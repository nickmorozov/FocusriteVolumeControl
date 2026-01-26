//
//  AppDelegate.swift
//  FocusriteVolumeControl
//
//  Menu bar app delegate
//

import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    let focusriteClient = FocusriteClient()
    var volumeController: VolumeController!

    private var cancellables = Set<AnyCancellable>()

    // Global event monitor for hotkeys
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize volume controller
        volumeController = VolumeController(client: focusriteClient)

        // Set up menu bar
        setupMenuBar()

        // Set up global hotkeys
        setupHotkeys()

        // Start Focusrite Control server if needed and connect
        startServerAndConnect()

        // Observe connection state to update icon
        focusriteClient.$isConnected
            .combineLatest(focusriteClient.$isApproved)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected, isApproved in
                self?.updateStatusIcon(connected: isConnected, approved: isApproved)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusriteClient.disconnect()
        removeHotkeys()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Volume")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.animates = true

        // Set content view
        let contentView = PopoverView(
            client: focusriteClient,
            volumeController: volumeController
        )
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Make popover the key window
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusIcon(connected: Bool, approved: Bool) {
        guard let button = statusItem.button else { return }

        let iconName: String
        if !connected {
            iconName = "speaker.slash"
        } else if !approved {
            iconName = "speaker.badge.exclamationmark"
        } else if volumeController.isMuted {
            iconName = "speaker.slash.fill"
        } else {
            iconName = "speaker.wave.2.fill"
        }

        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")
    }

    // MARK: - Server Management

    private func startServerAndConnect() {
        // Just connect directly - the server should be running if Focusrite Control 2 is installed
        // (We can't start the server from a sandboxed app as it requires sudo)
        focusriteClient.connect()
    }

    // MARK: - Global Hotkeys

    private func setupHotkeys() {
        // Monitor for media keys and custom shortcuts
        // Note: This requires Accessibility permissions on macOS

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func removeHotkeys() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // F13, F14, F15 keys (or customize as needed)
        switch event.keyCode {
        case 105: // F13
            volumeController.volumeDown()
        case 107: // F14
            volumeController.volumeUp()
        case 113: // F15
            volumeController.toggleMute()
        default:
            break
        }

        // Update icon on mute change
        updateStatusIcon(connected: focusriteClient.isConnected, approved: focusriteClient.isApproved)
    }
}
