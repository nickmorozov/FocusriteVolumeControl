//
//  HotkeyManager.swift
//  FocusriteVolumeControl
//
//  Global hotkey registration for custom keyboard shortcuts
//

import Cocoa
import Combine

class HotkeyManager {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shortcutManager: ShortcutManager
    private var cancellables = Set<AnyCancellable>()

    // Action handlers
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?
    var onMute: (() -> Void)?
    var onDirectMonitor: (() -> Void)?

    init(shortcutManager: ShortcutManager = .shared) {
        self.shortcutManager = shortcutManager

        // Observe shortcut changes to update handlers
        shortcutManager.$shortcuts
            .sink { [weak self] _ in
                self?.updateMonitors()
            }
            .store(in: &cancellables)
    }

    func start() {
        updateMonitors()
    }

    func stop() {
        removeMonitors()
    }

    private func updateMonitors() {
        removeMonitors()

        // Check if any custom (non-media-key) shortcuts are configured
        let hasCustomShortcuts = ShortcutAction.allCases.contains { action in
            if let shortcut = shortcutManager.shortcut(for: action) {
                return !shortcut.isMediaKey && shortcut.keyCode != nil
            }
            return false
        }

        guard hasCustomShortcuts else { return }

        // Add global monitor for key down events
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Add local monitor for when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil  // Consume the event
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])

        // Check each action's shortcut
        for action in ShortcutAction.allCases {
            guard let shortcut = shortcutManager.shortcut(for: action),
                  !shortcut.isMediaKey,
                  let shortcutKeyCode = shortcut.keyCode,
                  shortcutKeyCode == keyCode,
                  shortcut.modifiers == modifiers else {
                continue
            }

            // Found a match - execute the action
            DispatchQueue.main.async { [weak self] in
                self?.executeAction(action)
            }
            return true
        }

        return false
    }

    private func executeAction(_ action: ShortcutAction) {
        switch action {
        case .volumeUp:
            onVolumeUp?()
        case .volumeDown:
            onVolumeDown?()
        case .mute:
            onMute?()
        case .directMonitor:
            onDirectMonitor?()
        }
    }

    deinit {
        removeMonitors()
    }
}
