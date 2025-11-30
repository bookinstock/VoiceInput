import Foundation
import AppKit
import Carbon

/// Service for simulating text input into the currently focused text field
class TextInputSimulator {
    
    // MARK: - Singleton
    
    static let shared = TextInputSimulator()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Type the given text into the currently focused text field
    /// - Parameter text: The text to type
    /// - Parameter delay: Optional delay between characters (in seconds)
    func typeText(_ text: String, delay: TimeInterval = 0) {
        guard !text.isEmpty else { return }
        
        if delay > 0 {
            typeTextWithDelay(text, delay: delay)
        } else {
            typeTextImmediate(text)
        }
    }
    
    /// Insert text using clipboard (faster for large texts)
    /// - Parameter text: The text to insert
    func insertTextViaClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        
        print("insertTextViaClipboard: \(text)")
        
        // Set new content to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        print("Clipboard set success: \(success)")
        
        // Delay to ensure clipboard is ready
        usleep(150000) // 150ms
        
        // Simulate Cmd+V using AppleScript (more reliable)
        print("Simulating Cmd+V...")
        simulatePaste()
        print("Cmd+V simulated")
        
        // Don't restore clipboard - let user keep the text
    }
    
    // MARK: - Private Methods
    
    /// Type text immediately using CGEvents
    private func typeTextImmediate(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            typeCharacter(char, source: source)
        }
    }
    
    /// Type text with delay between characters
    private func typeTextWithDelay(_ text: String, delay: TimeInterval) {
        let characters = Array(text)
        var index = 0
        
        Timer.scheduledTimer(withTimeInterval: delay, repeats: true) { timer in
            guard index < characters.count else {
                timer.invalidate()
                return
            }
            
            self.typeCharacter(characters[index], source: nil)
            index += 1
        }
    }
    
    /// Type a single character
    private func typeCharacter(_ char: Character, source: CGEventSource?) {
        let utf16 = Array(String(char).utf16)
        
        // Create key down event with the Unicode character
        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            keyDownEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyDownEvent.post(tap: .cghidEventTap)
        }
        
        // Create key up event
        if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            keyUpEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUpEvent.post(tap: .cghidEventTap)
        }
    }
    
    /// Simulate a key press with modifiers using AppleScript (more reliable)
    func simulatePaste() {
        // Use AppleScript to simulate Cmd+V - this is more reliable than CGEvent
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                // Fall back to CGEvent method
                simulateKeyPressCGEvent(keyCode: 9, modifiers: .maskCommand)
            } else {
                print("Paste simulated via AppleScript")
            }
        }
    }
    
    /// Simulate a key press with modifiers using CGEvent (fallback)
    private func simulateKeyPressCGEvent(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down with modifier
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
            print("Key down posted: \(keyCode)")
        } else {
            print("Failed to create key down event")
            return
        }
        
        // Delay between key down and key up
        usleep(50000) // 50ms
        
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
            print("Key up posted: \(keyCode)")
        } else {
            print("Failed to create key up event")
        }
        
        // Wait for paste to complete
        usleep(100000) // 100ms
    }
    
    /// Check if accessibility permissions are granted
    func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request accessibility permissions with prompt
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

// MARK: - Text Processing Helpers

extension TextInputSimulator {
    
    /// Process text before typing (add punctuation, formatting, etc.)
    func processText(_ text: String, settings: AppSettings) -> String {
        var processed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Auto-capitalize first letter if needed
        if !processed.isEmpty {
            let first = processed.removeFirst()
            processed = first.uppercased() + processed
        }
        
        return processed
    }
    
    /// Add punctuation based on context
    func addAutoPunctuation(_ text: String, language: RecognitionLanguage) -> String {
        var result = text
        
        // Simple punctuation rules
        let lastChar = result.last
        let needsPunctuation = lastChar != nil && ![".", "!", "?", "。", "！", "？", ",", "，"].contains(String(lastChar!))
        
        if needsPunctuation {
            // Add period based on language
            switch language {
            case .chinese:
                result += "。"
            case .english:
                result += "."
            }
        }
        
        return result
    }
}

