//
//  Models.swift
//  HRVSleepAlgorithms
//
//  Data models and constants for HRV rMSSD processing and sleep scoring.
//

import Foundation

// MARK: - Algorithm Constants

/// Artifact correction thresholds derived from peer-reviewed research.
public enum AlgorithmConstants {

    /// Minimum physiological RR interval in milliseconds (~200 bpm).
    public static let rrIntervalMinMs: Double = 300

    /// Maximum physiological RR interval in milliseconds (~30 bpm).
    public static let rrIntervalMaxMs: Double = 2000

    /// Successive difference threshold — Plews et al. (2017) 75% first-pass filter.
    public static let successiveDiffThreshold: Double = 0.75

    /// IQR multiplier for outlier bounds — Plews et al. (2017).
    public static let iqrMultiplier: Double = 0.25

    /// Maximum proportion of beats that can be removed before rejecting an epoch —
    /// Sheridan et al. (2020) showed rMSSD tolerates up to 36% removal.
    public static let maxBeatRemovalRatio: Double = 0.36

    /// Threshold for classifying an epoch as high quality (<10% beats removed).
    public static let highQualityThreshold: Double = 0.10
}

// MARK: - Epoch Quality

/// Quality classification for a single HRV capture epoch based on artifact removal ratio.
public enum EpochQuality: String, Codable {
    /// Less than 10% of beats removed — high confidence in rMSSD value.
    case high
    /// 10–36% of beats removed — acceptable per Sheridan (2020).
    case acceptable
    /// More than 36% of beats removed or motion detected — epoch is unreliable.
    case rejected
}

// MARK: - HRV Epoch

/// A single 5-minute HRV capture window with computed rMSSD and quality metadata.
public struct HRVEpoch: Codable, Identifiable {
    public let id: UUID
    public let startTime: Date
    public let endTime: Date
    public let sleepStage: SleepStageLabel
    public let rmssd: Double
    public let lnRmssd: Double
    public let quality: EpochQuality
    public let beatsTotal: Int
    public let beatsRemoved: Int
    public let motionDetected: Bool

    public enum SleepStageLabel: String, Codable {
        case core, deep, rem, unknown
    }

    public init(
        startTime: Date,
        endTime: Date,
        sleepStage: SleepStageLabel,
        rmssd: Double,
        lnRmssd: Double,
        quality: EpochQuality,
        beatsTotal: Int,
        beatsRemoved: Int,
        motionDetected: Bool = false
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.sleepStage = sleepStage
        self.rmssd = rmssd
        self.lnRmssd = lnRmssd
        self.quality = quality
        self.beatsTotal = beatsTotal
        self.beatsRemoved = beatsRemoved
        self.motionDetected = motionDetected
    }
}

// MARK: - HRV Night Result

/// Aggregated nightly HRV result computed from multiple valid epochs.
public struct HRVNightResult {
    /// ISO date string (yyyy-MM-dd).
    public let date: String
    /// Median of Ln(rMSSD) across valid epochs — primary metric.
    public let medianLnRmssd: Double
    /// Back-transformed median rMSSD for display (exp of medianLnRmssd).
    public let medianRmssd: Double
    /// Total number of capture windows.
    public let epochsTotal: Int
    /// Number of epochs that passed the quality gate.
    public let epochsValid: Int
    /// Number of epochs with less than 10% beat removal.
    public let epochsHighQuality: Int
    /// Full per-epoch detail.
    public let epochs: [HRVEpoch]

    public init(
        date: String,
        medianLnRmssd: Double,
        medianRmssd: Double,
        epochsTotal: Int,
        epochsValid: Int,
        epochsHighQuality: Int,
        epochs: [HRVEpoch]
    ) {
        self.date = date
        self.medianLnRmssd = medianLnRmssd
        self.medianRmssd = medianRmssd
        self.epochsTotal = epochsTotal
        self.epochsValid = epochsValid
        self.epochsHighQuality = epochsHighQuality
        self.epochs = epochs
    }

    /// Summary string for wellness comments.
    public var commentSummary: String {
        let rmssdStr = String(format: "%.1f", medianRmssd)
        return "Enhanced HRV: \(epochsValid)/\(epochsTotal) epochs valid, median rMSSD \(rmssdStr)ms"
    }
}

// MARK: - Sleep Period

/// A single sleep period replacing HealthKit's HKCategorySample.
/// Represents a contiguous block of time in one sleep stage.
public struct SleepPeriod {
    public let startDate: Date
    public let endDate: Date
    public let stage: SleepStage

    public enum SleepStage: String, Codable {
        case asleepCore
        case asleepDeep
        case asleepREM
        case asleepUnspecified
        case awake
    }

    public init(startDate: Date, endDate: Date, stage: SleepStage) {
        self.startDate = startDate
        self.endDate = endDate
        self.stage = stage
    }
}

// MARK: - Sleep Score Result

/// Composite sleep score (0–100) broken down into five weighted components.
public struct SleepScoreResult {
    /// Overall composite score (0–100).
    public let score: Double
    /// Duration component score (0–100).
    public let durationScore: Double
    /// Sleep stage composition score (0–100).
    public let stageScore: Double
    /// Continuity component score (0–100).
    public let continuityScore: Double
    /// Efficiency component score (0–100).
    public let efficiencyScore: Double
    /// Heart rate component score (0–100), nil if no HR data.
    public let heartRateScore: Double?
    /// Percentage of total sleep spent in deep sleep, nil if no stage data.
    public let deepSleepPercent: Double?
    /// Percentage of total sleep spent in REM sleep, nil if no stage data.
    public let remSleepPercent: Double?
    /// Percentage of total sleep spent in core sleep, nil if no stage data.
    public let coreSleepPercent: Double?
    /// Number of significant wake-ups (gaps > 5 minutes).
    public let wakeUpCount: Int
    /// Sleep efficiency as a percentage (0–100%).
    public let sleepEfficiency: Double
    /// Whether granular sleep stage data was available.
    public let hasStageData: Bool

    public init(
        score: Double,
        durationScore: Double,
        stageScore: Double,
        continuityScore: Double,
        efficiencyScore: Double,
        heartRateScore: Double?,
        deepSleepPercent: Double?,
        remSleepPercent: Double?,
        coreSleepPercent: Double?,
        wakeUpCount: Int,
        sleepEfficiency: Double,
        hasStageData: Bool
    ) {
        self.score = score
        self.durationScore = durationScore
        self.stageScore = stageScore
        self.continuityScore = continuityScore
        self.efficiencyScore = efficiencyScore
        self.heartRateScore = heartRateScore
        self.deepSleepPercent = deepSleepPercent
        self.remSleepPercent = remSleepPercent
        self.coreSleepPercent = coreSleepPercent
        self.wakeUpCount = wakeUpCount
        self.sleepEfficiency = sleepEfficiency
        self.hasStageData = hasStageData
    }
}
