import SwiftUI
import AppKit

/// Application delegate handling app lifecycle and services
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    
    // MARK: - Properties
    
    @Published var isRecording: Bool = false
    @Published var statusText: String = "就绪"
    @Published var lastTranscribedText: String = ""
    
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    
    let speechRecognizer = SpeechRecognizer()
    let hotKeyManager = HotKeyManager.shared
    let textInputSimulator = TextInputSimulator.shared
    let settings = AppSettings.shared
    let floatingPanel = FloatingPanelController.shared
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupHotKey()
        setupFloatingPanel()
        requestPermissions()
        
        // Set speech recognizer delegate
        speechRecognizer.delegate = self
    }
    
    private func setupFloatingPanel() {
        // Confirm button - type the text
        floatingPanel.onConfirm = { [weak self] in
            guard let self = self else { return }
            let text = self.floatingPanel.transcribedText
            if !text.isEmpty {
                print("Confirm: typing text")
                self.floatingPanel.hide()
                
                // Small delay to let the panel close
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.textInputSimulator.insertTextViaClipboard(text)
                }
            }
        }
        
        // Cancel button - discard and close
        floatingPanel.onCancel = { [weak self] in
            print("Cancel: discarding text")
            self?.floatingPanel.hide()
            self?.speechRecognizer.stopRecording()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        if speechRecognizer.state.isRecording {
            speechRecognizer.stopRecording()
        }
    }
    
    // MARK: - Status Bar Setup
    
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            updateStatusBarIcon(isRecording: false)
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Setup popover for settings
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient
        popover?.animates = true
    }
    
    private func updateStatusBarIcon(isRecording: Bool) {
        guard let button = statusBarItem?.button else { return }
        
        if isRecording {
            // Recording state - red microphone
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            if let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")?.withSymbolConfiguration(config) {
                button.image = image
                button.contentTintColor = .systemRed
            }
        } else {
            // Idle state - normal microphone
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            if let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Voice Input")?.withSymbolConfiguration(config) {
                button.image = image
                button.contentTintColor = .controlTextColor
            }
        }
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right click - show context menu
            showContextMenu()
        } else {
            // Left click - toggle recording or show popover
            if event.modifierFlags.contains(.option) {
                showPopover(sender)
            } else {
                toggleRecording()
            }
        }
    }
    
    private func showPopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(self))
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            
            // Activate app to receive keyboard events in popover
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Status
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recording toggle
        let recordTitle = isRecording ? "停止录音" : "开始录音"
        let recordItem = NSMenuItem(title: recordTitle, action: #selector(toggleRecordingMenuItem), keyEquivalent: "")
        recordItem.target = self
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Language submenu
        let languageMenu = NSMenu()
        for language in RecognitionLanguage.allCases {
            let langItem = NSMenuItem(title: language.displayName, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            langItem.target = self
            langItem.representedObject = language
            langItem.state = settings.language == language ? .on : .off
            languageMenu.addItem(langItem)
        }
        let languageItem = NSMenuItem(title: "语言", action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        
        // Hotkey display
        let hotkeyItem = NSMenuItem(title: "快捷键: \(settings.hotKeyConfig.displayString)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusBarItem?.menu = menu
        statusBarItem?.button?.performClick(nil)
        statusBarItem?.menu = nil
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleRecordingMenuItem() {
        toggleRecording()
    }
    
    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? RecognitionLanguage else { return }
        settings.language = language
        speechRecognizer.changeLanguage(to: language)
    }
    
    @objc private func showSettings() {
        guard let button = statusBarItem?.button else { return }
        showPopover(button)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Hotkey Setup
    
    private func setupHotKey() {
        hotKeyManager.onHotKeyPressed = { [weak self] in
            self?.toggleRecording()
        }
    }
    
    // MARK: - Recording Control
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Check permissions first
        guard speechRecognizer.isAuthorized else {
            requestPermissions()
            return
        }
        
        isRecording = true
        statusText = "录音中..."
        updateStatusBarIcon(isRecording: true)
        
        // Show floating panel
        floatingPanel.show()
        
        speechRecognizer.startRecording()
        
        // Visual feedback - brief flash
        if let button = statusBarItem?.button {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                button.animator().alphaValue = 0.5
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    button.animator().alphaValue = 1.0
                }
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        statusText = "处理中..."
        updateStatusBarIcon(isRecording: false)
        
        // Don't hide floating panel - wait for user to click confirm or cancel
        floatingPanel.isRecording = false
        
        speechRecognizer.stopRecording()
    }
    
    // MARK: - Permissions
    
    private func requestPermissions() {
        speechRecognizer.requestAuthorization { [weak self] authorized in
            if !authorized {
                self?.showPermissionAlert()
            }
        }
        
        // Check accessibility permissions
        if !textInputSimulator.checkAccessibilityPermissions() {
            textInputSimulator.requestAccessibilityPermissions()
        }
    }
    
    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要权限"
            alert.informativeText = "VoiceInput 需要麦克风和语音识别权限才能正常工作。请在系统偏好设置中授予这些权限。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统偏好设置")
            alert.addButton(withTitle: "稍后")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
        }
    }
}

// MARK: - SpeechRecognizerDelegate

extension AppDelegate: SpeechRecognizerDelegate {
    func speechRecognizer(_ recognizer: SpeechRecognizer, didRecognizeText text: String, isFinal: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.lastTranscribedText = text
            
            // Update floating panel with real-time text
            self.floatingPanel.updateText(text)
            self.floatingPanel.isRecording = !isFinal
            
            if isFinal && !text.isEmpty {
                print("Final text ready: \(text)")
                // Don't auto-type, wait for user to click confirm or cancel button
                self.statusText = "点击采用或取消"
            }
        }
    }
    
    func speechRecognizer(_ recognizer: SpeechRecognizer, didChangeState state: SpeechRecognizer.State) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.statusText = state.statusText
            self.isRecording = state.isRecording
            self.updateStatusBarIcon(isRecording: state.isRecording)
        }
    }
    
    func speechRecognizer(_ recognizer: SpeechRecognizer, didEncounterError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "错误: \(error.localizedDescription)"
            self?.isRecording = false
            self?.updateStatusBarIcon(isRecording: false)
        }
    }
}

