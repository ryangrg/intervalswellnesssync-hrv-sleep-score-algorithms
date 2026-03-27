import XCTest
@testable import HRVSleepAlgorithms

final class HRVProcessorTests: XCTestCase {

    let processor = HRVProcessor()

    // MARK: - Stage 1: Range Filter

    func testRangeFilterRemovesIntervalsBelow300ms() {
        let epoch = processor.processEpoch(
            rrIntervals: [250, 800, 810, 150, 820, 830, 200, 840, 850, 860],
            startTime: Date(),
            endTime: Date()
        )
        // 3 intervals below 300ms removed by range filter; total removal >= 3
        XCTAssertGreaterThanOrEqual(epoch.beatsRemoved, 3, "Should remove at least 3 sub-300ms intervals")
        // 30% removal (3/10) puts this in acceptable range (10-36%)
        XCTAssertEqual(epoch.quality, .acceptable, "30% removal should produce acceptable quality")
    }

    func testRangeFilterRemovesIntervalsAbove2000ms() {
        let epoch = processor.processEpoch(
            rrIntervals: [800, 810, 2500, 820, 830, 3000, 840, 850, 860, 870],
            startTime: Date(),
            endTime: Date()
        )
        // 2 intervals above 2000ms should be removed (2500, 3000)
        XCTAssertGreaterThanOrEqual(epoch.beatsRemoved, 2, "Should remove at least 2 supra-2000ms intervals")
    }

    // MARK: - Stage 2: Successive Difference Filter

    func testSuccessiveDifferenceFilterRemovesArtifacts() {
        // [800, 810, 1500, 820, 830]
        // i=1: |810-800|=10 <= 800*0.75=600 → keep
        // i=2: |1500-810|=690 > 810*0.75=607.5 → remove
        // i=3: |820-1500|=680 <= 1500*0.75=1125 → keep
        // i=4: |830-820|=10 <= 820*0.75=615 → keep
        // Result: [800, 810, 820, 830] — only 1500 removed
        let result = processor.successiveDifferenceFilter([800, 810, 1500, 820, 830])
        XCTAssertEqual(result.count, 4, "Should remove only the artifact (1500)")
        XCTAssertFalse(result.contains(1500), "1500ms artifact should be removed")
    }

    func testSuccessiveDifferenceFilterPreservesCleanData() {
        let clean = [800.0, 810.0, 795.0, 820.0, 805.0]
        let result = processor.successiveDifferenceFilter(clean)
        XCTAssertEqual(result.count, clean.count, "Clean data should pass through unchanged")
    }

    func testSuccessiveDifferenceFilterHandlesSingleInterval() {
        let result = processor.successiveDifferenceFilter([800])
        XCTAssertEqual(result, [800], "Single interval should pass through")
    }

    func testSuccessiveDifferenceFilterHandlesEmptyArray() {
        let result = processor.successiveDifferenceFilter([])
        XCTAssertTrue(result.isEmpty, "Empty array should return empty")
    }

    // MARK: - Stage 3: IQR Filter

    func testIQRFilterRemovesOutliers() {
        // Tight cluster with outliers
        var data = Array(repeating: 800.0, count: 20)
        data.append(500) // outlier low
        data.append(1200) // outlier high
        let result = processor.iqrFilter(data)
        XCTAssertFalse(result.contains(500), "Low outlier should be removed")
        XCTAssertFalse(result.contains(1200), "High outlier should be removed")
    }

    func testIQRFilterPreservesNormalDistribution() {
        // Two-value cluster: Q1=800, Q3=805, IQR=5, bounds=[798.75, 806.25]
        let normal = [800.0, 800.0, 800.0, 800.0, 805.0, 805.0, 805.0, 805.0]
        let result = processor.iqrFilter(normal)
        XCTAssertEqual(result.count, normal.count, "Values within IQR bounds should pass through")
    }

    func testIQRFilterHandlesFewerThan4Intervals() {
        let short = [800.0, 810.0, 820.0]
        let result = processor.iqrFilter(short)
        XCTAssertEqual(result, short, "Fewer than 4 intervals should pass through unchanged")
    }

    // MARK: - rMSSD Computation

    func testComputeRMSSDKnownValue() {
        // Intervals: [800, 810, 795, 820]
        // Successive diffs: 10, -15, 25
        // Squared diffs: 100, 225, 625
        // Mean: 950/3 = 316.667
        // rMSSD = sqrt(316.667) ≈ 17.795
        let rmssd = processor.computeRMSSD([800, 810, 795, 820])
        XCTAssertEqual(rmssd, sqrt(950.0 / 3.0), accuracy: 0.001, "rMSSD should match hand calculation")
    }

    func testComputeRMSSDIdenticalIntervals() {
        // All identical → all diffs are 0 → rMSSD = 0
        let rmssd = processor.computeRMSSD([800, 800, 800, 800])
        XCTAssertEqual(rmssd, 0, accuracy: 0.001, "Identical intervals should produce rMSSD of 0")
    }

    func testComputeRMSSDSingleInterval() {
        let rmssd = processor.computeRMSSD([800])
        XCTAssertEqual(rmssd, 0, "Single interval should return 0")
    }

    func testComputeRMSSDEmptyArray() {
        let rmssd = processor.computeRMSSD([])
        XCTAssertEqual(rmssd, 0, "Empty array should return 0")
    }

    func testComputeRMSSDTwoIntervals() {
        // [800, 820] → diff = 20, squared = 400, mean = 400, sqrt = 20
        let rmssd = processor.computeRMSSD([800, 820])
        XCTAssertEqual(rmssd, 20, accuracy: 0.001)
    }

    // MARK: - Quality Gate

