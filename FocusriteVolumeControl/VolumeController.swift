//
//  VolumeController.swift
//  FocusriteVolumeControl
//
//  High-level volume control logic for Focusrite devices.
//  Uses a pluggable backend (AppleScript now, AES70 API later).
//

import Foundation
import Combine

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

    @Published var stepSize: Double = 3.0  // dB per step
    let minVolume: Double = -127.0
    let maxVolume: Double = 6.0

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
        backend.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateFromBackendState(state)
            }
            .store(in: &cancellables)
    }

    private func updateFromBackendState(_ state: VolumeState) {
        playbackVolume = state.playbackVolume
        playbackMuted = state.playbackMuted
        input1Volume = state.input1Volume
        input1Muted = state.input1Muted
        input2Volume = state.input2Volume
        input2Muted = state.input2Muted
        directMonitorEnabled = state.directMonitorEnabled
        isConnected = state.isConnected
        statusMessage = state.statusMessage
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
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            let result = await backend.setPlaybackVolume(clamped)
            if case .error(let msg) = result {
                print("Failed to set playback volume: \(msg)")
            }
        }
    }

    func playbackVolumeUp() {
        if playbackMuted {
            unmute()
            return
        }
        let newVolume = min(maxVolume, playbackVolume + stepSize)
        setPlaybackVolume(newVolume)
    }

    func playbackVolumeDown() {
        let newVolume = max(minVolume, playbackVolume - stepSize)
        setPlaybackVolume(newVolume)
    }

    // MARK: - Mute Control

    func toggleMute() {
        if playbackMuted {
            unmute()
        } else {
            mute()
        }
    }

    func mute() {
        // Save current volume before muting
        if playbackVolume > minVolume {
            preMuteVolume = playbackVolume
        }

        Task {
            let result = await backend.setPlaybackMuted(true)
            if case .error(let msg) = result {
                print("Failed to mute: \(msg)")
            }
        }
    }

    func unmute() {
        Task {
            let result = await backend.setPlaybackMuted(false)
            if case .error(let msg) = result {
                print("Failed to unmute: \(msg)")
            }
        }
    }

    // MARK: - Input 1 Control

    func setInput1Volume(_ newVolume: Double) {
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            _ = await backend.setInput1Volume(clamped)
        }
    }

    func toggleInput1Mute() {
        Task {
            _ = await backend.setInput1Muted(!input1Muted)
        }
    }

    // MARK: - Input 2 Control

    func setInput2Volume(_ newVolume: Double) {
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            _ = await backend.setInput2Volume(clamped)
        }
    }

    func toggleInput2Mute() {
        Task {
            _ = await backend.setInput2Muted(!input2Muted)
        }
    }

    // MARK: - Direct Monitor Control

    func toggleDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(!directMonitorEnabled)
        }
    }

    func enableDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(true)
        }
    }

    func disableDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(false)
        }
    }

    // MARK: - Legacy Compatibility (for existing UI)

    // Aliases for backward compatibility
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
