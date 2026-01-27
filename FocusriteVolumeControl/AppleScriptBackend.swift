//
//  AppleScriptBackend.swift
//  FocusriteVolumeControl
//
//  AppleScript-based backend for controlling FC2 via macOS Accessibility APIs.
//  This approach works by automating the FC2 UI directly.
//

import Foundation
import Combine

/// AppleScript-based volume control backend
/// Controls Focusrite Control 2 via UI automation
class AppleScriptBackend: VolumeBackend {

    // MARK: - Constants

    private let fc2Process = "Focusrite Control 2"
    private let fc2Window = "Focusrite Control 2"

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
        // (a) Ensure FC2 is running, Direct tab is active, window is minimized
        let result = await ensureFC2Ready()
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
        // Read all current values
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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

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
        let result = await ensureFC2Ready()
        if case .error = result { return result }

        do {
            try await setDirectMonitor(enabled: enabled)
            _state.directMonitorEnabled = enabled
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - AppleScript Helpers

    /// (a) Boilerplate: Ensure FC2 is running, Direct tab active, window exists (minimized OK)
    private func ensureFC2Ready() async -> VolumeResult {
        let script = """
        tell application "System Events"
            -- Check if FC2 is running
            if not (exists process "\(fc2Process)") then
                -- Try to launch it
                tell application "\(fc2Process)" to activate
                delay 2
                if not (exists process "\(fc2Process)") then
                    error "Focusrite Control 2 is not running"
                end if
            end if

            tell process "\(fc2Process)"
                -- Ensure window exists
                if (count of windows) = 0 then
                    -- Bring app to front to create window
                    set frontmost to true
                    delay 0.5
                end if

                -- Check if main window exists
                if not (exists window "\(fc2Window)") then
                    error "Could not find Focusrite Control 2 window"
                end if

                -- Click Direct tab if not already selected
                set directCheckbox to checkbox "Direct" of group "Navigation bar" of window "\(fc2Window)"
                if value of directCheckbox is 0 then
                    click directCheckbox
                    delay 0.3
                end if

                -- Minimize if not already (optional - keeps it out of the way)
                -- We actually want to keep it accessible but not in the way
                -- Minimizing might break accessibility, so we just leave it
            end tell
        end tell
        return "ready"
        """

        do {
            _ = try await runAppleScript(script)
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
                set sliderValue to value of slider "Level" of group "\(channel)" of group 5 of window "\(fc2Window)"
                return sliderValue
            end tell
        end tell
        """

        let result = try await runAppleScript(script)
        return parseDbValue(result)
    }

    /// Set slider value for a channel group
    private func setSliderValue(channel: String, db: Double) async throws {
        let dbString = formatDbValue(db)
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set value of slider "Level" of group "\(channel)" of group 5 of window "\(fc2Window)" to "\(dbString)"
            end tell
        end tell
        """

        _ = try await runAppleScript(script)
    }

    /// Read mute state from a channel group
    private func readMuteState(channel: String) async throws -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of checkbox "Mute" of group "\(channel)" of group 5 of window "\(fc2Window)"
            end tell
        end tell
        """

        let result = try await runAppleScript(script)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Set mute state for a channel group
    private func setMuteState(channel: String, muted: Bool) async throws {
        let targetValue = muted ? 1 : 0
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set cb to checkbox "Mute" of group "\(channel)" of group 5 of window "\(fc2Window)"
                if (value of cb) is not \(targetValue) then
                    click cb
                end if
            end tell
        end tell
        """

        _ = try await runAppleScript(script)
    }

    /// Read Direct Monitor state
    private func readDirectMonitorState() async throws -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of checkbox "Direct Monitor" of window "\(fc2Window)"
            end tell
        end tell
        """

        let result = try await runAppleScript(script)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Set Direct Monitor state
    private func setDirectMonitor(enabled: Bool) async throws {
        let targetValue = enabled ? 1 : 0
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set cb to checkbox "Direct Monitor" of window "\(fc2Window)"
                if (value of cb) is not \(targetValue) then
                    click cb
                end if
            end tell
        end tell
        """

        _ = try await runAppleScript(script)
    }

    // MARK: - Utilities

    /// Run AppleScript and return result
    private func runAppleScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)

                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: VolumeBackendError.appleScriptError(message))
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }

    /// Parse dB string like "-6dB" or "0dB" to Double
    private func parseDbValue(_ str: String) -> Double {
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove "dB" suffix and parse
        let numStr = cleaned.replacingOccurrences(of: "dB", with: "")
                            .replacingOccurrences(of: " ", with: "")
        return Double(numStr) ?? 0.0
    }

    /// Format Double to dB string like "-6dB"
    private func formatDbValue(_ db: Double) -> String {
        return "\(Int(round(db)))dB"
    }
}
