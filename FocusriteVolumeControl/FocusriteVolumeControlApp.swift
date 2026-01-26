//
//  FocusriteVolumeControlApp.swift
//  FocusriteVolumeControl
//
//  Menu bar app for controlling Focusrite Scarlett volume
//

import SwiftUI

@main
struct FocusriteVolumeControlApp: App {
    // Use AppDelegate for menu bar functionality
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty Settings scene (required but not used for menu bar app)
        Settings {
            EmptyView()
        }
    }
}
