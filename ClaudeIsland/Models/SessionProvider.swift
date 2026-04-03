import Foundation

enum SessionProvider: String, Equatable, Sendable {
    case claude
    case opencode

    var displayName: String {
        switch self {
        case .claude:
            return NSLocalizedString("Claude Code", comment: "")
        case .opencode:
            return NSLocalizedString("OpenCode", comment: "")
        }
    }

    var supportsHooks: Bool {
        self == .claude
    }

    var supportsInlineMessaging: Bool {
        // Both Claude Code and OpenCode support inline messaging
        true
    }
}
