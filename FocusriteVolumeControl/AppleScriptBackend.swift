//
//  AppleScriptBackend.swift
//  FocusriteVolumeControl
//
//  Controls Focusrite Control 2 via osascript (command-line AppleScript).
//  Uses the same approach as the working Node.js volume-control.js script.
//

import Foundation
import Combine

/// AppleScript-based volume control backend using osascript subprocess
class AppleScriptBackend: VolumeBackend {

    // MARK: - Constants

    private let fc2Process = "Focusrite Control 2"

    // MARK: - State

    private var _state = VolumeState()
    private let stateSubject = CurrentValueSubject<VolumeState, Never>(VolumeState())

    var statePublisher: AnyPublisher<VolumeState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var state: VolumeState {
        _state
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Connection

    func connect() async -> VolumeResult {
        // Ensure FC2 is running and Direct tab is active
        let result = await ensureDirectTab()
        if case .error = result {
            return result
        }

        // Refresh state
        return await refresh()
    }

    func disconnect() {
        _state.isConnected = false
        _state.statusMessage = "Disconnected"
        stateSubject.send(_state)
    }

    func refresh() async -> VolumeResult {
        do {
            let playbackVol = try await readSliderValue(channel: "Playback 1 - 2")
            let playbackMute = try await readMuteState(channel: "Playback 1 - 2")
            let input1Vol = try await readSliderValue(channel: "Analogue 1")
            let input1Mute = try await readMuteState(channel: "Analogue 1")
            let input2Vol = try await readSliderValue(channel: "Analogue 2")
            let input2Mute = try await readMuteState(channel: "Analogue 2")
            let directMon = try await readDirectMonitorState()

            _state.playbackVolume = playbackVol
            _state.playbackMuted = playbackMute
            _state.input1Volume = input1Vol
            _state.input1Muted = input1Mute
            _state.input2Volume = input2Vol
            _state.input2Muted = input2Mute
            _state.directMonitorEnabled = directMon
            _state.isConnected = true
            _state.statusMessage = "Connected"
            stateSubject.send(_state)
            return .success
        } catch {
            _state.isConnected = false
            _state.statusMessage = error.localizedDescription
            stateSubject.send(_state)
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Playback Volume

    func getPlaybackVolume() async -> Result<Double, Error> {
        do {
            let vol = try await readSliderValue(channel: "Playback 1 - 2")
            return .success(vol)
        } catch {
            return .failure(error)
        }
    }

    func setPlaybackVolume(_ db: Double) async -> VolumeResult {
        do {
            try await setSliderValue(channel: "Playback 1 - 2", db: db)
            _state.playbackVolume = db
            _state.playbackMuted = false
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func setPlaybackMuted(_ muted: Bool) async -> VolumeResult {
        do {
            try await setMuteState(channel: "Playback 1 - 2", muted: muted)
            _state.playbackMuted = muted
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Input 1

    func getInput1Volume() async -> Result<Double, Error> {
        do {
            let vol = try await readSliderValue(channel: "Analogue 1")
            return .success(vol)
        } catch {
            return .failure(error)
        }
    }

    func setInput1Volume(_ db: Double) async -> VolumeResult {
        do {
            try await setSliderValue(channel: "Analogue 1", db: db)
            _state.input1Volume = db
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func setInput1Muted(_ muted: Bool) async -> VolumeResult {
        do {
            try await setMuteState(channel: "Analogue 1", muted: muted)
            _state.input1Muted = muted
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Input 2

    func getInput2Volume() async -> Result<Double, Error> {
        do {
            let vol = try await readSliderValue(channel: "Analogue 2")
            return .success(vol)
        } catch {
            return .failure(error)
        }
    }

    func setInput2Volume(_ db: Double) async -> VolumeResult {
        do {
            try await setSliderValue(channel: "Analogue 2", db: db)
            _state.input2Volume = db
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func setInput2Muted(_ muted: Bool) async -> VolumeResult {
        do {
            try await setMuteState(channel: "Analogue 2", muted: muted)
            _state.input2Muted = muted
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Direct Monitor

    func setDirectMonitorEnabled(_ enabled: Bool) async -> VolumeResult {
        do {
            try await setDirectMonitor(enabled: enabled)
            _state.directMonitorEnabled = enabled
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - AppleScript Commands via osascript

    /// Ensure FC2 is running and Direct tab is active
    private func ensureDirectTab() async -> VolumeResult {
        let script = """
        tell application "System Events"
            if not (exists process "\(fc2Process)") then
                error "Focusrite Control 2 is not running"
            end if
            tell process "\(fc2Process)"
                click checkbox "Direct" of group "Navigation bar" of window "\(fc2Process)"
            end tell
        end tell
        """

        do {
            _ = try await runOsascript(script)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Read slider value from a channel group
    private func readSliderValue(channel: String) async throws -> Double {
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of slider "Level" of group "\(channel)" of group 5 of window "\(fc2Process)"
            end tell
        end tell
        """

        let result = try await runOsascript(script)
        return parseDbValue(result)
    }

    /// Set slider value for a channel group
    private func setSliderValue(channel: String, db: Double) async throws {
        let dbString = formatDbValue(db)
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set value of slider "Level" of group "\(channel)" of group 5 of window "\(fc2Process)" to "\(dbString)"
            end tell
        end tell
        """

        _ = try await runOsascript(script)
    }

    /// Read mute state from a channel group
    private func readMuteState(channel: String) async throws -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of checkbox "Mute" of group "\(channel)" of group 5 of window "\(fc2Process)"
            end tell
        end tell
        """

        let result = try await runOsascript(script)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Set mute state for a channel group
    private func setMuteState(channel: String, muted: Bool) async throws {
        let targetValue = muted ? 1 : 0
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set cb to checkbox "Mute" of group "\(channel)" of group 5 of window "\(fc2Process)"
                if (value of cb) is not \(targetValue) then
                    click cb
                end if
            end tell
        end tell
        """

        _ = try await runOsascript(script)
    }

    /// Read Direct Monitor state
    private func readDirectMonitorState() async throws -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of checkbox "Direct Monitor" of window "\(fc2Process)"
            end tell
        end tell
        """

        let result = try await runOsascript(script)
        // FC2 returns "true" or "false" as strings
        return result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    /// Set Direct Monitor state
    private func setDirectMonitor(enabled: Bool) async throws {
        // FC2 returns true/false for checkbox values
        let targetValue = enabled ? "true" : "false"
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set cb to checkbox "Direct Monitor" of window "\(fc2Process)"
                if (value of cb) is not \(targetValue) then
                    click cb
                end if
            end tell
        end tell
        """

        _ = try await runOsascript(script)
    }

    // MARK: - osascript Execution

    /// Run AppleScript via osascript subprocess (same as Node.js script)
    private func runOsascript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: VolumeBackendError.appleScriptError(errorMessage))
                    } else {
                        let output = String(data: outputData, encoding: .utf8) ?? ""
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Utilities

    /// Parse dB string like "-6dB" or "0dB" to Double
    private func parseDbValue(_ str: String) -> Double {
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let numStr = cleaned.replacingOccurrences(of: "dB", with: "")
                            .replacingOccurrences(of: " ", with: "")
        return Double(numStr) ?? 0.0
    }

    /// Format Double to dB string like "-6dB"
    private func formatDbValue(_ db: Double) -> String {
        return "\(Int(round(db)))dB"
    }
}
