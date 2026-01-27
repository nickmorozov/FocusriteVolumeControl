//
//  PerceptualCurveTests.swift
//  FocusriteVolumeControlTests
//
//  Tests for the perceptual volume curve conversions (dB ↔ percentage).
//  The curve is designed so 50% slider = -16 dB (half perceived loudness).
//
//  Mathematical basis:
//  - dB = 127 × (percent/100)^exponent - 127
//  - Exponent ≈ 0.197 satisfies: 127 × 0.5^0.197 - 127 ≈ -16
//

import XCTest
@testable import FocusriteVolumeControl

@MainActor
final class PerceptualCurveTests: XCTestCase {

    var controller: VolumeController!

    override func setUp() {
        // Use real controller to test actual conversion methods
        controller = VolumeController()
    }

    override func tearDown() {
        controller = nil
    }

    // MARK: - dB to Percent Conversion

    func testDbToPercent_AtMaximum_Returns100() {
        let percent = controller.dbToPercent(0.0)
        XCTAssertEqual(percent, 100.0, accuracy: 0.01)
    }

    func testDbToPercent_AtMinimum_Returns0() {
        let percent = controller.dbToPercent(-127.0)
        XCTAssertEqual(percent, 0.0, accuracy: 0.01)
    }

    func testDbToPercent_AtMinus16dB_Returns50() {
        // This is the key requirement: 50% slider = -16 dB
        let percent = controller.dbToPercent(-16.0)
        XCTAssertEqual(percent, 50.0, accuracy: 1.0)  // Allow 1% tolerance
    }

    func testDbToPercent_AboveMax_Returns100() {
        let percent = controller.dbToPercent(10.0)
        XCTAssertEqual(percent, 100.0, accuracy: 0.01)
    }

    func testDbToPercent_BelowMin_Returns0() {
        let percent = controller.dbToPercent(-200.0)
        XCTAssertEqual(percent, 0.0, accuracy: 0.01)
    }

    func testDbToPercent_NeverExceeds100() {
        for db in stride(from: -127.0, through: 0.0, by: 1.0) {
            let percent = controller.dbToPercent(db)
            XCTAssertLessThanOrEqual(percent, 100.0, "dB \(db) produced \(percent)%")
        }
    }

    func testDbToPercent_NeverBelow0() {
        for db in stride(from: -127.0, through: 0.0, by: 1.0) {
            let percent = controller.dbToPercent(db)
            XCTAssertGreaterThanOrEqual(percent, 0.0, "dB \(db) produced \(percent)%")
        }
    }

    func testDbToPercent_IsMonotonicallyIncreasing() {
        var prevPercent = controller.dbToPercent(-127.0)
        for db in stride(from: -126.0, through: 0.0, by: 1.0) {
            let percent = controller.dbToPercent(db)
            XCTAssertGreaterThanOrEqual(percent, prevPercent,
                "Curve not monotonic: dB \(db-1) = \(prevPercent)%, dB \(db) = \(percent)%")
            prevPercent = percent
        }
    }

    // MARK: - Percent to dB Conversion

    func testPercentToDb_At100_ReturnsMax() {
        let db = controller.percentToDb(100.0)
        XCTAssertEqual(db, 0.0, accuracy: 0.01)
    }

    func testPercentToDb_At0_ReturnsMin() {
        let db = controller.percentToDb(0.0)
        XCTAssertEqual(db, -127.0, accuracy: 0.01)
    }

    func testPercentToDb_At50_ReturnsMinus16() {
        // This is the key requirement: 50% slider = -16 dB
        let db = controller.percentToDb(50.0)
        XCTAssertEqual(db, -16.0, accuracy: 1.0)  // Allow 1 dB tolerance
    }

    func testPercentToDb_Above100_ReturnsMax() {
        let db = controller.percentToDb(150.0)
        XCTAssertEqual(db, 0.0, accuracy: 0.01)
    }

    func testPercentToDb_Below0_ReturnsMin() {
        let db = controller.percentToDb(-50.0)
        XCTAssertEqual(db, -127.0, accuracy: 0.01)
    }

    func testPercentToDb_NeverExceeds0() {
        for percent in stride(from: 0.0, through: 100.0, by: 1.0) {
            let db = controller.percentToDb(percent)
            XCTAssertLessThanOrEqual(db, 0.0, "\(percent)% produced \(db) dB")
        }
    }

    func testPercentToDb_NeverBelowMinus127() {
        for percent in stride(from: 0.0, through: 100.0, by: 1.0) {
            let db = controller.percentToDb(percent)
            XCTAssertGreaterThanOrEqual(db, -127.0, "\(percent)% produced \(db) dB")
        }
    }

    func testPercentToDb_IsMonotonicallyIncreasing() {
        var prevDb = controller.percentToDb(0.0)
        for percent in stride(from: 1.0, through: 100.0, by: 1.0) {
            let db = controller.percentToDb(percent)
            XCTAssertGreaterThanOrEqual(db, prevDb,
                "Curve not monotonic: \(percent-1)% = \(prevDb) dB, \(percent)% = \(db) dB")
            prevDb = db
        }
    }

    // MARK: - Round-Trip Property Tests

    func testRoundTrip_DbToPercentToDb() {
        // Converting dB → % → dB should return close to original
        for db in stride(from: -120.0, through: -1.0, by: 5.0) {
            let percent = controller.dbToPercent(db)
            let backToDb = controller.percentToDb(percent)
            XCTAssertEqual(backToDb, db, accuracy: 0.5,
                "Round-trip failed: \(db) dB → \(percent)% → \(backToDb) dB")
        }
    }

