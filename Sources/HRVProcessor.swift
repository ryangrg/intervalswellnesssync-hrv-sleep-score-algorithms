//
//  HRVProcessor.swift
//  HRVSleepAlgorithms
//
//  Multi-stage artifact correction and rMSSD computation for beat-to-beat
//  RR interval data. Accepts raw RR intervals from any source (Apple Watch,
//  Polar, Garmin, etc.) — no HealthKit dependency.
//
//  Pipeline:
//    Stage 1 — Range filter (300–2000ms)
//    Stage 2 — Successive difference filter (Plews 75% threshold)
//    Stage 3 — IQR outlier removal (Q1/Q3 ± 0.25×IQR)
//    Stage 4 — Quality gate (classify epoch by % beats removed)
//    Stage 5 — rMSSD computation
//
//  References:
//    - Plews et al. (2017) — successive difference + IQR thresholds
//    - Sheridan et al. (2020) — 36% max beat removal tolerance
//    - Saboul et al. (2022) — rMSSD artifact sensitivity
//

import Foundation

/// Processes raw RR intervals through a multi-stage artifact correction pipeline
/// and computes rMSSD (root mean square of successive differences).
public struct HRVProcessor {

    public init() {}

    // MARK: - Epoch Processing

    /// Processes a single epoch's RR intervals through the full artifact correction pipeline.
    ///
    /// - Parameters:
    ///   - rrIntervals: Raw RR intervals in milliseconds.
    ///   - startTime: Start time of the capture window.
    ///   - endTime: End time of the capture window.
    /// - Returns: An `HRVEpoch` with computed rMSSD and quality classification.
    public func processEpoch(
        rrIntervals: [Double],
        startTime: Date,
        endTime: Date
    ) -> HRVEpoch {
        let originalCount = rrIntervals.count
        var filtered = rrIntervals

        // Stage 1: Range filter — remove intervals outside physiological bounds (300–2000ms)
        filtered = filtered.filter { rr in
            rr >= AlgorithmConstants.rrIntervalMinMs && rr <= AlgorithmConstants.rrIntervalMaxMs
        }

        // Stage 2: Successive difference filter — Plews 75% threshold
        filtered = successiveDifferenceFilter(filtered)

        // Stage 3: IQR outlier removal
        filtered = iqrFilter(filtered)

        let beatsRemoved = originalCount - filtered.count
        let removalRatio = originalCount > 0
            ? Double(beatsRemoved) / Double(originalCount)
            : 1.0

        // Stage 4: Quality gate
        let quality: EpochQuality
        if removalRatio > AlgorithmConstants.maxBeatRemovalRatio {
            quality = .rejected
        } else if removalRatio <= AlgorithmConstants.highQualityThreshold {
            quality = .high
        } else {
            quality = .acceptable
        }

        // Stage 5: Compute rMSSD from valid intervals
        let rmssd = computeRMSSD(filtered)
        let lnRmssd = rmssd > 0 ? log(rmssd) : 0

        return HRVEpoch(
            startTime: startTime,
            endTime: endTime,
            sleepStage: .unknown,
            rmssd: rmssd,
            lnRmssd: lnRmssd,
            quality: quality,
            beatsTotal: originalCount,
            beatsRemoved: beatsRemoved
        )
    }

    // MARK: - Nightly Aggregation

    /// Processes multiple epochs and returns an aggregated nightly HRV result.
    ///
    /// Computes Ln(rMSSD) for each valid epoch, then takes the median — robust to
    /// outlier epochs and aligned with the Plews/Buchheit methodology and Oura's approach.
    ///
    /// - Parameters:
    ///   - epochs: Array of tuples containing RR intervals and time bounds for each epoch.
    ///   - date: The date to associate with the result (defaults to current date).
    /// - Returns: An `HRVNightResult`, or nil if no valid epochs remain.
    public func processNight(
        epochs: [(rrIntervals: [Double], start: Date, end: Date)],
        date: Date = Date()
    ) -> HRVNightResult? {
        var processedEpochs: [HRVEpoch] = []

        for epoch in epochs {
            guard epoch.rrIntervals.count >= 10 else { continue }
            let result = processEpoch(
                rrIntervals: epoch.rrIntervals,
                startTime: epoch.start,
                endTime: epoch.end
            )
            processedEpochs.append(result)
        }

        guard !processedEpochs.isEmpty else { return nil }

        let validEpochs = processedEpochs.filter { $0.quality != .rejected }
        guard !validEpochs.isEmpty else { return nil }

        let lnValues = validEpochs.map { $0.lnRmssd }
        let medianLn = median(lnValues)
        let medianRmssd = exp(medianLn)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        return HRVNightResult(
            date: dateFormatter.string(from: date),
            medianLnRmssd: medianLn,
            medianRmssd: medianRmssd,
            epochsTotal: processedEpochs.count,
            epochsValid: validEpochs.count,
            epochsHighQuality: processedEpochs.filter { $0.quality == .high }.count,
            epochs: processedEpochs
        )
    }

    // MARK: - Artifact Correction

    /// Stage 2: Removes intervals where the successive difference exceeds 75% of
    /// the previous interval (Plews method).
    ///
    /// Reference: Plews et al. (2017) — successive difference filter for PPG artifact removal.
    public func successiveDifferenceFilter(_ intervals: [Double]) -> [Double] {
        guard intervals.count >= 2 else { return intervals }

        var result: [Double] = [intervals[0]]

        for i in 1..<intervals.count {
            let diff = abs(intervals[i] - intervals[i - 1])
            let threshold = intervals[i - 1] * AlgorithmConstants.successiveDiffThreshold

            if diff <= threshold {
                result.append(intervals[i])
            }
        }

        return result
    }

    /// Stage 3: Removes intervals outside Q1 − 0.25×IQR to Q3 + 0.25×IQR.
    ///
    /// Reference: Plews et al. (2017) — IQR-based outlier bounds for RR interval cleaning.
    public func iqrFilter(_ intervals: [Double]) -> [Double] {
        guard intervals.count >= 4 else { return intervals }

        let sorted = intervals.sorted()
        let q1Index = sorted.count / 4
        let q3Index = (sorted.count * 3) / 4

        let q1 = sorted[q1Index]
        let q3 = sorted[q3Index]
        let iqr = q3 - q1

        let lowerBound = q1 - AlgorithmConstants.iqrMultiplier * iqr
        let upperBound = q3 + AlgorithmConstants.iqrMultiplier * iqr

        return intervals.filter { $0 >= lowerBound && $0 <= upperBound }
    }

    // MARK: - rMSSD Computation

    /// Computes the root mean square of successive differences from an array of RR intervals.
    ///
    /// rMSSD reflects short-term, beat-to-beat vagal (parasympathetic) activity and is the
    /// gold standard metric for athlete HRV monitoring (Buchheit 2014, Plews et al. 2013).
    ///
    /// - Parameter intervals: Cleaned RR intervals in milliseconds.
    /// - Returns: rMSSD value in milliseconds, or 0 if fewer than 2 intervals.
    public func computeRMSSD(_ intervals: [Double]) -> Double {
        guard intervals.count >= 2 else { return 0 }

        var sumSquaredDiffs: Double = 0
        var count = 0

        for i in 1..<intervals.count {
            let diff = intervals[i] - intervals[i - 1]
            sumSquaredDiffs += diff * diff
            count += 1
        }

        guard count > 0 else { return 0 }
        return sqrt(sumSquaredDiffs / Double(count))
    }

    // MARK: - Statistics

    /// Returns the median of an array of Doubles.
    public func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2

        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }
}
