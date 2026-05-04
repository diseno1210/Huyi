import Carbon
import Foundation

enum ShortcutPreset: String, CaseIterable {
    case controlShiftA
    case controlShiftT
    case controlShiftS
    case optionShiftA
    case optionShiftS
    case commandShiftS
    case f1
    case f2
    case f3
    case f4
    case f5

    var title: String {
        switch self {
        case .controlShiftA: "Control+Shift+A"
        case .controlShiftT: "Control+Shift+T"
        case .controlShiftS: "Control+Shift+S"
        case .optionShiftA: "Option+Shift+A"
        case .optionShiftS: "Option+Shift+S"
        case .commandShiftS: "Command+Shift+S"
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlShiftA, .optionShiftA:
            UInt32(kVK_ANSI_A)
        case .controlShiftT:
            UInt32(kVK_ANSI_T)
        case .controlShiftS, .optionShiftS, .commandShiftS:
            UInt32(kVK_ANSI_S)
        case .f1:
            UInt32(kVK_F1)
        case .f2:
            UInt32(kVK_F2)
        case .f3:
            UInt32(kVK_F3)
        case .f4:
            UInt32(kVK_F4)
        case .f5:
            UInt32(kVK_F5)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlShiftA, .controlShiftT, .controlShiftS:
            UInt32(controlKey | shiftKey)
        case .optionShiftA, .optionShiftS:
            UInt32(optionKey | shiftKey)
        case .commandShiftS:
            UInt32(cmdKey | shiftKey)
        case .f1, .f2, .f3, .f4, .f5:
            0
        }
    }
}

final class AppSettings {
    private enum Key {
        static let translateShortcut = "translateShortcutPreset"
        static let screenshotShortcut = "screenshotShortcutPreset"
        static let inputTranslationShortcut = "inputTranslationShortcutPreset"
        static let localAIBaseURL = "localAIBaseURL"
        static let localAIModel = "localAIModel"
        static let localAIAPIKey = "localAIAPIKey"
        static let localAITimeout = "localAITimeout"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var translateShortcut: ShortcutPreset {
        get {
            preset(for: Key.translateShortcut, fallback: .f4)
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.translateShortcut)
        }
    }

    var screenshotShortcut: ShortcutPreset {
        get {
            preset(for: Key.screenshotShortcut, fallback: .f1)
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.screenshotShortcut)
        }
    }

    var inputTranslationShortcut: ShortcutPreset {
        get {
            preset(for: Key.inputTranslationShortcut, fallback: .f5)
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.inputTranslationShortcut)
        }
    }

    var localAIBaseURL: String {
        get {
            defaults.string(forKey: Key.localAIBaseURL) ?? "http://127.0.0.1:1234/v1"
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.localAIBaseURL)
        }
    }

    var localAIModel: String {
        get {
            if let savedModel = defaults.string(forKey: Key.localAIModel),
               !savedModel.isEmpty {
                return savedModel
            }
            return "local-model"
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.localAIModel)
        }
    }

    var localAIAPIKey: String {
        get {
            defaults.string(forKey: Key.localAIAPIKey) ?? ""
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.localAIAPIKey)
        }
    }

    var localAITimeout: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.localAITimeout)
            return value > 0 ? value : 20
        }
        set {
            defaults.set(max(1, newValue), forKey: Key.localAITimeout)
        }
    }

    private func preset(for key: String, fallback: ShortcutPreset) -> ShortcutPreset {
        guard let rawValue = defaults.string(forKey: key),
              let preset = ShortcutPreset(rawValue: rawValue)
        else {
            return fallback
        }
        return preset
    }
}
