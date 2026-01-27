//
//  FCServerBackendTests.swift
//  FocusriteVolumeControlTests
//
//  Tests for FCServerBackend placeholder - verifies it correctly returns
//  "not implemented" errors for all operations.
//

import XCTest
import Combine
@testable import FocusriteVolumeControl

final class FCServerBackendTests: XCTestCase {

    var backend: FCServerBackend!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        backend = FCServerBackend()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        backend = nil
    }

    // MARK: - Connection Tests

    func testConnect_ReturnsError() async {
        let result = await backend.connect()

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("not yet implemented"))
        } else {
            XCTFail("Expected error result")
        }
    }

    func testConnect_SetsIsConnectedFalse() async {
        _ = await backend.connect()

        XCTAssertFalse(backend.state.isConnected)
    }

    func testConnect_SetsStatusMessage() async {
        _ = await backend.connect()

        XCTAssertTrue(backend.state.statusMessage.contains("not yet implemented"))
    }

    func testDisconnect_SetsIsConnectedFalse() {
        backend.disconnect()

        XCTAssertFalse(backend.state.isConnected)
        XCTAssertEqual(backend.state.statusMessage, "Disconnected")
    }

    func testRefresh_ReturnsError() async {
        let result = await backend.refresh()

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("not yet implemented"))
        } else {
            XCTFail("Expected error result")
        }
    }

    // MARK: - Playback Volume Tests

    func testGetPlaybackVolume_ReturnsFailure() async {
        let result = await backend.getPlaybackVolume()

        switch result {
        case .failure(let error):
            XCTAssertTrue(error is VolumeBackendError)
        case .success:
            XCTFail("Expected failure result")
        }
    }

    func testSetPlaybackVolume_ReturnsError() async {
        let result = await backend.setPlaybackVolume(-20.0)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("not yet implemented"))
        } else {
            XCTFail("Expected error result")
        }
    }

    func testSetPlaybackMuted_ReturnsError() async {
        let result = await backend.setPlaybackMuted(true)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("not yet implemented"))
        } else {
            XCTFail("Expected error result")
        }
    }

    // MARK: - Input Volume Tests

    func testSetInput1Volume_ReturnsError() async {
        let result = await backend.setInput1Volume(-20.0)

        if case .error = result {
            // Expected
        } else {
            XCTFail("Expected error result")
        }
    }

    func testSetInput2Volume_ReturnsError() async {
        let result = await backend.setInput2Volume(-20.0)

        if case .error = result {
            // Expected
        } else {
            XCTFail("Expected error result")
        }
    }

    // MARK: - Direct Monitor Tests

    func testSetDirectMonitorEnabled_ReturnsError() async {
        let result = await backend.setDirectMonitorEnabled(true)

        if case .error(let message) = result {
            XCTAssertTrue(message.contains("not yet implemented"))
        } else {
            XCTFail("Expected error result")
        }
    }

    // MARK: - State Publisher Tests

    func testStatePublisher_EmitsUpdates() async {
        let expectation = XCTestExpectation(description: "State published")

        backend.statePublisher
            .dropFirst()  // Skip initial state
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        _ = await backend.connect()

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Minimize Tests

    func testMinimizeFC2IfNeeded_DoesNothing() async {
        // Should complete without error (no-op for FC Server)
        await backend.minimizeFC2IfNeeded()
        // If we get here without crashing, the test passes
    }
}
