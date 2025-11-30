import Foundation
import Speech
import AVFAudio
import AVFoundation

/// Protocol for speech recognition delegate
protocol SpeechRecognizerDelegate: AnyObject {
    func speechRecognizer(_ recognizer: SpeechRecognizer, didRecognizeText text: String, isFinal: Bool)
    func speechRecognizer(_ recognizer: SpeechRecognizer, didChangeState state: SpeechRecognizer.State)
    func speechRecognizer(_ recognizer: SpeechRecognizer, didEncounterError error: Error)
}

/// Speech recognition service using Apple's Speech framework
class SpeechRecognizer: NSObject, ObservableObject {
    
    // MARK: - State
    
    enum State: Equatable {
        case idle
        case preparing
        case recording
        case processing
        case error(String)
        
        var isRecording: Bool {
            return self == .recording
        }
        
        var statusText: String {
            switch self {
            case .idle: return "就绪"
            case .preparing: return "准备中..."
            case .recording: return "录音中..."
            case .processing: return "处理中..."
            case .error(let message): return "错误: \(message)"
            }
        }
    }
    
    // MARK: - Properties
    
    @Published private(set) var state: State = .idle
    @Published private(set) var transcribedText: String = ""
    @Published private(set) var isAuthorized: Bool = false
    
    weak var delegate: SpeechRecognizerDelegate?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var currentLanguage: RecognitionLanguage = .chinese
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupRecognizer(for: AppSettings.shared.language)
    }
    
    // MARK: - Public Methods
    
    /// Request authorization for speech recognition and microphone
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        var speechAuthorized = false
        var microphoneAuthorized = false
        
        let group = DispatchGroup()
        
        // Request speech recognition authorization
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechAuthorized = (status == .authorized)
            group.leave()
        }
        
        // Request microphone authorization
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            microphoneAuthorized = granted
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            let authorized = speechAuthorized && microphoneAuthorized
            self?.isAuthorized = authorized
            completion(authorized)
        }
    }
    
    /// Setup recognizer for a specific language
    func setupRecognizer(for language: RecognitionLanguage) {
        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: language.locale)
        speechRecognizer?.delegate = self
        
        guard let recognizer = speechRecognizer else {
            print("Speech recognizer not available for \(language.displayName)")
            return
        }
        
        if !recognizer.isAvailable {
            print("Speech recognizer not available")
            updateState(.error("语音识别不可用"))
        }
    }
    
    /// Change recognition language
    func changeLanguage(to language: RecognitionLanguage) {
        if state.isRecording {
            stopRecording()
        }
        setupRecognizer(for: language)
    }
    
    /// Start recording and recognizing speech
    func startRecording() {
        guard !state.isRecording else { return }
        
        // Check speech recognition permission first
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        guard speechStatus == .authorized else {
            if speechStatus == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    DispatchQueue.main.async {
                        if status == .authorized {
                            self?.startRecording()
                        } else {
                            self?.updateState(.error("需要语音识别权限"))
                        }
                    }
                }
            } else {
                updateState(.error("请在系统偏好设置 > 隐私 > 语音识别中授权"))
            }
            return
        }
        
        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard micStatus == .authorized else {
            if micStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    if granted {
                        DispatchQueue.main.async {
                            self?.startRecording()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.updateState(.error("需要麦克风权限"))
                        }
                    }
                }
            } else {
                updateState(.error("请在系统偏好设置 > 隐私 > 麦克风中授权"))
            }
            return
        }
        
        // Check if any microphone is available
        guard AVCaptureDevice.default(for: .audio) != nil else {
            updateState(.error("未找到麦克风设备"))
            return
        }
        
        print("Speech recognition authorized: \(speechStatus == .authorized)")
        print("Microphone authorized: \(micStatus == .authorized)")
        
        // Cancel any ongoing task
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // Clean up audio engine if needed
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        updateState(.preparing)
        transcribedText = ""
        
        // Configure the microphone input
        let inputNode = audioEngine.inputNode
        
        // IMPORTANT: We must use the hardware's native format for the tap
        // The tap format MUST match the hardware format - we cannot override it
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("Using hardware format: \(recordingFormat)")
        
        // Validate hardware format
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            updateState(.error("无效的硬件音频格式"))
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            updateState(.error("无法创建识别请求"))
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        // Use server-based recognition (more reliable) and enable auto-punctuation
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
            recognitionRequest.addsPunctuation = AppSettings.shared.autoPunctuation
        }
        
        // Start recognition task
        guard let speechRecognizer = speechRecognizer else {
            updateState(.error("语音识别器未初始化"))
            return
        }
        
        print("Starting recognition task with language: \(currentLanguage.rawValue)")
        print("Speech recognizer available: \(speechRecognizer.isAvailable)")
        
        // Install tap on the input node using the hardware's native format
        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            bufferCount += 1
            
            // Log audio level every 50 buffers (roughly every second) to verify audio input
            if bufferCount % 50 == 0 {
                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)
                
                if let channelData = channelData {
                    var sum: Float = 0
                    var peak: Float = 0
                    for i in 0..<frameLength {
                        let sample = abs(channelData[i])
                        sum += sample
                        peak = max(peak, sample)
                    }
                    let avgLevel = sum / Float(frameLength)
                    
                    // Convert to rough dB scale
                    let avgDb = 20 * log10(max(avgLevel, 0.00001))
                    let peakDb = 20 * log10(max(peak, 0.00001))
                    
                    print("🎤 Audio input - Avg: \(String(format: "%.1f", avgDb)) dB, Peak: \(String(format: "%.1f", peakDb)) dB (frames: \(frameLength))")
                    
                    if peak < 0.01 {
                        print("⚠️ Audio level very low - speak louder or check microphone!")
                    }
                }
            }
            
            self?.recognitionRequest?.append(buffer)
        }
        
        // Prepare and start the audio engine BEFORE starting the recognition task
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            print("Audio engine started successfully")
        } catch {
            inputNode.removeTap(onBus: 0)
            updateState(.error("无法启动音频引擎: \(error.localizedDescription)"))
            delegate?.speechRecognizer(self, didEncounterError: error)
            return
        }
        
        // Now start the recognition task AFTER audio engine is running
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Recognition error: \(error.localizedDescription)")
                let nsError = error as NSError
                print("Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            
            var isFinal = false
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                print("Recognized text: \(text), isFinal: \(result.isFinal)")
                self.transcribedText = text
                isFinal = result.isFinal
                
                DispatchQueue.main.async {
                    self.delegate?.speechRecognizer(self, didRecognizeText: text, isFinal: isFinal)
                }
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                if isFinal {
                    self.updateState(.idle)
                } else if let error = error {
                    // Check if it's a cancellation error or "no speech detected" (which is expected)
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 209 || nsError.code == 1101 || nsError.code == 1110) {
                        // Expected errors - user cancelled or no speech detected
                        print("Expected error, ignoring: \(nsError.code)")
                        self.updateState(.idle)
                    } else {
                        self.updateState(.error(error.localizedDescription))
                        self.delegate?.speechRecognizer(self, didEncounterError: error)
                    }
                }
            }
        }
        
        updateState(.recording)
    }
    
    /// Stop recording
    func stopRecording() {
        guard state.isRecording || state == .preparing else { return }
        
        updateState(.processing)
        
        // Stop audio engine first
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Safely remove tap only if it was installed
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // End the audio input
        recognitionRequest?.endAudio()
        
        // Give a moment for final results
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.state == .processing {
                // If we have text, type it out even if not marked as final
                if !self.transcribedText.isEmpty {
                    self.delegate?.speechRecognizer(self, didRecognizeText: self.transcribedText, isFinal: true)
                }
                self.updateState(.idle)
            }
        }
    }
    
    /// Toggle recording state
    func toggleRecording() {
        if state.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Get the final transcribed text
    func getFinalText() -> String {
        return transcribedText
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: State) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state = newState
            self.delegate?.speechRecognizer(self, didChangeState: newState)
            NotificationCenter.default.post(name: .recordingStateChanged, object: newState)
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            updateState(.error("语音识别暂时不可用"))
        } else if state == .error("语音识别暂时不可用") {
            updateState(.idle)
        }
    }
}

