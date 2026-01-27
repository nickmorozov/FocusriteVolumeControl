//
//  PopoverView.swift
//  FocusriteVolumeControl
//
//  Menu bar popover UI - minimal volume-focused design
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var volumeController: VolumeController
    var onOpenPreferences: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header with connection status
            HeaderView(volumeController: volumeController, onOpenPreferences: onOpenPreferences)

            Divider()

            if volumeController.isConnected {
                // Volume controls
                VolumeControlView(volumeController: volumeController)

                // Increment slider
                IncrementSliderView(volumeController: volumeController)
            } else {
                // Not connected
                NotConnectedView(volumeController: volumeController)
            }

            Divider()

            // Footer with shortcuts info and quit
            FooterView()
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var volumeController: VolumeController
    var onOpenPreferences: () -> Void

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Focusrite Control")
                    .font(.headline)

                Text(volumeController.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Refresh button
            Button(action: { volumeController.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")

            // Preferences button (cog icon)
            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Preferences")
        }
    }

    private var statusColor: Color {
        volumeController.isConnected ? .green : .red
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var volumeController: VolumeController

    // Local state for smooth slider dragging
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var pendingValue: Double? = nil  // Value waiting for backend confirmation

    /// The value to display - uses pending value until backend catches up
    private var displayValue: Double {
        if isDragging {
            return dragValue
        } else if let pending = pendingValue {
            // Show pending until backend confirms (within 1 dB tolerance)
            if abs(volumeController.playbackVolume - pending) < 1.5 {
                return volumeController.playbackVolume
            }
            return pending
        }
        return volumeController.playbackVolume
    }

    var body: some View {
        // Single row: [Mute] [Vol-] ---slider--- [Vol+]  -20 dB
        HStack(spacing: 8) {
            // Mute button - ZStack keeps both icons in layout to prevent shift
            Button(action: { volumeController.toggleMute() }) {
                ZStack {
                    Image(systemName: "speaker.slash")
                        .opacity(volumeController.playbackMuted ? 0 : 1)
                    Image(systemName: "speaker.slash.fill")
                        .opacity(volumeController.playbackMuted ? 1 : 0)
                }
                .foregroundColor(volumeController.playbackMuted ? .red : .primary)
            }
            .buttonStyle(.plain)
            .help(volumeController.playbackMuted ? "Unmute" : "Mute")

            // Volume down button
            Button(action: { volumeController.volumeDown() }) {
                Image(systemName: "speaker.wave.1")
            }
            .buttonStyle(.plain)
            .help("Volume Down")
            .disabled(volumeController.playbackMuted)

            // Volume slider
            Slider(
                value: Binding(
                    get: { displayValue },
                    set: { dragValue = $0 }
                ),
                in: -127...0,
                step: 1.0,
                onEditingChanged: { editing in
                    isDragging = editing
                    if editing {
                        // Start dragging - capture current value
                        dragValue = volumeController.playbackVolume
                        pendingValue = nil
                    } else {
                        // End dragging - commit final value
                        pendingValue = dragValue
                        volumeController.setPlaybackVolume(dragValue)
                    }
                }
            )
            .disabled(volumeController.playbackMuted)
            .onChange(of: volumeController.playbackVolume) { _, newValue in
                // Clear pending when backend confirms (within tolerance)
                if let pending = pendingValue, abs(newValue - pending) < 1.5 {
                    pendingValue = nil
                }
            }

            // Volume up button
            Button(action: { volumeController.volumeUp() }) {
                Image(systemName: "speaker.wave.3")
            }
            .buttonStyle(.plain)
            .help("Volume Up")
            .disabled(volumeController.playbackMuted)

            // Volume display
            Text(volumeString)
                .font(.system(.body, design: .monospaced))
                .frame(width: 55, alignment: .trailing)
        }
    }

    private var volumeString: String {
        if volumeController.playbackMuted {
            return "MUTE"
        } else {
            return String(format: "%.0f dB", displayValue)
        }
    }
}

// MARK: - Increment Slider View

struct IncrementSliderView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        HStack {
            Text("Increment:")
                .font(.caption)
                .foregroundColor(.secondary)

            Slider(
                value: $volumeController.stepSize,
                in: 1...10,
                step: 1
            )

            Text("\(Int(volumeController.stepSize))")
                .font(.system(.body, design: .monospaced))
                .frame(width: 20, alignment: .trailing)
        }
    }
}

// MARK: - Not Connected View

struct NotConnectedView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.yellow)

            Text("Not Connected")
                .font(.headline)

            Text(volumeController.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Connect") {
                volumeController.connect()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Footer View

struct FooterView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("F13/F14: Vol  F15: Mute")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    PopoverView(volumeController: VolumeController(), onOpenPreferences: {})
}