    func testQualityHighWhenFewBeatsRemoved() {
        // All identical values: no successive diffs to trigger, IQR=0 so all pass
        let clean = Array(repeating: 800.0, count: 20)
        let epoch = processor.processEpoch(
            rrIntervals: clean,
            startTime: Date(),
            endTime: Date()
        )
        XCTAssertEqual(epoch.quality, .high, "Identical clean data should produce high quality epoch")
        XCTAssertEqual(epoch.beatsRemoved, 0, "No beats should be removed from identical data")
    }

    func testQualityRejectedWhenTooManyBeatsRemoved() {
        // Mostly artifact data
        let noisy = [800.0, 200.0, 2500.0, 100.0, 3000.0, 150.0, 50.0, 2800.0, 810.0, 820.0]
        let epoch = processor.processEpoch(
            rrIntervals: noisy,
            startTime: Date(),
            endTime: Date()
        )
        XCTAssertEqual(epoch.quality, .rejected, "Mostly artifact data should be rejected")
    }

    func testQualityAcceptableForModerateArtifact() {
        // 30 intervals: 24 identical clean + 6 out-of-range = 20% removal
        // Identical values ensure IQR filter removes nothing extra
        var data: [Double] = Array(repeating: 800.0, count: 24)
        data.insert(contentsOf: [200.0, 2500.0, 100.0, 3000.0, 150.0, 2800.0], at: 0)
        let epoch = processor.processEpoch(
            rrIntervals: data,
            startTime: Date(),
            endTime: Date()
        )
        XCTAssertEqual(epoch.quality, .acceptable, "20% removal should produce acceptable quality")
    }

    // MARK: - Median

    func testMedianOddCount() {
        let result = processor.median([3, 1, 2])
        XCTAssertEqual(result, 2, accuracy: 0.001)
    }

    func testMedianEvenCount() {
        let result = processor.median([4, 1, 3, 2])
        XCTAssertEqual(result, 2.5, accuracy: 0.001)
    }

    func testMedianSingleValue() {
        let result = processor.median([42])
        XCTAssertEqual(result, 42, accuracy: 0.001)
    }

    func testMedianEmpty() {
        let result = processor.median([])
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    // MARK: - Full Pipeline End-to-End

    func testFullPipelineRealisticData() {
        // Simulate a realistic 5-minute epoch (~350 beats at ~70 bpm)
        // Use tight variation (±10ms) to stay within IQR bounds
        var rrIntervals: [Double] = []
        for _ in 0..<350 {
            let base = 850.0 + Double.random(in: -10...10)
            rrIntervals.append(base)
        }
        // Inject a few obvious artifacts
        rrIntervals[50] = 250   // too short — removed by range filter
        rrIntervals[100] = 2500 // too long — removed by range filter
        rrIntervals[200] = 450  // will trigger successive diff filter

        let epoch = processor.processEpoch(
            rrIntervals: rrIntervals,
            startTime: Date(),
            endTime: Date()
        )

        XCTAssertGreaterThan(epoch.rmssd, 0, "rMSSD should be positive")
        XCTAssertGreaterThan(epoch.lnRmssd, 0, "Ln(rMSSD) should be positive")
        XCTAssertNotEqual(epoch.quality, .rejected, "Realistic data with few artifacts should not be rejected")
        XCTAssertGreaterThan(epoch.beatsRemoved, 0, "Should have removed some artifacts")
        // With tight ±10ms variation, the IQR filter won't over-remove.
        // 3 injected artifacts out of 350 = ~1%, well under the 36% rejection threshold.
        XCTAssertLessThan(Double(epoch.beatsRemoved) / Double(epoch.beatsTotal),
                          AlgorithmConstants.maxBeatRemovalRatio,
                          "Artifact removal should stay under rejection threshold")
    }

    // MARK: - Nightly Aggregation

    func testProcessNightReturnsNilForEmptyInput() {
        let result = processor.processNight(epochs: [])
        XCTAssertNil(result, "Empty epochs should return nil")
    }

    func testProcessNightReturnsNilForTooFewBeats() {
        let result = processor.processNight(epochs: [
            (rrIntervals: [800, 810, 820], start: Date(), end: Date()) // only 3 beats
        ])
        XCTAssertNil(result, "Epochs with fewer than 10 beats should be skipped")
    }

    func testProcessNightAggregatesMultipleEpochs() {
        let now = Date()
        let epochs: [(rrIntervals: [Double], start: Date, end: Date)] = (0..<5).map { i in
            let start = now.addingTimeInterval(Double(i) * 300)
            let end = start.addingTimeInterval(300)
            let rr = (0..<60).map { _ in 850.0 + Double.random(in: -20...20) }
            return (rrIntervals: rr, start: start, end: end)
        }

        let result = processor.processNight(epochs: epochs, date: now)
        XCTAssertNotNil(result, "Should produce a nightly result")
        XCTAssertEqual(result?.epochsTotal, 5)
        XCTAssertGreaterThan(result?.medianRmssd ?? 0, 0, "Median rMSSD should be positive")
        XCTAssertGreaterThan(result?.medianLnRmssd ?? 0, 0, "Median Ln(rMSSD) should be positive")
    }

    // MARK: - Edge Cases

    func testProcessEpochWithAllIdenticalIntervals() {
        let identical = Array(repeating: 800.0, count: 20)
        let epoch = processor.processEpoch(
            rrIntervals: identical,
            startTime: Date(),
            endTime: Date()
        )
        XCTAssertEqual(epoch.rmssd, 0, accuracy: 0.001, "Identical intervals should produce rMSSD of 0")
        XCTAssertEqual(epoch.quality, .high, "No beats should be removed")
    }
}
