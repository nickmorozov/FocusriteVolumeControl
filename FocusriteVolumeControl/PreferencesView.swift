//
//  PreferencesView.swift
//  FocusriteVolumeControl
//
//  Preferences window for app settings
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
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

            Spacer()
        }
        .padding()
        .frame(width: 320, height: 220)
    }
}

#Preview {
    PreferencesView(volumeController: VolumeController())
}
