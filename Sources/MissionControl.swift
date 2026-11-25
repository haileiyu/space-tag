import Cocoa
import ApplicationServices

/// One Space button in the Mission Control Spaces bar.
struct MCButton {
    let frame: CGRect   // Cocoa screen coordinates (origin bottom-left)
    let title: String
}

struct MCDisplay {
    let displayID: CGDirectDisplayID
    let buttons: [MCButton]
}

enum MissionControl {
    static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    /// True while the Dock shows a full-screen window at the Mission Control layers.
    /// Uses only owner PID, layer and bounds, so it needs no Screen Recording permission.
    /// App Exposé can match too; `readSpacesBar()` filters it out (it has no Spaces bar).
    static func isOpen() -> Bool {
        guard let pid = dockPID,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let sizes = NSScreen.screens.map { $0.frame.size }
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 18 || layer == 20,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b)
            else { return false }
            return sizes.contains { $0 == rect.size }
        }
    }

    /// Reads the Spaces bar from the Dock's accessibility tree:
    /// Dock → "mc" → "mc.display" → "mc.spaces" → "mc.spaces.list" → buttons.
    /// Returns nil when there is no Spaces bar or no Accessibility permission.
    static func readSpacesBar() -> [MCDisplay]? {
        guard AXIsProcessTrusted(), let pid = dockPID else { return nil }
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.25)
        guard let mc = children(dock).first(where: { identifier($0) == "mc" }) else { return nil }

        var result: [MCDisplay] = []
        for display in children(mc) where identifier(display) == "mc.display" {
            let displayID = (attribute(display, "AXDisplayID") as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            guard let spaces = children(display).last(where: { identifier($0) == "mc.spaces" }),
                  let list = children(spaces).last(where: { identifier($0) == "mc.spaces.list" })
            else { continue }
            let buttons = children(list).compactMap { b -> MCButton? in
                guard let f = frame(b) else { return nil }
                let title = (attribute(b, kAXDescriptionAttribute) as? String)
                    ?? (attribute(b, kAXTitleAttribute) as? String) ?? ""
                return MCButton(frame: toCocoa(f), title: title)
            }
            result.append(MCDisplay(displayID: displayID, buttons: buttons))
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - AX helpers

    private static func attribute(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        attribute(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func identifier(_ e: AXUIElement) -> String? {
        attribute(e, kAXIdentifierAttribute) as? String
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = attribute(e, kAXPositionAttribute), let s = attribute(e, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pos),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// AX uses top-left origin on the primary screen; Cocoa uses bottom-left.
    private static func toCocoa(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
