//
//  VolumeHUDWindow.swift
//  FocusriteVolumeControl
//
//  NSPanel-based floating HUD window that shows Focusrite volume changes.
//  Non-activating, click-through, floats above all windows including fullscreen.
//

import Cocoa
import SwiftUI

// MARK: - HUD Window (NSPanel subclass)

class VolumeHUDWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Wraps SwiftUI content in an NSVisualEffectView using the same .hudWindow
    /// material that macOS uses for floating overlay panels, so the appearance
    /// automatically tracks Apple's design language across OS updates.
    func setHUDContent<V: View>(_ rootView: V, size: NSSize) {
        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true

        // Round corners with a mask image to avoid the material's built-in border
        let radius: CGFloat = 14
        let maskImage = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        visualEffect.maskImage = maskImage

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        self.contentView = visualEffect
    }
}

// MARK: - HUD Panel Manager (singleton)

class VolumeHUDPanel {
    static let shared = VolumeHUDPanel()

    private var panel: VolumeHUDWindow?
    private let viewModel = VolumeHUDViewModel()
    private var dismissTimer: Timer?
    private var fadeOutWorkItem: DispatchWorkItem?

    private let fadeDuration: TimeInterval = 0.15
    private let dismissDelay: TimeInterval = 2.0
    private let fadeOutDuration: TimeInterval = 0.3

    private init() {}

    /// Update the HUD values without showing it (for Combine-driven updates while already visible)
    func update(volume: Double, isMuted: Bool, allowGain: Bool) {
        viewModel.volumeDb = volume
        viewModel.isMuted = isMuted
        viewModel.allowGain = allowGain
    }

    /// Show the HUD with current volume state (call from key/hotkey handlers)
    func show(volume: Double, isMuted: Bool, allowGain: Bool) {
        // Cancel any pending fade-out
        fadeOutWorkItem?.cancel()
        fadeOutWorkItem = nil

        // Update view model
        viewModel.volumeDb = volume
        viewModel.isMuted = isMuted
        viewModel.allowGain = allowGain

        // Create panel lazily
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        // Position at top-center of main screen
        positionPanel(panel)

        // Show with fade-in (only fade if not already visible)
        if !panel.isVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            panel.animator().alphaValue = 1
        }

        // Reset dismiss timer
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissDelay, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Fade out and hide the HUD
    func dismiss() {
        guard let panel else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil

        let workItem = DispatchWorkItem { [weak self] in
            panel.orderOut(nil)
            self?.fadeOutWorkItem = nil
        }
        fadeOutWorkItem = workItem

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            workItem.perform()
        }
    }

    // MARK: - Private

    private func createPanel() {
        let hudView = VolumeHUDView(viewModel: viewModel)
        let panelSize = NSSize(width: 280, height: 56)

        let panel = VolumeHUDWindow(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.level = NSWindow.Level.screenSaver  // Above everything including fullscreen
        panel.collectionBehavior = NSWindow.CollectionBehavior([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.setHUDContent(hudView, size: panelSize)

        self.panel = panel
    }

    private func positionPanel(_ panel: VolumeHUDWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        // Top-center of screen, below the notch / menu bar area
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 48
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
