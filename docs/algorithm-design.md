# Enhanced HRV rMSSD Capture Algorithm -- Design & Research Reassessment

## IntervalsWellnessSync -- Technical Design Document

---

## 1. Algorithm Overview

The Enhanced HRV Mode uses beat-to-beat RR interval data collected during sleep to compute rMSSD (root mean square of successive differences) -- the gold standard parasympathetic HRV metric for athlete monitoring.

### Why rMSSD Over SDNN

Apple Watch natively stores HRV as SDNN in HealthKit. However, the sport science and autonomic monitoring literature strongly favors rMSSD because:

- It reflects short-term, beat-to-beat vagal (parasympathetic) activity rather than total autonomic variability
- It is more robust to missing data and artifact than frequency-domain parameters
- It is the metric used by WHOOP, Oura, Polar, and Kubios for recovery monitoring
- The Plews/Buchheit framework -- the most widely cited methodology for HRV-guided training in endurance athletes -- is built entirely on Ln rMSSD (natural log of rMSSD) with 7-day rolling averages

### Core Pipeline

```
Raw RR Intervals (any source)
    |
    v
Stage 1: Range Filter (300-2000ms)
    |
    v
Stage 2: Successive Difference Filter (Plews 75%)
    |
    v
Stage 3: IQR Outlier Removal (Q1/Q3 +/- 0.25 x IQR)
    |
    v
Stage 4: Quality Gate (reject >36% beats removed)
    |
    v
Stage 5: rMSSD Computation per 5-Minute Epoch
    |
    v
Nightly Aggregation: Median of Ln(rMSSD) across valid epochs
    |
    v
7-Day Rolling Average + CV for trend detection
```

---

## 2. Original Algorithm Design

### 2.1 Capture Windows

The original design proposed duty cycling based on sleep stage:

| Sleep Stage | Sensor Duty Cycle | Rationale |
|---|---|---|
| Core (N2) | 5 min on / 5 min off | Highest yield -- most total time, good sensitivity |
| Deep (N3/SWS) | 5 min on / 10 min off | Longer homogeneous segments, can sample less |
| REM | Sensor OFF | Sympathetic variability contaminates parasympathetic signal |
| Wake / Transitions | Sensor OFF | Not representative of resting autonomic state |

**Target:** ~25-27 valid 5-minute capture windows per night across NREM sleep only.

### 2.2 rMSSD Calculation

For each 5-minute epoch of collected RR intervals:

```swift
func calculateRMSSD(from rrIntervals: [Double]) -> Double? {
    guard rrIntervals.count >= 2 else { return nil }

    var sumSquaredDiffs: Double = 0
    var validPairs = 0

    for i in 1..<rrIntervals.count {
        let diff = rrIntervals[i] - rrIntervals[i - 1]

        // Ectopic beat filter: skip if successive difference > 25%
        let threshold = 0.25 * rrIntervals[i - 1]
        guard abs(diff) <= threshold else { continue }

        sumSquaredDiffs += diff * diff
        validPairs += 1
    }

    guard validPairs > 0 else { return nil }
    return sqrt(sumSquaredDiffs / Double(validPairs))
}
```

### 2.3 Artifact Rejection

- Ectopic beat detection: flag RR intervals differing from previous by >25%
- Remove flagged beats and adjacent intervals
- Reject entire 5-minute window if >5-10% of beats are flagged
- Reject windows where accelerometer indicates wrist motion

### 2.4 Nightly Aggregation

- Report the **median** rMSSD across all valid NREM windows (not mean -- robust to outlier epochs)
- Apply natural log transformation: Ln rMSSD
- Feed into 7-day rolling average and CV (coefficient of variation)

---

## 3. Research Reassessment

The following sections evaluate each design decision against peer-reviewed evidence. Key reviews and primary studies are cited to identify where the original design is well-supported, where it needs revision, and where important trade-offs exist.

### 3.1 The 5-Minute Epoch Standard

**Verdict: WELL SUPPORTED -- no change needed.**

The 5-minute recording window is the de facto standard in HRV research and is used consistently across clinical and applied sport science contexts. The European Society of Cardiology Task Force (1996) established the 5-minute short-term recording as the minimum standard for time-domain HRV analysis.

Multiple validation studies confirm this window length:

