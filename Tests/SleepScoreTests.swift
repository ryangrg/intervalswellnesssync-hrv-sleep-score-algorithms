import XCTest
@testable import HRVSleepAlgorithms

final class SleepScoreTests: XCTestCase {

    let calculator = SleepScoreCalculator()

    // MARK: - Helpers

    /// Creates a date offset by the given number of hours from a base date.
    private func date(hoursFromBase hours: Double, base: Date = Date(timeIntervalSince1970: 0)) -> Date {
        base.addingTimeInterval(hours * 3600)
    }

    /// Creates a simple sleep period from hour offsets.
    private func period(
        from startHour: Double,
        to endHour: Double,
        stage: SleepPeriod.SleepStage,
        base: Date = Date(timeIntervalSince1970: 0)
    ) -> SleepPeriod {
        SleepPeriod(
            startDate: date(hoursFromBase: startHour, base: base),
            endDate: date(hoursFromBase: endHour, base: base),
            stage: stage
        )
    }

    // MARK: - Component 1: Duration Scoring

    func testDurationScore5Hours() {
        let score = calculator.durationScore(totalSeconds: 5 * 3600)
        XCTAssertEqual(score, 30, accuracy: 0.1, "5 hours should score ~30")
    }

    func testDurationScore6Hours() {
        let score = calculator.durationScore(totalSeconds: 6 * 3600)
        XCTAssertEqual(score, 60, accuracy: 0.1, "6 hours should score ~60")
    }

    func testDurationScore7Hours() {
        let score = calculator.durationScore(totalSeconds: 7 * 3600)
        XCTAssertEqual(score, 100, accuracy: 0.1, "7 hours should score 100")
    }

    func testDurationScore8Hours() {
        let score = calculator.durationScore(totalSeconds: 8 * 3600)
        XCTAssertEqual(score, 100, accuracy: 0.1, "8 hours should score 100")
    }

    func testDurationScore9Hours() {
        let score = calculator.durationScore(totalSeconds: 9 * 3600)
        XCTAssertEqual(score, 100, accuracy: 0.1, "9 hours should score 100")
    }

    func testDurationScore10Hours() {
        let score = calculator.durationScore(totalSeconds: 10 * 3600)
        XCTAssertEqual(score, 80, accuracy: 0.1, "10 hours should score ~80")
    }

    func testDurationScore4Hours() {
        let score = calculator.durationScore(totalSeconds: 4 * 3600)
        XCTAssertEqual(score, 15, accuracy: 0.1, "4 hours should score ~15")
    }

    // MARK: - Component 2: Stage Scoring

    func testStageScoreFallbackWhenNoStageData() {
        let periods = [
            period(from: 0, to: 8, stage: .asleepUnspecified)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 8 * 3600,
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.stageScore, 70, accuracy: 0.1, "No stage data should fall back to 70")
        XCTAssertFalse(result!.hasStageData)
    }

