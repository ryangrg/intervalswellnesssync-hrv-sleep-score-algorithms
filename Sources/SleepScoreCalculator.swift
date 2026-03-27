//
//  SleepScoreCalculator.swift
//  HRVSleepAlgorithms
//
//  Calculates a composite sleep score (0–100) from sleep period data.
//  Uses 5 weighted components: duration, sleep stages, continuity,
//  efficiency, and heart rate.
//
//  No HealthKit dependency — accepts plain SleepPeriod structs.
//

import Foundation

/// Calculates a composite sleep quality score (0–100) from five weighted components.
///
/// | Component   | Weight | Weight (no HR) |
/// |-------------|--------|----------------|
/// | Duration    | 30%    | 34%            |
/// | Stages      | 25%    | 28%            |
/// | Continuity  | 20%    | 22%            |
/// | Efficiency  | 15%    | 16%            |
/// | Heart Rate  | 10%    | —              |
public class SleepScoreCalculator {

    public init() {}

    // MARK: - Public API

    /// Calculates a composite sleep score from sleep period data.
    ///
    /// - Parameters:
    ///   - sleepPeriods: Array of `SleepPeriod` values representing contiguous sleep blocks.
    ///   - totalSleepSeconds: Total actual sleep time in seconds (excluding wake periods).
    ///   - avgSleepingHR: Average heart rate during sleep in bpm, or nil if unavailable.
    /// - Returns: A `SleepScoreResult`, or nil if input is empty or sleep time is zero.
    public func calculateScore(
        sleepPeriods: [SleepPeriod],
        totalSleepSeconds: Int,
        avgSleepingHR: Double?
    ) -> SleepScoreResult? {
        guard !sleepPeriods.isEmpty, totalSleepSeconds > 0 else { return nil }

        let sorted = sleepPeriods.sorted { $0.startDate < $1.startDate }

        let durScore = durationScore(totalSeconds: totalSleepSeconds)
        let stageResult = stageCompositionScore(periods: sorted, totalSeconds: totalSleepSeconds)
        let contResult = continuityScore(periods: sorted)
        let effResult = efficiencyScore(periods: sorted, totalSeconds: totalSleepSeconds)
        let hrScore = heartRateScore(avgHR: avgSleepingHR)

        let composite: Double
        if let hr = hrScore {
            composite = durScore * 0.30
                + stageResult.score * 0.25
                + contResult.score * 0.20
                + effResult.score * 0.15
                + hr * 0.10
        } else {
            // Redistribute HR weight across other components
            composite = durScore * 0.34
                + stageResult.score * 0.28
                + contResult.score * 0.22
                + effResult.score * 0.16
        }

        let finalScore = min(100, max(0, (composite * 10).rounded() / 10))

        return SleepScoreResult(
            score: finalScore,
            durationScore: durScore,
            stageScore: stageResult.score,
            continuityScore: contResult.score,
            efficiencyScore: effResult.score,
            heartRateScore: hrScore,
            deepSleepPercent: stageResult.deep,
            remSleepPercent: stageResult.rem,
            coreSleepPercent: stageResult.core,
            wakeUpCount: contResult.wakeCount,
            sleepEfficiency: effResult.efficiency,
            hasStageData: stageResult.hasStages
        )
    }

    // MARK: - Component 1: Duration (30%)

    /// Scores total sleep time. 7–9 hours is optimal (score = 100).
    func durationScore(totalSeconds: Int) -> Double {
        let hours = Double(totalSeconds) / 3600.0

        if hours >= 7.0 && hours <= 9.0 {
            return 100
        } else if hours > 9.0 && hours <= 10.0 {
            return 100 - (hours - 9.0) * 20  // 80–100
        } else if hours > 10.0 {
            return max(50, 80 - (hours - 10.0) * 15)  // 50–80
        } else if hours >= 6.0 {
            return 100 - (7.0 - hours) * 40  // 60–100
        } else if hours >= 5.0 {
            return 60 - (6.0 - hours) * 30   // 30–60
        } else {
            return max(0, 30 - (5.0 - hours) * 15)  // 0–30
        }
    }

    // MARK: - Component 2: Sleep Stages (25%)

    private struct StageResult {
        let score: Double
        let deep: Double?
        let rem: Double?
        let core: Double?
        let hasStages: Bool
    }

