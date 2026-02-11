//
//  OnboardingView.swift
//  FocusriteVolumeControl
//
//  Permission onboarding wizard — shown on launch until both
//  Accessibility and Automation permissions are granted.
//

import SwiftUI
import Combine
import ApplicationServices

// MARK: - Permission Checks

func isAccessibilityGranted() -> Bool {
    AXIsProcessTrusted()
}

func isAutomationGranted() -> Bool {
    let script = "tell application \"System Events\" to return name of first process"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func areAllPermissionsGranted() -> Bool {
    isAccessibilityGranted() && isAutomationGranted()
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var accessibilityGranted = false
    @State private var automationGranted = false
    @State private var isChecking = false

    var onContinue: () -> Void

    private var allGranted: Bool {
        accessibilityGranted && automationGranted
    }

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Focusrite Volume Control Setup")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This app needs two permissions to work correctly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            // Permission steps
            VStack(spacing: 16) {
                PermissionRow(
                    step: 1,
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Intercepts your Mac's volume keys so they control your Focusrite instead of the built-in speakers.",
                    isGranted: accessibilityGranted,
                    buttonTitle: "Grant Accessibility Access",
                    action: requestAccessibility,
                    fallbackAction: openAccessibilitySettings,
                    fallbackTitle: "Open System Settings"
                )

                Divider()
                    .padding(.horizontal, 12)

                PermissionRow(
                    step: 2,
                    icon: "gearshape.2.fill",
                    title: "Automation",
                    description: "Controls Focusrite Control 2 via Apple Events to read and set your volume levels.",
                    isGranted: automationGranted,
                    buttonTitle: "Test Automation Access",
                    action: requestAutomation,
                    fallbackAction: openAutomationSettings,
                    fallbackTitle: "Open System Settings"
                )
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)

            Divider()
                .padding(.horizontal, 24)

            // Footer buttons
            HStack {
                Button(action: recheckPermissions) {
                    HStack(spacing: 4) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Re-check Permissions")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allGranted)
            }
            .padding(24)
        }
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            recheckPermissions()
        }
        .onReceive(timer) { _ in
            refreshStatus()
        }
    }

    // MARK: - Actions

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Recheck after a short delay to pick up the change
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            refreshStatus()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestAutomation() {
        // Running an osascript targeting System Events triggers the automation prompt
        Task.detached {
            let script = "tell application \"System Events\" to return name of first process"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            await MainActor.run {
                refreshStatus()
            }
        }
    }

    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func recheckPermissions() {
        isChecking = true
        // Run checks off main thread since osascript is synchronous
        Task.detached {
            let accGranted = isAccessibilityGranted()
            let autoGranted = isAutomationGranted()
            await MainActor.run {
                accessibilityGranted = accGranted
                automationGranted = autoGranted
                isChecking = false
            }
        }
    }

    private func refreshStatus() {
        Task.detached {
            let accGranted = isAccessibilityGranted()
            let autoGranted = isAutomationGranted()
            await MainActor.run {
                accessibilityGranted = accGranted
                automationGranted = autoGranted
            }
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let step: Int
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let action: () -> Void
    let fallbackAction: () -> Void
    let fallbackTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Step \(step): \(title)")
                        .font(.headline)

                    Spacer()

                    Text(isGranted ? "Granted" : "Required")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isGranted ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        )
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isGranted {
                    HStack(spacing: 8) {
                        Button(buttonTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button(fallbackTitle, action: fallbackAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
