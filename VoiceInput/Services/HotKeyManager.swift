import Foundation
import Carbon
import AppKit

/// Manager for global hotkey registration and handling
class HotKeyManager: ObservableObject {
    
    // MARK: - Properties
    
    static let shared = HotKeyManager()
    
    @Published private(set) var isRegistered: Bool = false
    @Published private(set) var currentConfig: HotKeyConfig
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var hotKeyID: EventHotKeyID
    
    /// Callback when hotkey is pressed
    var onHotKeyPressed: (() -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        self.currentConfig = AppSettings.shared.hotKeyConfig
        self.hotKeyID = EventHotKeyID(signature: OSType(0x564F4943), id: 1) // "VOIC"
        
        setupEventHandler()
        registerHotKey()
        
        // Listen for config changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyConfigChanged(_:)),
            name: .hotKeyConfigChanged,
            object: nil
        )
    }
    
    deinit {
        unregisterHotKey()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
    
    // MARK: - Public Methods
    
    /// Update hotkey configuration
    func updateConfig(_ config: HotKeyConfig) {
        unregisterHotKey()
        currentConfig = config
        registerHotKey()
    }
    
    /// Check if accessibility permissions are granted
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Request accessibility permissions
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Private Methods
    
    private func setupEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if status == noErr && hotKeyID.id == manager.hotKeyID.id {
                    DispatchQueue.main.async {
                        manager.onHotKeyPressed?()
                    }
                    return noErr
                }
                
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        if status != noErr {
            print("Failed to install event handler: \(status)")
        }
    }
    
    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
        
        // Convert modifiers from Carbon format
        var carbonModifiers: UInt32 = 0
        if currentConfig.modifiers & UInt32(cmdKey) != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if currentConfig.modifiers & UInt32(shiftKey) != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }
        if currentConfig.modifiers & UInt32(optionKey) != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        if currentConfig.modifiers & UInt32(controlKey) != 0 {
            carbonModifiers |= UInt32(controlKey)
        }
        
        let status = RegisterEventHotKey(
            UInt32(currentConfig.keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            isRegistered = true
            print("Hotkey registered: \(currentConfig.displayString)")
        } else {
            isRegistered = false
            print("Failed to register hotkey: \(status)")
        }
    }
    
    private func unregisterHotKey() {
        guard let ref = hotKeyRef else { return }
        
        let status = UnregisterEventHotKey(ref)
        if status == noErr {
            hotKeyRef = nil
            isRegistered = false
            print("Hotkey unregistered")
        } else {
            print("Failed to unregister hotkey: \(status)")
        }
    }
    
    @objc private func hotKeyConfigChanged(_ notification: Notification) {
        if let config = notification.object as? HotKeyConfig {
            updateConfig(config)
        }
    }
}

// MARK: - Hotkey Recorder View Helper

/// Helper class for recording custom hotkey combinations
class HotKeyRecorder: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var recordedConfig: HotKeyConfig?
    
    private var localMonitor: Any?
    
    func startRecording() {
        isRecording = true
        recordedConfig = nil
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            
            // Ignore modifier-only key presses
            let keyCode = event.keyCode
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Various modifier keys
            if modifierOnlyKeyCodes.contains(keyCode) {
                return event
            }
            
            // Check if at least one modifier is pressed
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifierFlags.contains(.command) || modifierFlags.contains(.control) ||
                  modifierFlags.contains(.option) || modifierFlags.contains(.shift) else {
                return event
            }
            
            // Convert NSEvent modifiers to Carbon modifiers
            var carbonModifiers: UInt32 = 0
            if modifierFlags.contains(.command) {
                carbonModifiers |= UInt32(cmdKey)
            }
            if modifierFlags.contains(.shift) {
                carbonModifiers |= UInt32(shiftKey)
            }
            if modifierFlags.contains(.option) {
                carbonModifiers |= UInt32(optionKey)
            }
            if modifierFlags.contains(.control) {
                carbonModifiers |= UInt32(controlKey)
            }
            
            self.recordedConfig = HotKeyConfig(keyCode: keyCode, modifiers: carbonModifiers)
            self.stopRecording()
            
            return nil // Consume the event
        }
    }
    
    func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    func applyRecordedConfig() {
        guard let config = recordedConfig else { return }
        AppSettings.shared.hotKeyConfig = config
    }
}