- Oura Ring computes nightly HRV by segmenting data into 5-minute samples and averaging across the night (confirmed in the PMC wearable validation study, Patel et al., 2024).
- Polar uses a 4-hour window after sleep onset but calculates metrics from constituent 5-minute blocks.
- The Herzig et al. (2017) reproducibility study in *Frontiers in Physiology* analyzed HRV specifically in 5-minute segments across sleep stages.
- The Oura Ring ECG validation study (PMC 11644394) found that rMSSD accuracy at the 5-minute level showed high correlation with ECG reference, improving further when averaged over 30-minute epochs and substantially more at the whole-night level.

**Design implication:** The 5-minute epoch is not merely conventional -- it provides enough beats (typically 300-400 at resting heart rates) for statistically stable rMSSD estimates while being short enough to fall within a single sleep stage.


### 3.2 Sleep Stage Filtering -- The Critical Reassessment

**Verdict: ORIGINAL DESIGN NEEDS SIGNIFICANT REVISION.**

The original design excluded REM sleep entirely and favored NREM-only capture. The research paints a more nuanced picture.

#### 3.2a -- rMSSD Reliability Across Sleep Stages

A key study by researchers at Penn State (published in the *American Journal of Physiology -- Heart and Circulatory Physiology*, 2022) examined HRV reliability across N2, SWS, and REM during both stable and disrupted sleep in 27 participants using polysomnography. Their findings:

- **rMSSD was reliable across all three sleep stages** -- N2, SWS, and REM -- during both stable and disrupted sleep
- Cortical arousals did not substantially impact rMSSD intraindividual reliability
- This contrasts with LF HRV, which showed questionable reliability in SWS

This was corroborated by the Herzig et al. (2017) reproducibility study, which found:

- **SWS (deep sleep) had the best night-to-night reproducibility** for heart rate, HF power, and rMSSD -- between-segment variance was only 8-12% of total variance
- **N2 (core sleep) was second best** in reproducibility
- **REM had the highest residual variance** and poorest reproducibility
- However, even in REM, the between-subject ICC for rMSSD remained acceptable

#### 3.2b -- HRV Varies Systematically Across the Night

A critical finding from Boudreau et al. (2013, *Sleep*) and the PMC study on aggregating HRV indices across sleep epochs:

- HRV shows **significant circadian variation** within each sleep stage across the night
- Simply averaging all N2 epochs or all SWS epochs implicitly assumes HRV is consistent within a stage type -- it is not
- Early-night NREM and late-night NREM may differ substantially, independent of sleep stage

This means that the position of the capture window in the night matters, not just the sleep stage label.

#### 3.2c -- Apple Watch Sleep Stage Accuracy Is a Major Constraint

This is the most consequential finding for the algorithm design. According to Apple's own validation study (updated October 2025) and independent research:

- Apple Watch correctly identifies **deep sleep ~62% of the time**, misclassifying it as core sleep 38% of the time
- **REM detection is better at ~81%**, with 15% misclassified as core sleep
- Overall 4-stage classification accuracy trails Oura Ring by approximately 5%

**This means:** If we implement a sleep-stage-filtered capture that turns the sensor off during "REM," we will actually be turning the sensor off during NREM ~15-19% of the time (when Apple Watch wrongly labels core/deep as REM). Conversely, some of our "NREM" capture windows will actually be REM epochs that Apple Watch misclassified.

The sleep stage filter introduces classification noise that may degrade the signal quality more than the physiological noise of including REM epochs.

#### 3.2d -- Revised Recommendation

**Capture during ALL sleep stages (Core + Deep + REM), but NOT wake.**

The rationale:

1. rMSSD is reliable across all NREM and REM stages (Penn State 2022 study)
2. Apple Watch sleep stage misclassification (~20-38% error rate depending on stage) means stage-based filtering introduces substantial noise
3. What Apple Watch *can* reliably detect is **sleep vs. wake** -- this binary distinction is the one that actually matters for filtering
4. Using median aggregation across all sleep-stage windows naturally down-weights outlier REM epochs without requiring accurate stage classification
5. This approach mirrors what Oura does: segment all sleep into 5-minute windows, compute rMSSD for each, and average across the entire night

**However**, if future Apple Watch models improve sleep staging accuracy, revisiting NREM-only capture becomes worthwhile. The design should be modular enough to enable this.


### 3.3 Artifact Correction -- Needs Strengthening

**Verdict: THE 25% THRESHOLD IS TOO AGGRESSIVE. MULTI-STAGE APPROACH NEEDED.**

