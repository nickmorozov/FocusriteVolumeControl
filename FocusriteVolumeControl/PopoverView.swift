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

    var body: some View {
        VStack(spacing: 12) {
            // Playback volume slider
            HStack {
                Button(action: { volumeController.toggleMute() }) {
                    Image(systemName: volumeController.playbackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(volumeController.playbackMuted ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help(volumeController.playbackMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { volumeController.playbackVolume },
                        set: { volumeController.setPlaybackVolume($0) }
                    ),
                    in: -70...6,
                    step: 1.0
                )
                .disabled(volumeController.playbackMuted)

                Text(volumeString)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 60, alignment: .trailing)
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
            return String(format: "%.0f dB", volumeController.playbackVolume)
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

            // Step size picker
            HStack {
                Text("Step:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $volumeController.stepSize) {
                    Text("1 dB").tag(1.0)
                    Text("3 dB").tag(3.0)
                    Text("6 dB").tag(6.0)
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
