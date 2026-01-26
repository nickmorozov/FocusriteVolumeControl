//
//  VolumeController.swift
//  FocusriteVolumeControl
//
//  High-level volume control logic for Focusrite devices
//

import Foundation
import Combine

/// Manages volume, mute, and direct monitor controls
class VolumeController: ObservableObject {

    // MARK: - Published State

    @Published var volume: Double = -20.0  // dB
    @Published var isMuted: Bool = false
    @Published var isDirectMonitorEnabled: Bool = false

    // MARK: - Configuration

    @Published var stepSize: Double = 3.0  // dB per step

    // MARK: - Private Properties

    private let client: FocusriteClient
    private var cancellables = Set<AnyCancellable>()

    // Discovered item IDs
    private var outputGainId: String?
    private var directMonitorGainIds: [String] = []
    private var muteId: String?

    // Mute state tracking
    private var preMuteVolume: Double = -20.0

    // Volume range
    private let minVolume: Double = -70.0
    private let maxVolume: Double = 6.0
    private let muteValue: Double = -128.0

    // MARK: - Initialization

    init(client: FocusriteClient) {
        self.client = client
        setupBindings()
    }

    private func setupBindings() {
        // When items change, discover controls
        client.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.discoverControls(items: items)
            }
            .store(in: &cancellables)

        // Track volume changes from device
        client.onVolumeChange = { [weak self] itemId, value in
            guard let self = self else { return }

            if itemId == self.outputGainId {
                DispatchQueue.main.async {
                    self.volume = value
                    self.isMuted = value <= self.minVolume
                }
            }
        }
    }

    // MARK: - Control Discovery

    private func discoverControls(items: [String: DeviceItem]) {
        outputGainId = nil
        directMonitorGainIds = []
        muteId = nil

        for (id, item) in items {
            // Look for output gain (first one found)
            // In the Focusrite protocol, output gains are often near the start
            if outputGainId == nil, let value = Double(item.value), value >= minVolume && value <= maxVolume {
                outputGainId = id
                volume = value
                isMuted = value <= minVolume
                print("Found output gain: \(id) = \(value)")
            }
        }
    }

    // MARK: - Volume Control

    func setVolume(_ newVolume: Double) {
        guard let gainId = outputGainId else {
            print("No output gain control found")
            return
        }

        let clamped = max(minVolume, min(maxVolume, newVolume))
        client.setValue(itemId: gainId, value: String(format: "%.1f", clamped))
        volume = clamped
        isMuted = false
    }

    func volumeUp() {
        if isMuted {
            unmute()
            return
        }

        let newVolume = min(maxVolume, volume + stepSize)
        setVolume(newVolume)
    }

    func volumeDown() {
        let newVolume = max(minVolume, volume - stepSize)
        setVolume(newVolume)
    }

    // MARK: - Mute Control

    func toggleMute() {
        if isMuted {
            unmute()
        } else {
            mute()
        }
    }

    func mute() {
        guard let gainId = outputGainId else { return }

        // Save current volume before muting
        if volume > minVolume {
            preMuteVolume = volume
        }

        client.setValue(itemId: gainId, value: String(format: "%.1f", muteValue))
        isMuted = true
    }

    func unmute() {
        guard let gainId = outputGainId else { return }

        let restoreVolume = preMuteVolume > minVolume ? preMuteVolume : -20.0
        client.setValue(itemId: gainId, value: String(format: "%.1f", restoreVolume))
        volume = restoreVolume
        isMuted = false
    }

    // MARK: - Direct Monitor Control

    func enableDirectMonitor() {
        for gainId in directMonitorGainIds {
            client.setValue(itemId: gainId, value: "0.0")
        }
        isDirectMonitorEnabled = true
    }

    func disableDirectMonitor() {
        for gainId in directMonitorGainIds {
            client.setValue(itemId: gainId, value: String(format: "%.1f", muteValue))
        }
        isDirectMonitorEnabled = false
    }

    func toggleDirectMonitor() {
        if isDirectMonitorEnabled {
            disableDirectMonitor()
        } else {
            enableDirectMonitor()
        }
    }
}
