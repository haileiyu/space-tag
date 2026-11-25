import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = MissionControlOverlay()
    private let hud = SwitchHUD()
    private let store = NameStore.shared

    private var showHUD: Bool {
        get { UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showHUD") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusTitle()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusTitle), name: .spaceNamesChanged, object: nil)

        overlay.start()

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    @objc private func spaceChanged() {
        updateStatusTitle()
        guard showHUD, !MissionControl.isOpen(), let space = Spaces.current() else { return }
        hud.flash(store.displayName(for: space))
    }

    @objc private func updateStatusTitle() {
        let name = Spaces.current().map { store.displayName(for: $0) } ?? "Space"
        statusItem.button?.title = name.count > 28 ? String(name.prefix(27)) + "…" : name
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let currentID = Spaces.activeSpaceID()
        let displays = Spaces.displays()

        let hint = NSMenuItem(title: "Click a Space to name it", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        for (i, display) in displays.enumerated() {
            if displays.count > 1 {
                menu.addItem(.separator())
                let header = NSMenuItem(title: "Display \(i + 1)", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }
            for space in display.spaces {
                let title = store.name(for: space).map { "\($0)   (\(space.defaultName))" } ?? space.defaultName
                let item = NSMenuItem(title: title, action: #selector(renameFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = space.key
                item.state = space.id == currentID ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let rename = NSMenuItem(title: "Rename Current Space…", action: #selector(renameCurrent), keyEquivalent: "r")
        rename.target = self
        menu.addItem(rename)

        let hudItem = NSMenuItem(title: "Show Name When Switching", action: #selector(toggleHUD), keyEquivalent: "")
        hudItem.target = self
        hudItem.state = showHUD ? .on : .off
        menu.addItem(hudItem)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !AXIsProcessTrusted() {
            menu.addItem(.separator())
            let ax = NSMenuItem(title: "⚠︎ Allow Accessibility (for Mission Control labels)…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WorkspaceTag", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func renameFromMenu(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let space = Spaces.all().first(where: { $0.key == key }) else { return }
        promptRename(space)
    }

    @objc private func renameCurrent() {
        guard let space = Spaces.current() else { return }
        promptRename(space)
    }

    private func promptRename(_ space: Space) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Name for \(space.defaultName)"
        alert.informativeText = "Shown in Mission Control and the menu bar. Leave empty to remove the name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = store.name(for: space) ?? ""
        field.placeholderString = "e.g. 📝 Notes"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            store.setName(field.stringValue, for: space)
        }
    }

    @objc private func toggleHUD() { showHUD.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Menu-bar-only apps have no main menu, so ⌘C / ⌘V / ⌘A would not work in the rename field.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
