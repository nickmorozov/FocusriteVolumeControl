//
//  PopoverView.swift
//  FocusriteVolumeControl
//
//  Menu bar popover UI
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var client: FocusriteClient
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(spacing: 16) {
            // Header with connection status
            HeaderView(client: client)

            Divider()

            if client.isApproved {
                // Volume controls
                VolumeControlView(volumeController: volumeController)

                Divider()

                // Additional controls
                AdditionalControlsView(volumeController: volumeController)
            } else if client.isConnected {
                // Waiting for approval
                ApprovalWaitingView()
            } else {
                // Not connected
                NotConnectedView(client: client)
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
    @ObservedObject var client: FocusriteClient

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(client.deviceModel ?? "Focusrite Control")
                    .font(.headline)

                Text(client.connectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        if client.isApproved {
            return .green
        } else if client.isConnected {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(spacing: 12) {
            // Volume slider
            HStack {
                Button(action: { volumeController.toggleMute() }) {
                    Image(systemName: volumeController.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(volumeController.isMuted ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help(volumeController.isMuted ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { volumeController.volume },
                        set: { volumeController.setVolume($0) }
                    ),
                    in: -70...6,
                    step: 0.5
                )
                .disabled(volumeController.isMuted)

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
        if volumeController.isMuted {
            return "MUTE"
        } else {
            return String(format: "%.1f dB", volumeController.volume)
        }
    }
}

// MARK: - Additional Controls View

struct AdditionalControlsView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        HStack {
            // Step size picker
            Picker("Step", selection: $volumeController.stepSize) {
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

// MARK: - Approval Waiting View

struct ApprovalWaitingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.yellow)

            Text("Waiting for Approval")
                .font(.headline)

            Text("Please approve this app in Focusrite Control 2:\nSettings → Remote Devices")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Not Connected View

struct NotConnectedView: View {
    @ObservedObject var client: FocusriteClient

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("Not Connected")
                .font(.headline)

            Button("Reconnect") {
                client.connect()
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
    PopoverView(
        client: FocusriteClient(),
        volumeController: VolumeController(client: FocusriteClient())
    )
}