#### 3.3a -- rMSSD Is Exceptionally Sensitive to Artifacts

The Saboul et al. (2022, *Sensors*) study comparing artifact sensitivity across HRV parameters found that rMSSD was **more sensitive to artifacts than frequency-domain parameters**. In supine recordings, rMSSD exceeded the tolerance threshold with just 0.9% of artifacts in the signal -- meaning even a tiny number of uncorrected ectopic beats can distort the reading.

Marco Altini's applied work on PPG artifact removal confirms this: a single misdirected beat in a 5-minute window can produce rMSSD values that are not slightly noisy but fundamentally unrelated to the true artifact-free value.

#### 3.3b -- How Much Artifact Can We Actually Tolerate?

The Sheridan et al. (2020, *Sensors*) study provides the best empirical answer. They systematically removed increasing percentages of beats and measured the impact on HRV metrics:

- **rMSSD tolerated removal of up to 36% of beats** without clinically significant change (defined as <5% mean absolute percent difference)
- This held for both random and consecutive beat removal
- However, **shifting the timing of beat detection by 3-5 samples** (i.e., the peak-picking error common in PPG) quickly altered rMSSD significantly
- This finding means that **removing suspicious beats is safer than trying to interpolate them** for rMSSD specifically

#### 3.3c -- Implemented Multi-Stage Artifact Pipeline

Based on the Kubios methodology (Lipponen & Tarvainen, 2019) and Altini's applied approach:

**Stage 1 -- Range Filter:**
Remove any RR interval outside physiological bounds (<300ms or >2000ms, corresponding to heart rates of 30-200 bpm).

**Stage 2 -- Successive Difference Filter (Ectopic Detection):**
The Plews et al. (2017) method:
- Remove intervals where the successive difference exceeds 75% of the previous interval

**Stage 3 -- IQR Outlier Removal:**
- Remove outliers beyond Q1 - 0.25 x IQR to Q3 + 0.25 x IQR

This two-stage approach from Plews is less aggressive than a flat 25% threshold and adapts to the individual's actual HRV level.

**Stage 4 -- Quality Gate:**
- Calculate the ratio of removed beats to total beats for each 5-minute window
- **Accept:** <10% beats removed (high confidence)
- **Flag:** 10-36% beats removed (acceptable per Sheridan, but mark quality)
- **Reject:** >36% beats removed (too much artifact for reliable rMSSD)

#### 3.3d -- Correction Method: Delete, Don't Interpolate

For rMSSD specifically, the Sheridan data supports **deletion over interpolation**. Removing ectopic beats and their flanking intervals, then computing rMSSD from the remaining valid successive pairs, is more robust than attempting to estimate what the normal beat should have been.


### 3.4 Nightly Aggregation -- Median vs. Mean

**Verdict: MEDIAN IS WELL SUPPORTED, BUT LN-TRANSFORM FIRST.**

The Plews/Buchheit methodology uses the natural log transformation of rMSSD (Ln rMSSD) as the standard working metric because raw rMSSD has a skewed distribution. Logging first enables parametric statistical comparisons.

The recommended aggregation pipeline:

1. Compute rMSSD for each valid 5-minute epoch
2. Apply natural log: Ln(rMSSD) for each epoch
3. Report the **median Ln rMSSD** across all valid epochs as the nightly value
4. Feed nightly values into the 7-day rolling average

The median is preferred over the mean because:
- It is robust to outlier epochs (e.g., a brief period of motion artifact that passed the quality gate)
- It is less affected by the non-normal distribution of rMSSD values within a night
- It aligns with how Oura and validated research approaches handle multi-epoch aggregation


### 3.5 Weekly Metrics -- Rolling Average and CV

**Verdict: STRONGLY SUPPORTED. This is the core of the Plews/Buchheit framework.**

A 2025 narrative review in *Sensors* (Monitoring Training Adaptation and Recovery Status in Athletes Using Heart Rate Variability via Mobile Devices) comprehensively validates this approach:

- **RMSSD_MEAN** (weekly average of daily Ln rMSSD): Reflects chronic adaptation -- a stable or increasing trend indicates positive training adaptation
- **RMSSD_CV** (coefficient of variation: SD/Mean x 100): Reflects acute homeostatic perturbation -- elevated CV signals the body is struggling to maintain autonomic balance
- The combination of mean and CV is essential: a drop in mean alone could be acute fatigue or maladaptation; elevated CV alongside a stable mean suggests the training load is approaching the limit of functional overreaching

