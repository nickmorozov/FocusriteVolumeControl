//
//  AppDelegate.swift
//  FocusriteVolumeControl
//
//  Menu bar app delegate - intercepts system volume keys for Focusrite control
//
//  TODO:
//  1. option to start on sys startup
//  2. option to restart server automatically if connection is lost

import Cocoa
import SwiftUI
import Combine

// Media key codes (from IOKit/hidsystem/ev_keymap.h)
private let NX_KEYTYPE_SOUND_UP: Int = 0
private let NX_KEYTYPE_SOUND_DOWN: Int = 1
private let NX_KEYTYPE_MUTE: Int = 7

// System-defined event type (NX_SYSDEFINED = 14)
private let kCGEventTypeSystemDefined: CGEventType = CGEventType(rawValue: 14)!

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var statusMenu: NSMenu!
    private var preferencesWindow: NSWindow?

    // Volume controller with AppleScript backend
    var volumeController: VolumeController!

    private var cancellables = Set<AnyCancellable>()

    // CGEventTap for intercepting media keys
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Custom hotkey manager for non-media-key shortcuts
    private var hotkeyManager: HotkeyManager!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize volume controller with AppleScript backend
        volumeController = VolumeController()

        // Set up menu bar
        setupMenuBar()
        setupStatusMenu()

        // Set up media key interception (blocks system volume)
        setupMediaKeyTap()

        // Set up custom hotkey manager for non-media-key shortcuts
        setupHotkeyManager()

        // Connect to FC2 via AppleScript
        volumeController.connect()

        // Observe connection state to update icon
        volumeController.$isConnected
            .combineLatest(volumeController.$playbackMuted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected, isMuted in
                self?.updateStatusIcon(connected: isConnected, muted: isMuted)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeController.disconnect()
        removeMediaKeyTap()
        hotkeyManager?.stop()
    }

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onVolumeUp = { [weak self] in
            self?.volumeController.volumeUp()
        }
        hotkeyManager.onVolumeDown = { [weak self] in
            self?.volumeController.volumeDown()
        }
        hotkeyManager.onMute = { [weak self] in
            self?.volumeController.toggleMute()
        }
        hotkeyManager.onDirectMonitor = { [weak self] in
            self?.volumeController.toggleDirectMonitor()
        }
        hotkeyManager.start()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Volume")
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            // Enable right-click
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 180)
        popover.behavior = .transient
        popover.animates = true

        // Set content view with preferences callback
        let contentView = PopoverView(volumeController: volumeController) { [weak self] in
            self?.showPreferences()
        }
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupStatusMenu() {
        statusMenu = NSMenu()

        // About
        let aboutItem = NSMenuItem(title: "About Focusrite Volume Control", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        statusMenu.addItem(aboutItem)

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesMenuItem), keyEquivalent: ",")
        prefsItem.target = self
        statusMenu.addItem(prefsItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Reconnect
        let reconnectItem = NSMenuItem(title: "Reconnect to Focusrite Control 2", action: #selector(reconnect), keyEquivalent: "r")
        reconnectItem.target = self
        statusMenu.addItem(reconnectItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: show menu
            popover.performClose(nil)
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil  // Clear so left-click works next time
        } else {
            // Left-click: toggle popover
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make window key but clear focus so no button has focus ring
            if let window = popover.contentViewController?.view.window {
                window.makeKey()
                window.makeFirstResponder(nil)
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Focusrite Volume Control"
        alert.informativeText = "Control your Focusrite Scarlett Solo volume with system media keys.\n\nVersion 1.0\n\n© 2026"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showPreferencesMenuItem() {
        showPreferences()
    }

    func showPreferences() {
        // Close popover if open
        popover.performClose(nil)

        // If window already exists, just bring it to front
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create preferences window
        let prefsView = PreferencesView(volumeController: volumeController)
        let hostingController = NSHostingController(rootView: prefsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 580))
        window.center()
        window.isReleasedWhenClosed = false

        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reconnect() {
        volumeController.disconnect()
        volumeController.connect()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusIcon(connected: Bool, muted: Bool) {
        guard let button = statusItem.button else { return }

        let iconName: String
        if !connected {
            iconName = "speaker.slash"
        } else if muted {
            iconName = "speaker.slash.fill"
        } else {
            iconName = "speaker.wave.2.fill"
        }

        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")
    }

    // MARK: - Media Key Tap (intercepts and blocks system volume)

    private func setupMediaKeyTap() {
        // Event mask for system-defined events (media keys)
        let eventMask: CGEventMask = 1 << kCGEventTypeSystemDefined.rawValue

        // Create event tap - requires Accessibility permissions
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // Can modify/block events
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return appDelegate.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            print("⚠️ Failed to create event tap - grant Accessibility permissions in System Settings")
            return
        }

        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("✅ Media key tap installed - system volume keys now control Focusrite only")
    }

    private func removeMediaKeyTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Only handle system-defined events
        guard type == kCGEventTypeSystemDefined else {
            return Unmanaged.passRetained(event)
        }

        // Convert to NSEvent to parse media key data
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        // Check for media key subtype (8 = NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }

        // Parse key data from data1
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let keyDown = keyState == 0x0A

        // Only handle key down
        guard keyDown else {
            return nil  // Suppress key up too
        }

        // Handle volume keys - pass through to system for HUD, also control Focusrite
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            DispatchQueue.main.async {
                self.volumeController.volumeUp()
            }
            return Unmanaged.passRetained(event)  // Let system show HUD

        case NX_KEYTYPE_SOUND_DOWN:
            DispatchQueue.main.async {
                self.volumeController.volumeDown()
            }
            return Unmanaged.passRetained(event)  // Let system show HUD

        case NX_KEYTYPE_MUTE:
            DispatchQueue.main.async {
                self.volumeController.toggleMute()
            }
            return Unmanaged.passRetained(event)  // Let system show HUD

        default:
            return Unmanaged.passRetained(event)
        }
    }
}
