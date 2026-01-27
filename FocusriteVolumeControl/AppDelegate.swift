//
//  AppDelegate.swift
//  FocusriteVolumeControl
//
//  Menu bar app delegate - intercepts system volume keys for Focusrite control
//
//  TODO:
//  1. add button to restart server
//  2. add menu with about and preferences
//  3. option to start on sys startup
//  4. option to restart server automatically if connection is lost

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

    // Volume controller with AppleScript backend
    var volumeController: VolumeController!

    private var cancellables = Set<AnyCancellable>()

    // CGEventTap for intercepting media keys
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize volume controller with AppleScript backend
        volumeController = VolumeController()

        // Set up menu bar
        setupMenuBar()

        // Set up media key interception (blocks system volume)
        setupMediaKeyTap()

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

        // Handle volume keys - return nil to block system handling
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            DispatchQueue.main.async {
                self.volumeController.volumeUp()
            }
            return nil  // Block system volume

        case NX_KEYTYPE_SOUND_DOWN:
            DispatchQueue.main.async {
                self.volumeController.volumeDown()
            }
            return nil  // Block system volume

        case NX_KEYTYPE_MUTE:
            DispatchQueue.main.async {
                self.volumeController.toggleMute()
            }
            return nil  // Block system mute

        default:
            return Unmanaged.passRetained(event)
        }
    }
}
