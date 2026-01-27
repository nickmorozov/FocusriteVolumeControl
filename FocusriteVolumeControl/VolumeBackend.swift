//
//  VolumeBackend.swift
//  FocusriteVolumeControl
//
//  Protocol defining the interface for volume control backends.
//  This allows swapping between AppleScript UI automation and future AES70 API.
//

import Foundation
import Combine

/// Result of a volume operation
enum VolumeResult {
    case success
    case error(String)
}

/// Current state of the volume backend
struct VolumeState {
    var playbackVolume: Double = 0.0      // dB
    var playbackMuted: Bool = false
    var input1Volume: Double = 0.0
    var input1Muted: Bool = false
    var input2Volume: Double = 0.0
    var input2Muted: Bool = false
    var directMonitorEnabled: Bool = false
    var isConnected: Bool = false
    var statusMessage: String = "Not connected"
}

/// Protocol for volume control backends
protocol VolumeBackend: AnyObject {
    /// Publisher for state changes
    var statePublisher: AnyPublisher<VolumeState, Never> { get }

    /// Current state
    var state: VolumeState { get }

    /// Initialize and connect to FC2
    func connect() async -> VolumeResult

    /// Disconnect from FC2
    func disconnect()

    /// Refresh state from FC2
    func refresh() async -> VolumeResult

    // MARK: - Playback Volume

    func getPlaybackVolume() async -> Result<Double, Error>
    func setPlaybackVolume(_ db: Double) async -> VolumeResult
    func setPlaybackMuted(_ muted: Bool) async -> VolumeResult

    // MARK: - Input 1

    func getInput1Volume() async -> Result<Double, Error>
    func setInput1Volume(_ db: Double) async -> VolumeResult
    func setInput1Muted(_ muted: Bool) async -> VolumeResult

    // MARK: - Input 2

    func getInput2Volume() async -> Result<Double, Error>
    func setInput2Volume(_ db: Double) async -> VolumeResult
    func setInput2Muted(_ muted: Bool) async -> VolumeResult

    // MARK: - Direct Monitor

    func setDirectMonitorEnabled(_ enabled: Bool) async -> VolumeResult

    // MARK: - FC2 Window Control

    /// Minimize FC2 window if not already minimized (never unminimizes)
    func minimizeFC2IfNeeded() async
}

/// Errors that can occur during volume operations
enum VolumeBackendError: Error, LocalizedError {
    case fc2NotRunning
    case fc2WindowNotFound
    case sliderNotFound(String)
    case appleScriptError(String)
    case timeout
    case notConnected

    var errorDescription: String? {
        switch self {
        case .fc2NotRunning:
            return "Focusrite Control 2 is not running"
        case .fc2WindowNotFound:
            return "Could not find Focusrite Control 2 window"
        case .sliderNotFound(let name):
            return "Could not find slider: \(name)"
        case .appleScriptError(let msg):
            return "AppleScript error: \(msg)"
        case .timeout:
            return "Operation timed out"
        case .notConnected:
            return "Not connected to Focusrite Control 2"
        }
    }
}