**Minimum data requirement:** Plews et al. (2014, *Int J Sports Physiol Perform*) established that a minimum of 3 randomly selected valid data points per week is needed for Ln rMSSD averages to plateau in reliability. Beyond 3-4 days, additional data points provide diminishing returns.

The Plews/Buchheit "normal range" for HRV-guided training decisions is calculated as:

```
Normal range = Baseline Ln rMSSD_MEAN +/- 0.5 x SD
```

When the daily value falls below this range, the recommendation is to reduce training intensity. When within or above, proceed with planned training.


### 3.6 Wearable PPG vs. ECG Accuracy for rMSSD

**Verdict: ACKNOWLEDGED LIMITATION -- Apple Watch PPG is noisier than ECG but sufficient with proper artifact handling.**

The multi-device validation study (PMC 12367097) comparing Garmin, Oura Gen 3, Oura Gen 4, Polar, and WHOOP against ECG reference found:

- Consumer wearables using PPG can provide accurate nocturnal rMSSD, but accuracy varies significantly between devices
- The Oura Ring ECG validation study found that at the 5-minute level, individual rMSSD readings could have >10% error (especially in older adults), but this error was random and cancelled out when averaged over 30-minute or whole-night windows
- PPG accuracy degrades with: motion, poor skin contact, reduced peripheral perfusion (cold), and older age (arterial stiffness affects peak detection)

Apple Watch uses wrist-based PPG, which is generally considered less precise than finger-based (Oura Ring) for beat-to-beat timing. However, during sleep with minimal motion, wrist PPG quality improves significantly.

**Key insight from the Oura validation:** At stringent quality thresholds (80% valid beats), 5-minute rMSSD correlated highly with ECG. With aggregation to the nightly level, even moderate quality data produced accurate results because random measurement noise cancelled out. This validates the multi-epoch median approach.


---

## 4. Revised Algorithm Summary

### What Changed From Original Design

| Component | Original | Revised | Why |
|---|---|---|---|
| Sleep stage filter | NREM only, REM excluded | All sleep, wake excluded | rMSSD reliable in all stages; Apple Watch stage accuracy too low for filtering |
| Ectopic threshold | Fixed 25% successive diff | Multi-stage (Plews 75% + IQR) | Research supports graduated approach |
| Window rejection | >5-10% beats flagged | >36% beats removed | Sheridan 2020 data shows rMSSD tolerates high removal rates |
| Artifact handling | Skip + remove adjacent | Delete beats, don't interpolate | Deletion safer than interpolation for rMSSD |
| Log transform timing | After aggregation | Before aggregation (per-epoch) | Standard Plews methodology; enables parametric statistics |

### What Remained Unchanged

- 5-minute epoch duration (universally validated)
- Median aggregation across epochs (robust to outliers)
- 7-day rolling Ln rMSSD average and CV (Plews/Buchheit gold standard)
- Motion-based window rejection (accelerometer)
- Quality flagging per-epoch for transparency

### Architecture for Future Flexibility

The design stores per-epoch metadata:

```swift
struct HRVEpoch {
    let startTime: Date
    let endTime: Date
    let sleepStage: SleepStage
    let rmssd: Double
    let lnRmssd: Double
    let quality: EpochQuality    // .high, .acceptable, .rejected
    let beatsTotal: Int
    let beatsRemoved: Int
    let motionDetected: Bool
}
```

This allows retroactive re-analysis if sleep staging accuracy improves, and enables users to compare NREM-only vs. all-sleep rMSSD for their own data.

---

## 5. Key Research References

### Reviews and Methodological Frameworks

1. **Buchheit (2014)** -- "Monitoring training status with HR measures: do all roads lead to Rome?" *Frontiers in Physiology*, 5:73. The foundational review establishing Ln rMSSD as the preferred metric and outlining rolling average methodology.

2. **Plews, Laursen, Stanley, Kilding, & Buchheit (2013)** -- "Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring." *Sports Medicine*, 43:773-781. Established interpretation frameworks for HRV in elite athletes including saturation phenomena.

3. **Sensors 2025 Narrative Review** -- "Monitoring Training Adaptation and Recovery Status in Athletes Using Heart Rate Variability via Mobile Devices." Comprehensive 2025 review validating RMSSD_MEAN and RMSSD_CV as the primary weekly metrics.

