//
//  VolumeControllerIntegrationTests.swift
//  FocusriteVolumeControlTests
//
//  Integration tests verifying full workflows and edge cases.
//  These tests simulate real user scenarios with the mock backend.
//

import XCTest
import Combine
@testable import FocusriteVolumeControl

@MainActor
final class VolumeControllerIntegrationTests: XCTestCase {

    var mockBackend: MockVolumeBackend!
    var controller: VolumeController!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockBackend = MockVolumeBackend()
        controller = VolumeController(backend: mockBackend)
        cancellables = []
        try await Task.sleep(for: .milliseconds(50))
    }

    override func tearDown() {
        cancellables = nil
        controller = nil
        mockBackend = nil
    }

    func waitForStateUpdate() async throws {
        try await Task.sleep(for: .milliseconds(20))
    }

    // MARK: - Full Mute/Unmute Cycle

    func testFullMuteUnmuteCycle() async throws {
        // Start at known volume
        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()

        XCTAssertFalse(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -30.0)

        // Mute
        controller.mute()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -127.0)

        // Unmute - should restore original volume
        controller.unmute()
        try await waitForStateUpdate()

        XCTAssertFalse(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -30.0)
    }

    func testMuteUnmuteCycle_ViaToggle() async throws {
        mockBackend.setPlaybackVolumeState(-25.0)
        try await waitForStateUpdate()

        // Toggle to mute
        controller.toggleMute()
        try await waitForStateUpdate()
        XCTAssertTrue(controller.playbackMuted)

        // Toggle to unmute
        controller.toggleMute()
        try await waitForStateUpdate()
        XCTAssertFalse(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -25.0)
    }

    func testMuteUnmuteCycle_ViaVolumeDown() async throws {
        mockBackend.setPlaybackVolumeState(-125.0)
        try await waitForStateUpdate()

        // Volume down should mute when near minimum
        controller.volumeDown()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)
    }

    func testUnmute_ViaVolumeUp() async throws {
        // Start muted
        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()
        controller.mute()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)

        // Volume up should unmute
        controller.volumeUp()
        try await waitForStateUpdate()

        XCTAssertFalse(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -30.0)
    }

    // MARK: - Volume Up/Down Sequence

    func testVolumeUpDownSequence() async throws {
        mockBackend.setPlaybackVolumeState(-50.0)
        try await waitForStateUpdate()

        let initialVolume = controller.playbackVolume

        // Go up 3 times
        for _ in 1...3 {
            controller.volumeUp()
            try await waitForStateUpdate()
        }

        let afterUpVolume = controller.playbackVolume
        XCTAssertGreaterThan(afterUpVolume, initialVolume)

        // Go down 3 times
        for _ in 1...3 {
            controller.volumeDown()
            try await waitForStateUpdate()
        }

        let afterDownVolume = controller.playbackVolume
        XCTAssertLessThan(afterDownVolume, afterUpVolume)
    }

    func testVolumeUp_ToMaximum() async throws {
        mockBackend.setPlaybackVolumeState(-5.0)
        try await waitForStateUpdate()

        // Keep going up until we hit max
        for _ in 1...20 {
            controller.volumeUp()
            try await waitForStateUpdate()
            if controller.playbackVolume >= 0.0 {
                break
            }
        }

        XCTAssertEqual(controller.playbackVolume, 0.0, accuracy: 1.0)
    }

    func testVolumeDown_ToMinimum() async throws {
        mockBackend.setPlaybackVolumeState(-120.0)
        try await waitForStateUpdate()

        // Keep going down until we hit min
        for _ in 1...20 {
            controller.volumeDown()
            try await waitForStateUpdate()
            if controller.playbackMuted {
                break
            }
        }

        XCTAssertTrue(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -127.0)
    }

    // MARK: - Speed Setting Integration

    func testSpeedChange_AffectsVolumeSteps() async throws {
        mockBackend.setPlaybackVolumeState(-60.0)
        try await waitForStateUpdate()

        // Slow speed
        controller.stepSize = 3.0
        let startVolume = controller.playbackVolume
        controller.volumeUp()
        try await waitForStateUpdate()
        let slowStepChange = controller.playbackVolume - startVolume

        // Reset
        mockBackend.setPlaybackVolumeState(-60.0)
        try await waitForStateUpdate()

        // Fast speed
        controller.stepSize = 8.0
        controller.volumeUp()
        try await waitForStateUpdate()
        let fastStepChange = controller.playbackVolume - (-60.0)

        // Fast step should be larger (or equal at boundaries)
        XCTAssertGreaterThanOrEqual(fastStepChange, slowStepChange)
    }

    // MARK: - Connection State Integration

    func testConnectionLifecycle() async throws {
        // Initially disconnected
        mockBackend.setConnectedState(false)
        try await waitForStateUpdate()
        XCTAssertFalse(controller.isConnected)

        // Connect - use longer wait since connect() is async
        controller.connect()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Connected")

        // Disconnect
        controller.disconnect()
        try await waitForStateUpdate()
        XCTAssertFalse(controller.isConnected)
    }

    func testConnectionFailure_UpdatesStatus() async throws {
        mockBackend.shouldFailConnect = true
        mockBackend.connectError = "Focusrite Control 2 is not running"

        controller.connect()
        try await waitForStateUpdate()

        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Focusrite Control 2 is not running")
    }

    // MARK: - Direct Monitor Integration

    func testDirectMonitorToggle_UpdatesState() async throws {
        mockBackend.setMockState(VolumeState(directMonitorEnabled: false, isConnected: true))
        try await waitForStateUpdate()

        XCTAssertFalse(controller.directMonitorEnabled)

        controller.toggleDirectMonitor()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.directMonitorEnabled)

        controller.toggleDirectMonitor()
        try await waitForStateUpdate()

        XCTAssertFalse(controller.directMonitorEnabled)
    }

    // MARK: - Multiple Channel Integration

    func testMultipleChannels_IndependentState() async throws {
        // Set different volumes on each channel
        controller.setPlaybackVolume(-20.0)
        controller.setInput1Volume(-30.0)
        controller.setInput2Volume(-40.0)
        try await waitForStateUpdate()

        XCTAssertEqual(controller.playbackVolume, -20.0)
        XCTAssertEqual(controller.input1Volume, -30.0)
        XCTAssertEqual(controller.input2Volume, -40.0)

        // Mute input 1
        controller.toggleInput1Mute()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.input1Muted)
        XCTAssertFalse(controller.input2Muted)
        XCTAssertFalse(controller.playbackMuted)
    }

    // MARK: - Percentage API Integration

    func testPercentageAPI_FullRange() async throws {
        // Set to 0%
        controller.setPlaybackPercent(0.0)
        try await waitForStateUpdate()
        XCTAssertEqual(controller.playbackVolume, -127.0)
        XCTAssertTrue(controller.playbackMuted)

        // Set to 50%
        controller.setPlaybackPercent(50.0)
        try await waitForStateUpdate()
        XCTAssertEqual(controller.playbackVolume, -16.0, accuracy: 2.0)
        XCTAssertFalse(controller.playbackMuted)

        // Set to 100%
        controller.setPlaybackPercent(100.0)
        try await waitForStateUpdate()
        XCTAssertEqual(controller.playbackVolume, 0.0)
    }

    // MARK: - State Observation Integration

    func testStateObservation_PublisherUpdates() async throws {
        var receivedStates: [Bool] = []

        controller.$isConnected
            .sink { receivedStates.append($0) }
            .store(in: &cancellables)

        mockBackend.setConnectedState(true)
        try await waitForStateUpdate()

        mockBackend.setConnectedState(false)
        try await waitForStateUpdate()

        mockBackend.setConnectedState(true)
        try await waitForStateUpdate()

        // Should have received state changes
        XCTAssertTrue(receivedStates.count >= 2)
    }

    func testStateObservation_VolumeChanges() async throws {
        var receivedVolumes: [Double] = []

        controller.$playbackVolume
            .sink { receivedVolumes.append($0) }
            .store(in: &cancellables)

        mockBackend.setPlaybackVolumeState(-50.0)
        try await waitForStateUpdate()

        mockBackend.setPlaybackVolumeState(-40.0)
        try await waitForStateUpdate()

        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()

        XCTAssertTrue(receivedVolumes.count >= 3)
    }

    // MARK: - Edge Cases

    func testRapidVolumeChanges() async throws {
        mockBackend.setPlaybackVolumeState(-50.0)
        try await waitForStateUpdate()

        // Rapid up/down
        for _ in 1...5 {
            controller.volumeUp()
            controller.volumeDown()
        }
        try await waitForStateUpdate()

        // Should still be functional
        XCTAssertFalse(controller.playbackMuted)
    }

    func testMuteWhileAtMinimum() async throws {
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()

        // Already at minimum, muting again should not crash
        controller.mute()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)
        XCTAssertEqual(controller.playbackVolume, -127.0)
    }

    func testUnmuteAfterMultipleMutes() async throws {
        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()

        // Mute multiple times
        controller.mute()
        try await waitForStateUpdate()
        controller.mute()
        try await waitForStateUpdate()
        controller.mute()
        try await waitForStateUpdate()

        // Single unmute should restore original volume
        controller.unmute()
        try await waitForStateUpdate()

        XCTAssertEqual(controller.playbackVolume, -30.0)
    }

    func testVolumeDownWhenMuted_DoesNothing() async throws {
        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()

        controller.mute()
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeDown()
        try await waitForStateUpdate()

        // Should not have called setPlaybackVolume
        let volumeCalls = mockBackend.calls.filter { $0.method == "setPlaybackVolume" }
        XCTAssertTrue(volumeCalls.isEmpty)
    }
}
