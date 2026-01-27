//
//  LaunchAtLogin.swift
//  FocusriteVolumeControl
//
//  Manages Launch at Login functionality using SMAppService (macOS 13+)
//

import Foundation
import ServiceManagement
import Combine

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                enable()
            } else {
                disable()
            }
        }
    }

    private init() {
        // Read current state from system
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func enable() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            print("Failed to enable launch at login: \(error)")
            // Revert the published value if registration failed
            DispatchQueue.main.async {
                self.isEnabled = false
            }
        }
    }

    private func disable() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            print("Failed to disable launch at login: \(error)")
            // Revert the published value if unregistration failed
            DispatchQueue.main.async {
                self.isEnabled = true
            }
        }
    }

    /// Refresh the status from the system
    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
