import Foundation
import SwiftUI
import Carbon

/// Supported languages for speech recognition
enum RecognitionLanguage: String, CaseIterable, Codable {
    case chinese = "zh-CN"
    case english = "en-US"
    
    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
    
    var locale: Locale {
        return Locale(identifier: rawValue)
    }
}

/// Key code constants for common keys
struct KeyCodes {
    static let v: UInt16 = 9
    static let space: UInt16 = 49
    static let returnKey: UInt16 = 36
    // Add more as needed
}

/// Hotkey configuration
struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32
    
    static let defaultConfig = HotKeyConfig(
        keyCode: KeyCodes.v,
        modifiers: UInt32(cmdKey | shiftKey)  // Cmd + Shift + V
    )
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        
        // Map key code to character
        let keyChar = keyCodeToString(keyCode)
        parts.append(keyChar)
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 10: "B", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'",
            40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "Space", 50: "`",
        ]
        return keyMap[keyCode] ?? "?"
    }
}

/// Application settings stored in UserDefaults
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let language = "recognitionLanguage"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let showNotifications = "showNotifications"
        static let autoPunctuation = "autoPunctuation"
    }
    
    @Published var language: RecognitionLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }
    
    @Published var hotKeyConfig: HotKeyConfig {
        didSet {
            defaults.set(hotKeyConfig.keyCode, forKey: Keys.hotKeyCode)
            defaults.set(hotKeyConfig.modifiers, forKey: Keys.hotKeyModifiers)
            NotificationCenter.default.post(name: .hotKeyConfigChanged, object: hotKeyConfig)
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }
    
    @Published var showNotifications: Bool {
        didSet {
            defaults.set(showNotifications, forKey: Keys.showNotifications)
        }
    }
    
    @Published var autoPunctuation: Bool {
        didSet {
            defaults.set(autoPunctuation, forKey: Keys.autoPunctuation)
        }
    }
    
    private init() {
        // Load saved settings or use defaults
        if let savedLanguage = defaults.string(forKey: Keys.language),
           let lang = RecognitionLanguage(rawValue: savedLanguage) {
            self.language = lang
        } else {
            self.language = .chinese
        }
        
        let savedKeyCode = defaults.object(forKey: Keys.hotKeyCode) as? UInt16 ?? HotKeyConfig.defaultConfig.keyCode
        let savedModifiers = defaults.object(forKey: Keys.hotKeyModifiers) as? UInt32 ?? HotKeyConfig.defaultConfig.modifiers
        self.hotKeyConfig = HotKeyConfig(keyCode: savedKeyCode, modifiers: savedModifiers)
        
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showNotifications = defaults.object(forKey: Keys.showNotifications) as? Bool ?? true
        self.autoPunctuation = defaults.object(forKey: Keys.autoPunctuation) as? Bool ?? true
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotKeyConfigChanged = Notification.Name("hotKeyConfigChanged")
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}