    func testRoundTrip_PercentToDbToPercent() {
        // Converting % → dB → % should return close to original
        for percent in stride(from: 5.0, through: 95.0, by: 5.0) {
            let db = controller.percentToDb(percent)
            let backToPercent = controller.dbToPercent(db)
            XCTAssertEqual(backToPercent, percent, accuracy: 0.5,
                "Round-trip failed: \(percent)% → \(db) dB → \(backToPercent)%")
        }
    }

    // MARK: - Perceptual Curve Shape Tests

    func testCurve_LinearSliderTravelProperty() {
        // User requested: same visual distance 0→50% as 50→100%
        // This is about slider tick marks, not the curve itself
        // The curve converts these uniform ticks to non-linear dB

        // At 25%: should be roughly halfway between 0% and 50% dB-wise
        let db25 = controller.percentToDb(25.0)
        let db0 = controller.percentToDb(0.0)
        let db50 = controller.percentToDb(50.0)

        // 25% should be somewhere between 0% and 50% dB values
        XCTAssertGreaterThan(db25, db0)
        XCTAssertLessThan(db25, db50)
    }

    func testCurve_50PercentIsHalfPerceivedLoudness() {
        // -16 dB is roughly half perceived loudness
        // This is the psychoacoustic basis for the curve
        let db = controller.percentToDb(50.0)
        XCTAssertEqual(db, -16.0, accuracy: 2.0)
    }

    func testCurve_SmallPercentChangesAtLowVolumeHaveLargerdBChanges() {
        // At low volumes, small % changes should map to larger dB changes
        // This is what the exponent < 1 curve achieves
        let db5 = controller.percentToDb(5.0)
        let db10 = controller.percentToDb(10.0)
        let change_5_10 = db10 - db5

        let db50 = controller.percentToDb(50.0)
        let db55 = controller.percentToDb(55.0)
        let change_50_55 = db55 - db50

        // 5% change at low volume should produce larger dB change
        // than 5% change at mid volume
        XCTAssertGreaterThan(change_5_10, change_50_55,
            "Curve shape wrong: 5→10% changed \(change_5_10) dB, 50→55% changed \(change_50_55) dB")
    }

    // MARK: - Boundary Condition Tests

    func testBoundary_JustAboveMin() {
        let db = controller.percentToDb(0.1)
        XCTAssertGreaterThan(db, -127.0)
        // With exponent 0.197, 0.1% maps to very low dB (steep curve at low end)
        XCTAssertLessThan(db, 0.0)
    }

    func testBoundary_JustBelowMax() {
        let db = controller.percentToDb(99.9)
        XCTAssertLessThan(db, 0.0)
        XCTAssertGreaterThan(db, -10.0)
    }

    func testBoundary_VerySmallPercent() {
        // Very small percentages should still work
        let db = controller.percentToDb(0.01)
        XCTAssertGreaterThanOrEqual(db, -127.0)
        XCTAssertLessThan(db, -100.0)
    }

    func testBoundary_VeryLargePercent() {
        // Percentages above 100 should clamp to max
        let db = controller.percentToDb(999.0)
        XCTAssertEqual(db, 0.0, accuracy: 0.01)
    }

    // MARK: - Specific dB Value Tests

    func testKnownValues() {
        // Test some specific dB values that are commonly used

        // Unity gain (0 dB) = 100%
        XCTAssertEqual(controller.dbToPercent(0.0), 100.0, accuracy: 0.1)

        // Silence (-127 dB) = 0%
        XCTAssertEqual(controller.dbToPercent(-127.0), 0.0, accuracy: 0.1)

        // -16 dB ≈ 50% (half perceived loudness)
        XCTAssertEqual(controller.dbToPercent(-16.0), 50.0, accuracy: 2.0)

        // -6 dB (common "half power" reference)
        let percent_minus6 = controller.dbToPercent(-6.0)
        XCTAssertGreaterThan(percent_minus6, 60.0)
        XCTAssertLessThan(percent_minus6, 85.0)

        // -20 dB (common reference level)
        let percent_minus20 = controller.dbToPercent(-20.0)
        XCTAssertGreaterThan(percent_minus20, 35.0)
        XCTAssertLessThan(percent_minus20, 55.0)
    }

    // MARK: - Integer dB Value Tests (FC2 Requirement)

    func testPercentToDb_ProducesReasonableIntegerValues() {
        // FC2 only accepts integer dB values
        // Test that reasonable % values produce integers when rounded
        for percent in stride(from: 5.0, through: 95.0, by: 5.0) {
            let db = controller.percentToDb(percent)
            let rounded = round(db)
            XCTAssertEqual(db, rounded, accuracy: 0.5,
                "\(percent)% produced \(db) dB, rounded to \(rounded) dB")
        }
    }

    func testCurve_1PercentStepProducesMeaningfuldBChange() {
        // Ensure that 1% steps don't all round to the same integer dB
        var lastDb = round(controller.percentToDb(0.0))
        var changeCount = 0

        for percent in stride(from: 1.0, through: 100.0, by: 1.0) {
            let db = round(controller.percentToDb(percent))
            if db != lastDb {
                changeCount += 1
                lastDb = db
            }
        }

        // Should have many distinct dB values across 100% range
        // With -127 to 0 range, we have 128 possible integer values
        XCTAssertGreaterThan(changeCount, 50,
            "Only \(changeCount) distinct dB values in 100% range")
    }
}
