//
//  AppDelegate.swift
//  FocusriteVolumeControl
//
//  Menu bar app delegate
//
//  TODO:
//  1. add button to restart server
//  2. add menu with about and preferences
//  3. by default system vol+-/mute should be used with options to override and reset
//  4. option to start on sys startup
//  5. option to restart server automatically if connection is lost
//

import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // Volume controller with AppleScript backend
    var volumeController: VolumeController!

    private var cancellables = Set<AnyCancellable>()

    // Global event monitor for hotkeys
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize volume controller with AppleScript backend
        volumeController = VolumeController()

        // Set up menu bar
        setupMenuBar()

        // Set up global hotkeys
        setupHotkeys()

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
        popover.contentSize = NSSize(width: 280, height: 250)
        popover.behavior = .transient
        popover.animates = true

        // Set content view
        let contentView = PopoverView(volumeController: volumeController)
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
        updateStatusIcon(connected: volumeController.isConnected, muted: volumeController.playbackMuted)
    }
}