4. **Plews, Laursen, Le Meur, Hausswirth, Kilding, & Buchheit (2014)** -- "Monitoring training with heart rate-variability: how much compliance is needed for valid assessment?" *Int J Sports Physiol Perform*. Established the minimum 3 days/week requirement.

### Sleep Stage HRV Reliability

5. **Penn State Study (2022)** -- "Reliability of heart rate variability during stable and disrupted polysomnographic sleep." *Am J Physiol Heart Circ Physiol*. Demonstrated rMSSD reliability across N2, SWS, and REM in both stable and disrupted sleep.

6. **Herzig et al. (2017)** -- "Reproducibility of Heart Rate Variability Is Parameter and Sleep Stage Dependent." *Frontiers in Physiology*, 8:1100. Found SWS has best rMSSD reproducibility (8-12% between-segment variance); REM has poorest.

7. **Boudreau et al. (2013)** -- "Circadian Variation of Heart Rate Variability Across Sleep Stages." *Sleep*. Demonstrated significant circadian modulation of HRV within sleep stages.

8. **PMC 8923916** -- "Aggregating heart rate variability indices across sleep stage epochs ignores significant variance through the night." Showed HRV changes systematically across the night within the same stage type.

### Artifact Correction and Data Quality

9. **Sheridan et al. (2020)** -- "Heart Rate Variability Analysis: How Much Artifact Can We Remove?" *Sensors*. Established that rMSSD tolerates up to 36% beat removal without clinically significant change (<5% MAPD).

10. **Saboul et al. (2022)** -- "RMSSD Is More Sensitive to Artifacts Than Frequency-Domain Parameters." *Sensors*. Showed rMSSD exceeds tolerance threshold with just 0.9% uncorrected artifacts.

11. **Lipponen & Tarvainen (2019)** -- Kubios automatic artifact correction algorithm. Validated adaptive threshold approach using dRR series with 5.2 x quartile deviation.

### Wearable Validation

12. **PMC 12367097 (2025)** -- "Validation of nocturnal resting heart rate and heart rate variability in consumer wearables." Compared Garmin, Oura Gen 3/4, Polar, WHOOP against ECG across 536 nights.

13. **PMC 11644394 (2024)** -- "Deriving Accurate Nocturnal Heart Rate, rMSSD and Frequency HRV from the Oura Ring." Showed 80% validity threshold + nightly aggregation produces highly accurate rMSSD.

14. **Apple (2025)** -- "Estimating Sleep Stages from Apple Watch." Updated validation showing ~62% deep sleep accuracy, ~81% REM accuracy.

15. **SLEEP Advances (2025)** -- "A performance validation of six commercial wrist-worn wearable sleep-tracking devices for sleep stage scoring compared to polysomnography." Independent 62-participant multi-device comparison.

### Applied Monitoring

16. **Schmitt et al. (2015)** -- "Monitoring Fatigue Status with HRV Measures in Elite Athletes: An Avenue Beyond RMSSD?" *Frontiers in Physiology*. Acknowledges rMSSD limitations while confirming it as the most practical daily metric.

17. **Altini & Plews (2021)** -- "What is behind changes in resting heart rate and heart rate variability?" Large-scale longitudinal analysis of free-living measurements.

18. **Terra Research (2026)** -- "How HRV Actually Works." Population-level comparison of RMSSD vs SDNN across Oura, Apple, Garmin, and Fitbit. Confirmed that most wearables report rMSSD via 5-minute mean windows.

---

## 6. Open Questions

### 6.1 PPG Timing Precision

The accuracy of rMSSD depends on sub-millisecond precision in RR interval timing. PPG sampling frequency and peak-detection algorithm precision vary between devices. The Sheridan data suggests that even small timing shifts (3-5 samples) can significantly alter rMSSD. This needs empirical validation with specific hardware.

### 6.2 NREM-Only Mode as User Option

Given that NREM-only capture is scientifically superior *if* sleep staging were perfect, consider offering it as an advanced toggle once enough per-epoch data is collected to let users compare their own NREM-only vs. all-sleep rMSSD values and decide based on their individual data.

### 6.3 Morning Spot-Check as Complementary Capture

The Buchheit (2014) review noted that the most recommended approach in the applied literature is a supine morning rMSSD reading upon waking. Overnight data is richer, but a quick wake-up reading (1-2 minutes) could serve as a validation anchor and fallback if overnight capture fails.
