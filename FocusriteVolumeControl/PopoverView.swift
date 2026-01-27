//
//  PopoverView.swift
//  FocusriteVolumeControl
//
//  Menu bar popover UI
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(spacing: 16) {
            // Header with connection status
            HeaderView(volumeController: volumeController)

            Divider()

            if volumeController.isConnected {
                // Volume controls
                VolumeControlView(volumeController: volumeController)

                Divider()

                // Additional controls
                AdditionalControlsView(volumeController: volumeController)
            } else {
                // Not connected
                NotConnectedView(volumeController: volumeController)
            }

            Divider()

            // Footer with shortcuts info and quit
            FooterView()
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var volumeController: VolumeController

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
        VStack(spacing: 12) {
            // Playback volume slider (dB scale, integer values)
            HStack {
                Button(action: { volumeController.toggleMute() }) {
                    Image(systemName: volumeController.playbackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(volumeController.playbackMuted ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help(volumeController.playbackMuted ? "Unmute" : "Mute")

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

                Text(volumeString)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 55, alignment: .trailing)
            }

            // Volume buttons
            HStack(spacing: 20) {
                Button(action: { volumeController.volumeDown() }) {
                    Label("Volume Down", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.downArrow, modifiers: [])

                Button(action: { volumeController.volumeUp() }) {
                    Label("Volume Up", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.upArrow, modifiers: [])
            }
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

// MARK: - Additional Controls View

struct AdditionalControlsView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(spacing: 8) {
            // Direct Monitor toggle
            Toggle("Direct Monitor", isOn: Binding(
                get: { volumeController.directMonitorEnabled },
                set: { _ in volumeController.toggleDirectMonitor() }
            ))

            // Keep FC2 Minimized toggle
            Toggle("Keep FC2 Minimized", isOn: $volumeController.keepFC2Minimized)
                .help("Minimize Focusrite Control 2 on connect")

            // Volume sound feedback toggle
            Toggle("Play Volume Sound", isOn: $volumeController.playVolumeSound)
                .help("Play system sound on volume change")

            // Speed picker
            HStack {
                Text("Speed:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { volumeController.stepSize },
                    set: { newValue in
                        DispatchQueue.main.async {
                            volumeController.stepSize = newValue
                        }
                    }
                )) {
                    Text("Slow").tag(3.0)
                    Text("Normal").tag(5.0)
                    Text("Fast").tag(8.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Spacer()
            }
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
    PopoverView(volumeController: VolumeController())
}
