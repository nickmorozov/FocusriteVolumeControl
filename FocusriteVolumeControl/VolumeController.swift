//
//  VolumeController.swift
//  FocusriteVolumeControl
//
//  High-level volume control logic for Focusrite devices.
//  Uses a pluggable backend (AppleScript now, AES70 API later).
//

import Foundation
import Combine
import AppKit  // For NSSound

/// Manages volume, mute, and direct monitor controls
/// This is the Controller in our MVC architecture
class VolumeController: ObservableObject {

    // MARK: - Published State (for UI binding)

    @Published var playbackVolume: Double = 0.0  // dB
    @Published var playbackMuted: Bool = false

    @Published var input1Volume: Double = 0.0
    @Published var input1Muted: Bool = false

    @Published var input2Volume: Double = 0.0
    @Published var input2Muted: Bool = false

    @Published var directMonitorEnabled: Bool = false

    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Initializing..."

    // MARK: - Configuration

    @Published var stepSize: Double = 5.0  // Percentage per step (Normal speed)
    @Published var keepFC2Minimized: Bool = true  // Minimize FC2 on connect (user can unminimize manually)
    @Published var playVolumeSound: Bool = true  // Play system sound on volume change for audio feedback
    let minVolume: Double = -127.0  // FC2's actual minimum
    let maxVolume: Double = 0.0  // Unity gain, no boost allowed

    // MARK: - Private Properties

    private let backend: VolumeBackend
    private var cancellables = Set<AnyCancellable>()

    // Pre-mute volume for restore
    private var preMuteVolume: Double = -20.0

    // MARK: - Initialization

    init(backend: VolumeBackend) {
        self.backend = backend
        setupBindings()
    }

    /// Convenience init with default AppleScript backend
    convenience init() {
        self.init(backend: AppleScriptBackend())
    }

