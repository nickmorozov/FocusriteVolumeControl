//
//  PreferencesView.swift
//  FocusriteVolumeControl
//
//  Preferences window for app settings
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var volumeController: VolumeController
    @ObservedObject var shortcutManager = ShortcutManager.shared
    @ObservedObject var launchAtLogin = LaunchAtLoginManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("General")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        // Launch at Login toggle
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)

                            Text("Start automatically when you log in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }

                        // Keep FC2 Minimized toggle with subtitle
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Keep Focusrite Control 2 Minimized", isOn: $volumeController.keepFC2Minimized)

                            Text("Keeps the app out of your way")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }

                        // Ensure Direct Monitor On toggle with subtitle
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Ensure Direct Monitor On", isOn: $volumeController.ensureDirectMonitorOn)

                            Text("The app will NOT work with this disabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }

                        // Play Volume Sound toggle with subtitle
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Play Chime On Volume Change", isOn: $volumeController.playVolumeSound)

                            Text("Similar to system behaviour")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }

                        // Allow Gain toggle with subtitle
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Allow Gain (0 to +6 dB)", isOn: $volumeController.allowGain)

                            Text("Enable volume boost above unity gain")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }

                Divider()

                // Keyboard Shortcuts Section
                ShortcutsSectionView(shortcutManager: shortcutManager)
            }
            .padding()
        }
        .frame(width: 380, height: 470)
    }
}

#Preview {
    PreferencesView(volumeController: VolumeController())
}
