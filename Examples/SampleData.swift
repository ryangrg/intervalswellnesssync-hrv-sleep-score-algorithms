//
//  SampleData.swift
//  HRVSleepAlgorithms
//
//  Example inputs and outputs for both algorithms.
//  This file is not part of the library target — it serves as documentation.
//

import Foundation
import HRVSleepAlgorithms

// MARK: - HRV Processing Example

func hrvProcessingExample() {
    let processor = HRVProcessor()

    // --- Single epoch ---
    // Simulated 5-minute RR interval capture (~60 beats per minute)
    let rrIntervals: [Double] = [
        823, 831, 847, 812, 798, 835, 821, 809, 843, 826,
        818, 840, 805, 833, 811, 849, 822, 837, 801, 828,
        815, 844, 807, 836, 819, 841, 803, 830, 814, 846,
        808, 834, 820, 842, 806, 838, 817, 845, 810, 832,
        824, 839, 813, 848, 802, 829, 816, 843, 809, 835,
        825, 837, 811, 847, 804, 831, 818, 844, 807, 836,
    ]

    let epoch = processor.processEpoch(
        rrIntervals: rrIntervals,
        startTime: Date(),
        endTime: Date().addingTimeInterval(300)
    )

    print("=== Single Epoch Result ===")
    print("rMSSD: \(String(format: "%.2f", epoch.rmssd)) ms")
    print("Ln(rMSSD): \(String(format: "%.3f", epoch.lnRmssd))")
    print("Quality: \(epoch.quality.rawValue)")
    print("Beats: \(epoch.beatsTotal) total, \(epoch.beatsRemoved) removed")
    print()

    // --- Nightly aggregation ---
    // Simulate 6 epochs of overnight capture
    let now = Date()
    let nightEpochs: [(rrIntervals: [Double], start: Date, end: Date)] = (0..<6).map { i in
        let start = now.addingTimeInterval(Double(i) * 600) // every 10 min
        let end = start.addingTimeInterval(300)              // 5 min duration
        // Generate slightly varying RR intervals per epoch
        let rr = (0..<60).map { _ in 830.0 + Double.random(in: -25...25) }
        return (rrIntervals: rr, start: start, end: end)
    }

    if let nightResult = processor.processNight(epochs: nightEpochs, date: now) {
        print("=== Nightly Result ===")
        print("Date: \(nightResult.date)")
        print("Median rMSSD: \(String(format: "%.2f", nightResult.medianRmssd)) ms")
        print("Median Ln(rMSSD): \(String(format: "%.3f", nightResult.medianLnRmssd))")
        print("Epochs: \(nightResult.epochsValid)/\(nightResult.epochsTotal) valid")
        print("High quality: \(nightResult.epochsHighQuality)")
        print("Summary: \(nightResult.commentSummary)")
    }
}

// MARK: - Sleep Score Example

func sleepScoreExample() {
    let calculator = SleepScoreCalculator()

    let base = Date(timeIntervalSince1970: 0)

    // Simulate a good night of sleep: 10pm to 6am
    // Sleep architecture: Core → Deep → Core → REM → Core → Deep → REM → Core
    let sleepPeriods: [SleepPeriod] = [
        SleepPeriod(startDate: base, endDate: base.addingTimeInterval(1.5 * 3600), stage: .asleepCore),
        SleepPeriod(startDate: base.addingTimeInterval(1.5 * 3600), endDate: base.addingTimeInterval(2.5 * 3600), stage: .asleepDeep),
        SleepPeriod(startDate: base.addingTimeInterval(2.5 * 3600), endDate: base.addingTimeInterval(3.5 * 3600), stage: .asleepCore),
        SleepPeriod(startDate: base.addingTimeInterval(3.5 * 3600), endDate: base.addingTimeInterval(4.5 * 3600), stage: .asleepREM),
        SleepPeriod(startDate: base.addingTimeInterval(4.5 * 3600), endDate: base.addingTimeInterval(5.5 * 3600), stage: .asleepCore),
        SleepPeriod(startDate: base.addingTimeInterval(5.5 * 3600), endDate: base.addingTimeInterval(6.0 * 3600), stage: .asleepDeep),
        SleepPeriod(startDate: base.addingTimeInterval(6.0 * 3600), endDate: base.addingTimeInterval(7.0 * 3600), stage: .asleepREM),
        SleepPeriod(startDate: base.addingTimeInterval(7.0 * 3600), endDate: base.addingTimeInterval(8.0 * 3600), stage: .asleepCore),
    ]

    // Total sleep = 8 hours = 28800 seconds
    if let result = calculator.calculateScore(
        sleepPeriods: sleepPeriods,
        totalSleepSeconds: 28800,
        avgSleepingHR: 52.0
    ) {
        print("=== Sleep Score Result ===")
        print("Overall Score: \(String(format: "%.1f", result.score))/100")
        print()
        print("Components:")
        print("  Duration:   \(String(format: "%.1f", result.durationScore))")
        print("  Stages:     \(String(format: "%.1f", result.stageScore))")
        print("  Continuity: \(String(format: "%.1f", result.continuityScore))")
        print("  Efficiency: \(String(format: "%.1f", result.efficiencyScore))")
        if let hr = result.heartRateScore {
            print("  Heart Rate: \(String(format: "%.1f", hr))")
        }
        print()
        print("Details:")
        if let deep = result.deepSleepPercent {
            print("  Deep sleep: \(String(format: "%.1f", deep))%")
        }
        if let rem = result.remSleepPercent {
            print("  REM sleep:  \(String(format: "%.1f", rem))%")
        }
        print("  Efficiency: \(String(format: "%.1f", result.sleepEfficiency))%")
        print("  Wake-ups:   \(result.wakeUpCount)")
        print("  Has stages: \(result.hasStageData)")
    }
}
