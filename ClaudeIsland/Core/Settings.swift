//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }

    var displayName: String {
        NSLocalizedString(rawValue, comment: "")
    }
}

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "")
        case .english:
            return NSLocalizedString("English", comment: "")
        case .chinese:
            return NSLocalizedString("Chinese", comment: "")
        }
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([self.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let hideInFullscreen = "hideInFullscreen"
        static let autoHideNoActiveSessions = "autoHideNoActiveSessions"
        static let smartSuppression = "smartSuppression"
        static let collapseOnMouseLeave = "collapseOnMouseLeave"
        static let showUsageSummary = "showUsageSummary"
        static let appLanguage = "appLanguage"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    static var hideInFullscreen: Bool {
        get { defaults.object(forKey: Keys.hideInFullscreen) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.hideInFullscreen) }
    }

    static var autoHideNoActiveSessions: Bool {
        get { defaults.object(forKey: Keys.autoHideNoActiveSessions) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoHideNoActiveSessions) }
    }

    static var smartSuppression: Bool {
        get { defaults.object(forKey: Keys.smartSuppression) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.smartSuppression) }
    }

    static var collapseOnMouseLeave: Bool {
        get { defaults.object(forKey: Keys.collapseOnMouseLeave) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.collapseOnMouseLeave) }
    }

    static var showUsageSummary: Bool {
        get { defaults.object(forKey: Keys.showUsageSummary) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showUsageSummary) }
    }

    // MARK: - App Language

    static var appLanguage: AppLanguage {
        get {
            guard let rawValue = defaults.string(forKey: Keys.appLanguage),
                  let language = AppLanguage(rawValue: rawValue) else {
                return .system // Default to system
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
            newValue.apply()
        }
    }
}
