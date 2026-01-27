//
//  ShortcutRecorderView.swift
//  FocusriteVolumeControl
//
//  A view for recording keyboard shortcuts
//

import SwiftUI
import AppKit

// MARK: - Shortcut Recorder View

struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @ObservedObject var shortcutManager: ShortcutManager
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(action.displayName)
                .frame(width: 100, alignment: .leading)

            ShortcutRecorderButton(
                shortcut: shortcutManager.shortcuts[action] ?? nil,
                isRecording: $isRecording,
                onShortcutRecorded: { shortcut in
                    shortcutManager.setShortcut(shortcut, for: action)
                }
            )
            .frame(width: 140)

            Button(action: {
                shortcutManager.resetToDefault(for: action)
            }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Reset to default")
            .opacity(isDefault ? 0.3 : 1.0)
            .disabled(isDefault)
        }
    }

    private var isDefault: Bool {
        let current = shortcutManager.shortcuts[action] ?? nil
        let defaultShortcut = action.defaultShortcut
        return current == defaultShortcut
    }
}

// MARK: - Shortcut Recorder Button

struct ShortcutRecorderButton: View {
    let shortcut: KeyboardShortcut?
    @Binding var isRecording: Bool
    let onShortcutRecorded: (KeyboardShortcut?) -> Void

    var body: some View {
        Button(action: {
            isRecording = true
        }) {
            HStack {
                if isRecording {
                    Text("Press shortcut...")
                        .foregroundColor(.secondary)
                } else {
                    Text(shortcut?.displayString ?? "Not Set")
                        .foregroundColor(shortcut == nil ? .secondary : .primary)
                }
                Spacer()
                if !isRecording && shortcut != nil {
                    Button(action: {
                        onShortcutRecorded(nil)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .background(
            ShortcutRecorderEventHandler(
                isRecording: $isRecording,
                onShortcutRecorded: onShortcutRecorded
            )
        )
    }
}

// MARK: - Event Handler (NSViewRepresentable)

struct ShortcutRecorderEventHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onShortcutRecorded: (KeyboardShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { shortcut in
            onShortcutRecorded(shortcut)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

// MARK: - NSView for Key Event Handling

class ShortcutRecorderNSView: NSView {
    var onShortcutRecorded: ((KeyboardShortcut) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape cancels recording
        if event.keyCode == 53 { // Escape key
            onCancel?()
            return
        }

        // Ignore modifier-only key presses
        let modifierOnlyKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Modifier key codes
        if modifierOnlyKeys.contains(event.keyCode) {
            return
        }

        // Create shortcut from event
        let shortcut = KeyboardShortcut(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection([.control, .option, .shift, .command]),
            isMediaKey: false,
            mediaKeyType: nil
        )

        onShortcutRecorded?(shortcut)
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't handle modifier-only changes
    }
}

// MARK: - Shortcuts Section View

struct ShortcutsSectionView: View {
    @ObservedObject var shortcutManager: ShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            Text("By default, system volume keys are used. Click to set a custom shortcut.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRecorderView(action: action, shortcutManager: shortcutManager)
                }
            }

            HStack {
                Spacer()
                Button("Reset All to Defaults") {
                    shortcutManager.resetAllToDefaults()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
}