    func testStageScoreOptimalDeepAndREM() {
        // 18% deep, 22% REM, 60% core = ideal
        let totalSecs = 8 * 3600
        let deepSecs = Double(totalSecs) * 0.18
        let remSecs = Double(totalSecs) * 0.22
        let coreSecs = Double(totalSecs) * 0.60

        let periods = [
            period(from: 0, to: coreSecs / 3600, stage: .asleepCore),
            period(from: coreSecs / 3600, to: (coreSecs + deepSecs) / 3600, stage: .asleepDeep),
            period(from: (coreSecs + deepSecs) / 3600, to: 8, stage: .asleepREM),
        ]

        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: totalSecs,
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.stageScore, 95, "Optimal deep/REM should score near 100")
        XCTAssertTrue(result!.hasStageData)
    }

    // MARK: - Component 3: Continuity Scoring

    func testContinuityScoreNoWakeUps() {
        let periods = [
            period(from: 0, to: 8, stage: .asleepCore)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 8 * 3600,
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.continuityScore, 100, accuracy: 0.1, "No wake-ups should score 100")
        XCTAssertEqual(result!.wakeUpCount, 0)
    }

    func testContinuityScoreOneWakeUp() {
        // One 10-minute gap
        let periods = [
            period(from: 0, to: 4, stage: .asleepCore),
            period(from: 4.167, to: 8, stage: .asleepCore), // ~10 min gap
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: Int(7.833 * 3600),
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wakeUpCount, 1)
        XCTAssertLessThan(result!.continuityScore, 100, "One wake-up should reduce score")
    }

    func testContinuityScoreThreeWakeUps() {
        // Three 10-minute gaps
        let periods = [
            period(from: 0, to: 2, stage: .asleepCore),
            period(from: 2.167, to: 4, stage: .asleepCore),
            period(from: 4.333, to: 6, stage: .asleepCore),
            period(from: 6.5, to: 8, stage: .asleepCore),
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: Int(7.0 * 3600),
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wakeUpCount, 3)
        XCTAssertLessThan(result!.continuityScore, 60, "Three wake-ups should significantly reduce score")
    }

    // MARK: - Component 4: Efficiency Scoring

    func testEfficiencyScore95Percent() {
        // 7.6h sleep in 8h window = 95%
        let periods = [
            period(from: 0, to: 8, stage: .asleepCore)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: Int(7.6 * 3600),
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.efficiencyScore, 100, accuracy: 0.1, "95% efficiency should score 100")
    }

    func testEfficiencyScore85Percent() {
        let periods = [
            period(from: 0, to: 8, stage: .asleepCore)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: Int(6.8 * 3600), // 6.8/8 = 85%
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.efficiencyScore, 80, accuracy: 1, "85% efficiency should score ~80")
    }

    func testEfficiencyScore75Percent() {
        let periods = [
            period(from: 0, to: 8, stage: .asleepCore)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: Int(6.0 * 3600), // 6/8 = 75%
            avgSleepingHR: 55
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.efficiencyScore, 50, accuracy: 1, "75% efficiency should score ~50")
    }

    // MARK: - Component 5: Heart Rate Scoring

    func testHeartRateScore50bpm() {
        let score = calculator.heartRateScore(avgHR: 50)
        XCTAssertEqual(score, 100, "50 bpm should score 100")
    }

    func testHeartRateScore55bpm() {
        let score = calculator.heartRateScore(avgHR: 55)
        XCTAssertEqual(score, 95, "55 bpm should score 95")
    }

    func testHeartRateScore60bpm() {
        let score = calculator.heartRateScore(avgHR: 60)
        XCTAssertEqual(score, 85, "60 bpm should score 85")
    }

    func testHeartRateScore65bpm() {
        let score = calculator.heartRateScore(avgHR: 65)
        XCTAssertEqual(score, 70, "65 bpm should score 70")
    }

    func testHeartRateScore70bpm() {
        let score = calculator.heartRateScore(avgHR: 70)
        XCTAssertEqual(score, 55, "70 bpm should score 55")
    }

    func testHeartRateScore75bpm() {
        let score = calculator.heartRateScore(avgHR: 75)
        XCTAssertEqual(score, 40, "75 bpm should score 40")
    }

    func testHeartRateScore80bpm() {
        let score = calculator.heartRateScore(avgHR: 80)
        XCTAssertEqual(score, 30, "80 bpm should score 30")
    }

    func testHeartRateScoreNil() {
        let score = calculator.heartRateScore(avgHR: nil)
        XCTAssertNil(score, "nil HR should return nil")
    }

    // MARK: - Weight Redistribution When HR Is Nil

    func testWeightRedistributionWithoutHR() {
        let periods = [
            period(from: 0, to: 8, stage: .asleepUnspecified)
        ]
        let withHR = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 8 * 3600,
            avgSleepingHR: 55
        )
        let withoutHR = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 8 * 3600,
            avgSleepingHR: nil
        )
        XCTAssertNotNil(withHR)
        XCTAssertNotNil(withoutHR)
        XCTAssertNil(withoutHR!.heartRateScore, "HR score should be nil when no HR data")
        XCTAssertNotNil(withHR!.heartRateScore, "HR score should be present when HR data available")
        // Both should still produce a reasonable composite score
        XCTAssertGreaterThan(withoutHR!.score, 70)
        XCTAssertGreaterThan(withHR!.score, 70)
    }

    // MARK: - Full Composite Score End-to-End

    func testFullCompositeScoreGoodSleep() {
        // 8 hours sleep, optimal stages, no wake-ups, 95% efficiency, 52 bpm
        let totalSecs = 8 * 3600
        let deepSecs = Double(totalSecs) * 0.18
        let remSecs = Double(totalSecs) * 0.22
        let coreSecs = Double(totalSecs) * 0.60

        let periods = [
            period(from: 0, to: coreSecs / 3600, stage: .asleepCore),
            period(from: coreSecs / 3600, to: (coreSecs + deepSecs) / 3600, stage: .asleepDeep),
            period(from: (coreSecs + deepSecs) / 3600, to: 8, stage: .asleepREM),
        ]

        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: totalSecs,
            avgSleepingHR: 52
        )

        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.score, 90, "Good sleep across all metrics should score >90")
    }

    func testFullCompositeScorePoorSleep() {
        // 4 hours sleep, no stages, many wake-ups, poor efficiency, high HR
        let periods = [
            period(from: 0, to: 1.5, stage: .asleepUnspecified),
            period(from: 2.0, to: 3.5, stage: .asleepUnspecified), // 30 min gap
            period(from: 4.0, to: 5.0, stage: .asleepUnspecified), // 30 min gap
        ]

        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 4 * 3600,
            avgSleepingHR: 78
        )

        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.score, 50, "Poor sleep should score <50")
    }

    // MARK: - Edge Cases

    func testReturnsNilForEmptyPeriods() {
        let result = calculator.calculateScore(
            sleepPeriods: [],
            totalSleepSeconds: 3600,
            avgSleepingHR: 55
        )
        XCTAssertNil(result)
    }

    func testReturnsNilForZeroSleepSeconds() {
        let periods = [
            period(from: 0, to: 8, stage: .asleepCore)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 0,
            avgSleepingHR: 55
        )
        XCTAssertNil(result)
    }

    func testScoreIsClamped0To100() {
        // Even extreme inputs should produce a score in 0-100
        let periods = [
            period(from: 0, to: 1, stage: .asleepUnspecified)
        ]
        let result = calculator.calculateScore(
            sleepPeriods: periods,
            totalSleepSeconds: 3600,
            avgSleepingHR: 90
        )
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.score, 0)
        XCTAssertLessThanOrEqual(result!.score, 100)
    }
}
