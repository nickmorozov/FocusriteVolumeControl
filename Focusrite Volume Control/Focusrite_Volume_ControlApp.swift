//
//  Focusrite_Volume_ControlApp.swift
//  Focusrite Volume Control
//
//  Menu bar app for controlling Focusrite Scarlett volume
//

import SwiftUI

@main
struct Focusrite_Volume_ControlApp: App {
    // Use AppDelegate for menu bar functionality
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty Settings scene (required but not used for menu bar app)
        Settings {
            EmptyView()
        }
    }
}
