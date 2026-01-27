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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("General")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
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
                    }
                }

                Divider()

                // Keyboard Shortcuts Section
                ShortcutsSectionView(shortcutManager: shortcutManager)
            }
            .padding()
        }
        .frame(width: 380, height: 420)
    }
}

#Preview {
    PreferencesView(volumeController: VolumeController())
}