    private func setupBindings() {
        // Observe backend state changes
        // Use RunLoop.main.next to ensure updates happen after current view cycle
        backend.statePublisher
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] state in
                self?.updateFromBackendState(state)
            }
            .store(in: &cancellables)
    }

    private func updateFromBackendState(_ state: VolumeState) {
        // Only update if values actually changed to minimize view updates
        if playbackVolume != state.playbackVolume { playbackVolume = state.playbackVolume }
        // Derive muted state from volume level (volume-based mute)
        let isMuted = state.playbackVolume <= minVolume
        if playbackMuted != isMuted { playbackMuted = isMuted }
        if input1Volume != state.input1Volume { input1Volume = state.input1Volume }
        if input1Muted != state.input1Muted { input1Muted = state.input1Muted }
        if input2Volume != state.input2Volume { input2Volume = state.input2Volume }
        if input2Muted != state.input2Muted { input2Muted = state.input2Muted }
        if directMonitorEnabled != state.directMonitorEnabled { directMonitorEnabled = state.directMonitorEnabled }
        if isConnected != state.isConnected { isConnected = state.isConnected }
        if statusMessage != state.statusMessage { statusMessage = state.statusMessage }
    }

    // MARK: - Connection

    func connect() {
        Task {
            let result = await backend.connect()
            if case .error(let msg) = result {
                await MainActor.run {
                    self.statusMessage = msg
                    self.isConnected = false
                }
            } else {
                // Minimize FC2 after successful connect if setting is enabled
                let shouldMinimize = await MainActor.run { keepFC2Minimized }
                if shouldMinimize {
                    await backend.minimizeFC2IfNeeded()
                }
            }
        }
    }

    func disconnect() {
        backend.disconnect()
    }

    func refresh() {
        Task {
            _ = await backend.refresh()
        }
    }

    // MARK: - Playback Volume Control

    func setPlaybackVolume(_ newVolume: Double) {
        // FC2 only accepts integer dB values - round to nearest int
        let rounded = round(newVolume)
        let clamped = max(minVolume, min(maxVolume, rounded))
        // Dispatch async to avoid SwiftUI view update conflicts
        DispatchQueue.main.async {
            Task {
                let result = await self.backend.setPlaybackVolume(clamped)
                if case .error(let msg) = result {
                    print("Failed to set playback volume: \(msg)")
                } else {
                    await MainActor.run { self.playVolumeFeedback() }
                }
                await self.minimizeFC2IfNeeded()
            }
        }
    }

    /// Minimize FC2 if the setting is enabled
    private func minimizeFC2IfNeeded() async {
        let shouldMinimize = await MainActor.run { keepFC2Minimized }
        if shouldMinimize {
            await backend.minimizeFC2IfNeeded()
        }
    }

    /// Play system sound for volume feedback if enabled
    private func playVolumeFeedback() {
        guard playVolumeSound else { return }
        NSSound.beep()
    }

    func playbackVolumeUp() {
        if playbackMuted {
            // Unmute and restore previous volume
            unmute()
            return
        }
        // Step in percentage, ensure at least 1 dB change
        let currentDb = round(playbackVolume)
        let currentPercent = dbToPercent(currentDb)
        let newPercent = min(100, currentPercent + stepSize)
        var newDb = round(percentToDb(newPercent))

        // If rounding resulted in same dB, force at least 1 dB change
        if newDb <= currentDb && currentDb < maxVolume {
            newDb = currentDb + 1
        }
        if newDb > maxVolume { newDb = maxVolume }
        setPlaybackVolume(newDb)
    }

    func playbackVolumeDown() {
        if playbackMuted {
            return
        }
        // Step in percentage, ensure at least 1 dB change
        let currentDb = round(playbackVolume)
        let currentPercent = dbToPercent(currentDb)
        let newPercent = max(0, currentPercent - stepSize)
        var newDb = round(percentToDb(newPercent))

        // If rounding resulted in same dB, force at least 1 dB change
        if newDb >= currentDb && currentDb > minVolume {
            newDb = currentDb - 1
        }
        if newDb < minVolume { newDb = minVolume }

        if newDb <= minVolume {
            mute()
        } else {
            setPlaybackVolume(newDb)
        }
    }

    // MARK: - Mute Control (volume-based: min volume = muted)

    func toggleMute() {
        if playbackMuted {
            unmute()
        } else {
            mute()
        }
    }

    func mute() {
        // Save current volume before muting (only if not already at min)
        if playbackVolume > minVolume {
            preMuteVolume = playbackVolume
        }

        // Set to minimum volume (acts as mute)
        // playbackMuted will be derived from volume in updateFromBackendState
        setPlaybackVolume(minVolume)
    }

    func unmute() {
        // Restore previous volume
        // playbackMuted will be derived from volume in updateFromBackendState
        setPlaybackVolume(preMuteVolume)
    }

    // MARK: - Input 1 Control

    func setInput1Volume(_ newVolume: Double) {
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            _ = await backend.setInput1Volume(clamped)
            await minimizeFC2IfNeeded()
        }
    }

    func toggleInput1Mute() {
        Task {
            _ = await backend.setInput1Muted(!input1Muted)
            await minimizeFC2IfNeeded()
        }
    }

    // MARK: - Input 2 Control

    func setInput2Volume(_ newVolume: Double) {
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            _ = await backend.setInput2Volume(clamped)
            await minimizeFC2IfNeeded()
        }
    }

    func toggleInput2Mute() {
        Task {
            _ = await backend.setInput2Muted(!input2Muted)
            await minimizeFC2IfNeeded()
        }
    }

    // MARK: - Direct Monitor Control

    func toggleDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(!directMonitorEnabled)
            await minimizeFC2IfNeeded()
        }
    }

    func enableDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(true)
            await minimizeFC2IfNeeded()
        }
    }

    func disableDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(false)
            await minimizeFC2IfNeeded()
        }
    }

    // MARK: - dB to Percentage Conversion (Perceptual Curve)
    // 0% = -127 dB (silence), 50% = -16 dB (half volume), 100% = 0 dB (full)
    // Uses power curve where 50% of travel = -16 dB
    // Exponent ~0.197 satisfies: 127 * 0.5^0.197 - 127 = -16

    private let curveExponent: Double = 0.197  // Calculated for 50% = -16 dB with 127 range

    /// Convert dB to percentage (0-100) - perceptual curve
    func dbToPercent(_ db: Double) -> Double {
        // Inverse: percent = 100 * ((dB + 127) / 127)^(1/exponent)
        guard db < 0 else { return 100 }
        guard db > -127 else { return 0 }
        let normalized = (db + 127) / 127  // 0 to 1
        return max(0, min(100, 100 * pow(normalized, 1 / curveExponent)))
    }

    /// Convert percentage (0-100) to dB - perceptual curve
    func percentToDb(_ percent: Double) -> Double {
        // dB = 127 * (percent/100)^exponent - 127
        // At 50%: 127 * 0.5^0.197 - 127 ≈ -16 dB
        guard percent > 0 else { return -127 }
        guard percent < 100 else { return 0 }
        let p = percent / 100
        return max(-127, min(0, 127 * pow(p, curveExponent) - 127))
    }

    /// Get playback volume as percentage
    var playbackPercent: Double {
        get { dbToPercent(playbackVolume) }
    }

    /// Set playback volume from percentage
    func setPlaybackPercent(_ percent: Double) {
        setPlaybackVolume(percentToDb(percent))
    }

    // MARK: - Legacy Compatibility

    var volume: Double {
        get { playbackVolume }
        set { setPlaybackVolume(newValue) }
    }

    var isMuted: Bool {
        get { playbackMuted }
    }

    var isDirectMonitorEnabled: Bool {
        get { directMonitorEnabled }
    }

    func volumeUp() { playbackVolumeUp() }
    func volumeDown() { playbackVolumeDown() }
}