    /// Scores deep and REM sleep adequacy. Falls back to 70 if no stage data.
    private func stageCompositionScore(
        periods: [SleepPeriod],
        totalSeconds: Int
    ) -> StageResult {
        var deepSecs = 0.0
        var remSecs = 0.0
        var coreSecs = 0.0
        var unspecifiedSecs = 0.0

        for period in periods {
            let duration = period.endDate.timeIntervalSince(period.startDate)
            switch period.stage {
            case .asleepDeep:
                deepSecs += duration
            case .asleepREM:
                remSecs += duration
            case .asleepCore:
                coreSecs += duration
            case .asleepUnspecified:
                unspecifiedSecs += duration
            case .awake:
                break
            }
        }

        let totalSleep = Double(totalSeconds)

        // No stage breakdown available (older devices)
        if deepSecs == 0 && remSecs == 0 && coreSecs == 0 {
            return StageResult(score: 70, deep: nil, rem: nil, core: nil, hasStages: false)
        }

        let deepPct = (deepSecs / totalSleep) * 100
        let remPct = (remSecs / totalSleep) * 100
        let corePct = (coreSecs / totalSleep) * 100

        // Deep sleep sub-score (target 13–23%)
        let deepScore: Double
        if deepPct >= 13 && deepPct <= 23 {
            deepScore = 100
        } else if deepPct >= 10 {
            deepScore = 70 + (deepPct - 10) * 10
        } else if deepPct < 10 {
            deepScore = max(0, deepPct * 7)
        } else if deepPct <= 30 {
            deepScore = 100 - (deepPct - 23) * 5
        } else {
            deepScore = 50
        }

        // REM sleep sub-score (target 20–25%)
        let remScore: Double
        if remPct >= 20 && remPct <= 25 {
            remScore = 100
        } else if remPct >= 15 {
            remScore = 60 + (remPct - 15) * 8
        } else if remPct < 15 {
            remScore = max(0, remPct * 4)
        } else if remPct <= 35 {
            remScore = 100 - (remPct - 25) * 3
        } else {
            remScore = 50
        }

        let score = (deepScore + remScore) / 2.0
        return StageResult(
            score: min(100, max(0, score)),
            deep: deepPct,
            rem: remPct,
            core: corePct,
            hasStages: true
        )
    }

    // MARK: - Component 3: Continuity (20%)

    private struct ContinuityResult {
        let score: Double
        let wakeCount: Int
    }

    /// Scores sleep continuity by analyzing gaps between sleep periods.
    /// Gaps longer than 5 minutes count as wake-ups.
    private func continuityScore(periods: [SleepPeriod]) -> ContinuityResult {
        guard periods.count > 1 else {
            return ContinuityResult(score: 100, wakeCount: 0)
        }

        var wakeCount = 0
        var totalWakeMinutes = 0.0

        for i in 1..<periods.count {
            let gap = periods[i].startDate.timeIntervalSince(periods[i - 1].endDate)
            let gapMinutes = gap / 60.0

            if gapMinutes > 5.0 {
                wakeCount += 1
                totalWakeMinutes += gapMinutes
            }
        }

        let score = max(0, 100 - Double(wakeCount) * 20 - totalWakeMinutes * 0.5)
        return ContinuityResult(score: min(100, score), wakeCount: wakeCount)
    }

    // MARK: - Component 4: Efficiency (15%)

    private struct EfficiencyResult {
        let score: Double
        let efficiency: Double
    }

    /// Scores sleep efficiency: actual sleep time divided by time-in-bed window.
    /// 90%+ is optimal (score = 100).
    private func efficiencyScore(
        periods: [SleepPeriod],
        totalSeconds: Int
    ) -> EfficiencyResult {
        guard let first = periods.first, let last = periods.last else {
            return EfficiencyResult(score: 50, efficiency: 50)
        }

        let timeInBed = last.endDate.timeIntervalSince(first.startDate)
        guard timeInBed > 0 else {
            return EfficiencyResult(score: 50, efficiency: 50)
        }

        let efficiency = (Double(totalSeconds) / timeInBed) * 100

        let score: Double
        if efficiency >= 90 {
            score = 100
        } else if efficiency >= 85 {
            score = 80 + (efficiency - 85) * 4
        } else if efficiency >= 75 {
            score = 50 + (efficiency - 75) * 3
        } else {
            score = max(0, efficiency * 0.67)
        }

        return EfficiencyResult(score: min(100, score), efficiency: min(100, efficiency))
    }

    // MARK: - Component 5: Heart Rate (10%)

    /// Scores average sleeping heart rate. Lower is better. Returns nil if no data.
    ///
    /// | HR (bpm) | Score |
    /// |----------|-------|
    /// | ≤50      | 100   |
    /// | ≤55      | 95    |
    /// | ≤60      | 85    |
    /// | ≤65      | 70    |
    /// | ≤70      | 55    |
    /// | ≤75      | 40    |
    /// | >75      | 40 − 2×(HR−75), min 10 |
    func heartRateScore(avgHR: Double?) -> Double? {
        guard let hr = avgHR, hr > 0 else { return nil }

        if hr <= 50 { return 100 }
        if hr <= 55 { return 95 }
        if hr <= 60 { return 85 }
        if hr <= 65 { return 70 }
        if hr <= 70 { return 55 }
        if hr <= 75 { return 40 }
        return max(10, 40 - (hr - 75) * 2)
    }
}
