import Cocoa

// Private CoreGraphics (SkyLight) calls. macOS has no public API for Spaces.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") private func CGSGetActiveSpace(_ cid: Int32) -> Int
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

struct Space {
    let id: Int              // ManagedSpaceID (changes after reboot)
    let uuid: String         // stable across reboots for desktops
    let isFullscreen: Bool
    let displayID: CGDirectDisplayID
    let position: Int        // 1-based order on its display, same order as Mission Control
    let desktopNumber: Int?  // "Desktop N" number for normal desktops

    /// Key used to store the name.
    var key: String { uuid.isEmpty ? "display-\(displayID)-\(position)" : uuid }

    var defaultName: String {
        if let n = desktopNumber { return "Desktop \(n)" }
        return Spaces.fullscreenTitles[id] ?? "Full Screen"
    }
}

struct DisplaySpaces {
    let displayID: CGDirectDisplayID
    let spaces: [Space]
}

enum Spaces {
    private static let cid = CGSMainConnectionID()

    /// Titles of full-screen spaces as Mission Control shows them (filled in by MissionControl).
    static var fullscreenTitles: [Int: String] = [:]

    static func activeSpaceID() -> Int { CGSGetActiveSpace(cid) }

    static func displays() -> [DisplaySpaces] {
        guard let raw = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return [] }
        var desktopCount = 0
        return raw.map { d in
            let displayID = displayID(forIdentifier: d["Display Identifier"] as? String ?? "Main")
            let list = d["Spaces"] as? [[String: Any]] ?? []
            let spaces = list.enumerated().map { (i, s) -> Space in
                let full = (s["type"] as? Int ?? 0) == 4
                if !full { desktopCount += 1 }
                return Space(id: s["ManagedSpaceID"] as? Int ?? 0,
                             uuid: s["uuid"] as? String ?? "",
                             isFullscreen: full,
                             displayID: displayID,
                             position: i + 1,
                             desktopNumber: full ? nil : desktopCount)
            }
            return DisplaySpaces(displayID: displayID, spaces: spaces)
        }
    }

    static func all() -> [Space] { displays().flatMap(\.spaces) }

    static func current() -> Space? {
        let id = activeSpaceID()
        return all().first { $0.id == id }
    }

    private static func displayID(forIdentifier ident: String) -> CGDirectDisplayID {
        if ident == "Main" { return CGMainDisplayID() }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        for id in ids.prefix(Int(count)) {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let str = CFUUIDCreateString(nil, uuid) as String? else { continue }
            if str.caseInsensitiveCompare(ident) == .orderedSame { return id }
        }
        return CGMainDisplayID()
    }
}
