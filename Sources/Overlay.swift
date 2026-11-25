import Cocoa

/// A click-through rounded label that floats above everything, Mission Control included.
/// Windows are created once at launch and kept ordered front with alpha 0.
/// While Mission Control is open we only change alpha, frame and text.
final class PillWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")
    private let fontSize: CGFloat

    init(fontSize: CGFloat, cornerRadius: CGFloat) {
        self.fontSize = fontSize
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 0.92).cgColor
        bg.layer?.cornerRadius = cornerRadius
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        contentView = bg

        label.font = .systemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        bg.addSubview(label)

        alphaValue = 0
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `text` centered at `center`, no wider than `maxWidth`.
    func show(_ text: String, center: CGPoint, maxWidth: CGFloat, padding: CGFloat = 10) {
        label.stringValue = text
        let textSize = label.intrinsicContentSize
        let height = ceil(fontSize * 1.25) + padding
        let width = min(maxWidth, ceil(textSize.width) + padding * 2)
        let rect = CGRect(x: round(center.x - width / 2), y: round(center.y - height / 2), width: width, height: height)
        if frame != rect { setFrame(rect, display: false) }
        label.frame = CGRect(x: padding / 2, y: (height - textSize.height) / 2, width: width - padding, height: textSize.height)
        contentView?.needsDisplay = true
        alphaValue = 1
    }

    func hide() {
        if alphaValue != 0 { alphaValue = 0 }
    }
}

/// Puts each Space's name on top of its "Desktop N" label in Mission Control.
final class MissionControlOverlay {
    private var pills: [PillWindow] = (0..<32).map { _ in PillWindow(fontSize: 13, cornerRadius: 7) }
    /// Used when Accessibility access is missing: one line listing all names.
    private let legend = PillWindow(fontSize: 15, cornerRadius: 10)
    private var timer: Timer?
    private var wasOpen = false
    private var lastPlacements: [Placement] = []
    private var stableReads = 0

    private struct Placement: Equatable {
        let text: String
        let center: CGPoint
        let maxWidth: CGFloat
    }

    func start() { schedule(after: 0.15) }

    private func schedule(after interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in self?.tick() }
        timer?.tolerance = interval * 0.2
    }

    private func tick() {
        guard MissionControl.isOpen() else {
            if wasOpen { hideAll(); wasOpen = false }
            schedule(after: 0.15)
            return
        }
        wasOpen = true

        if let bar = MissionControl.readSpacesBar() {
            legend.hide()
            let placements = computePlacements(bar)
            // Show labels only after two equal reads, so they don't jump during animations.
            if placements == lastPlacements {
                stableReads += 1
            } else {
                stableReads = 0
                lastPlacements = placements
                hidePills()
            }
            if stableReads == 1 {
                apply(placements)
                debugLog(bar)
            }
        } else if !AXIsProcessTrusted() {
            showLegend()
        } else {
            hideAll() // e.g. App Exposé: no Spaces bar
        }
        schedule(after: 0.07)
    }

    private func computePlacements(_ bar: [MCDisplay]) -> [Placement] {
        let displays = Spaces.displays()
        var result: [Placement] = []
        for mcDisplay in bar {
            let match = displays.first { $0.displayID == mcDisplay.displayID }
                ?? (displays.count == 1 ? displays.first : nil)
            // Buttons follow the same order as the Spaces list. Skip if counts differ (e.g. mid-change).
            guard let spaces = match?.spaces, spaces.count == mcDisplay.buttons.count else { continue }
            for (space, button) in zip(spaces, mcDisplay.buttons) {
                if space.isFullscreen, !button.title.isEmpty { Spaces.fullscreenTitles[space.id] = button.title }
                guard let name = NameStore.shared.name(for: space) else { continue }
                // Cover the "Desktop N" caption at the bottom of the button.
                let f = button.frame
                let center = CGPoint(x: f.midX, y: f.minY + 11)
                result.append(Placement(text: name, center: center, maxWidth: max(f.width + 24, 80)))
            }
        }
        return result
    }

    private func apply(_ placements: [Placement]) {
        for (i, pill) in pills.enumerated() {
            if i < placements.count {
                let p = placements[i]
                pill.show(p.text, center: p.center, maxWidth: p.maxWidth, padding: 10)
            } else {
                pill.hide()
            }
        }
    }

    private func showLegend() {
        hidePills()
        let named = Spaces.all().compactMap { s in NameStore.shared.name(for: s).map { "\(s.defaultName): \($0)" } }
        guard !named.isEmpty, let screen = NSScreen.main else { legend.hide(); return }
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 175)
        legend.show(named.joined(separator: "   ·   "), center: center, maxWidth: screen.frame.width - 80, padding: 18)
    }

    /// `defaults write local.workspacetag debugLog -bool true` writes Spaces bar frames to
    /// ~/Library/Logs/WorkspaceTag.log each time the labels are placed.
    private func debugLog(_ bar: [MCDisplay]) {
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        var lines = ["\(Date()) spaces=\(Spaces.all().count)"]
        for d in bar {
            lines.append("display \(d.displayID): \(d.buttons.count) buttons")
            for b in d.buttons { lines.append("  \(b.title) \(b.frame)") }
        }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WorkspaceTag.log")
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func hidePills() { pills.forEach { $0.hide() } }

    private func hideAll() {
        hidePills()
        legend.hide()
        lastPlacements = []
        stableReads = 0
    }
}

/// Big name in the middle of the screen for a moment after a Space switch.
final class SwitchHUD {
    private let pill = PillWindow(fontSize: 34, cornerRadius: 16)
    private var hideWork: DispatchWorkItem?

    func flash(_ text: String) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        hideWork?.cancel()
        pill.show(text, center: CGPoint(x: screen.frame.midX, y: screen.frame.midY), maxWidth: screen.frame.width - 100, padding: 36)
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                self?.pill.animator().alphaValue = 0
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}
