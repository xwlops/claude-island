import AppKit
import CoreGraphics

struct DisplayModeDetector {
    static func isFrontmostAppFullscreen(on screen: NSScreen?) -> Bool {
        guard let screen,
              let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let targetPid = frontmostApp.processIdentifier
        let targetFrame = screen.frame
        let tolerance: CGFloat = 8

        for window in windowList {
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPid == targetPid,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }

            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )

            if abs(rect.width - targetFrame.width) <= tolerance &&
                abs(rect.height - targetFrame.height) <= tolerance {
                return true
            }
        }

        return false
    }
}
