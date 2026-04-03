import Foundation

enum SessionProvider: String, Equatable, Sendable {
    case claude
    case opencode

    var displayName: String {
        switch self {
        case .claude:
            return "Claude Code"
        case .opencode:
            return "OpenCode"
        }
    }

    var supportsHooks: Bool {
        self == .claude
    }

    var supportsInlineMessaging: Bool {
        self == .claude
    }
}
