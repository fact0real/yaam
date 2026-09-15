//
//  NetworkTransceiverAutomatedTester.swift
//  YAAM
//
//  Created by factoreal on 9/13/26.
//

import Combine
import Foundation
import FT8Codec

// MARK: - Test Result Item
nonisolated struct BenchmarkStepResult: Identifiable, Sendable {
    let id = UUID()
    let stepIndex: Int
    let snrDB: Double
    let messageSent: String
    let wasDecoded: Bool
    let decodedMessage: String?
    let decodedSNR: Double?
    let executionDurationMs: Double
}

// MARK: - Benchmark Summary Report
nonisolated struct BenchmarkSummaryReport: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let radioModel: String
    let testedSteps: [BenchmarkStepResult]
    let sensitivityFloorSNR: Double?
    let overallSuccessRatePercent: Double
    let durationSeconds: Double

    var markdownReport: String {
        var lines: [String] = []
        lines.append("# YAAM Network Transceiver Benchmark Report")
        lines.append("**Date:** \(timestamp.formatted(date: .abbreviated, time: .standard))")
        lines.append("**Emulated Transceiver:** \(radioModel)")
        lines.append("**Sensitivity Floor (Min Decodable SNR):** \(sensitivityFloorSNR != nil ? String(format: "%.1f dB", sensitivityFloorSNR!) : "N/A")")
        lines.append("**Overall Success Rate:** \(String(format: "%.1f%%", overallSuccessRatePercent))")
        lines.append("")
        lines.append("| Step | Injected SNR | Message Sent | Decoded? | Decoded SNR | Duration |")
        lines.append("| :--- | :---: | :--- | :---: | :---: | :---: |")

        for step in testedSteps {
            let status = step.wasDecoded ? "✅ Passed" : "❌ Failed"
            let decSNR = step.decodedSNR != nil ? String(format: "%.1f dB", step.decodedSNR!) : "--"
            lines.append("| \(step.stepIndex) | \(String(format: "%.1f dB", step.snrDB)) | `\(step.messageSent)` | \(status) | \(decSNR) | \(String(format: "%.1f ms", step.executionDurationMs)) |")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Automated Tester & DSP Benchmarking Engine
@MainActor
final class NetworkTransceiverAutomatedTester: ObservableObject {
    @Published var isTesting = false
    @Published var progressPercent: Double = 0.0
    @Published var currentStatusMessage: String = "Ready"
    @Published var stepResults: [BenchmarkStepResult] = []
    @Published var latestReport: BenchmarkSummaryReport?

    private var testTask: Task<Void, Never>?

    func runSNRSensitivitySweep(
        radioModel: String,
        rfEngine: SyntheticRFSignalEngine,
        startSNR: Double = 6.0,
        endSNR: Double = -24.0,
        stepDB: Double = 3.0
    ) {
        guard !isTesting else { return }
        isTesting = true
        progressPercent = 0.0
        stepResults.removeAll()
        latestReport = nil
        currentStatusMessage = "Starting automated SNR sensitivity sweep..."

        testTask = Task {
            let startTime = Date()
            var snrValues: [Double] = []
            var current = startSNR
            while current >= endSNR {
                snrValues.append(current)
                current -= stepDB
            }

            let totalSteps = snrValues.count
            var collectedResults: [BenchmarkStepResult] = []
            let testMessage = "CQ TEST W1AW FN31"

            for (index, snr) in snrValues.enumerated() {
                guard !Task.isCancelled else { break }

                self.currentStatusMessage = "Testing step \(index + 1)/\(totalSteps) at SNR \(String(format: "%.1f dB", snr))..."
                self.progressPercent = Double(index) / Double(totalSteps)

                let stepStart = Date()

                // Run DSP synthesis & decode test in detached task
                let result: BenchmarkStepResult = await Task.detached(priority: .userInitiated) {
                    // 1. Synthesize audio with FT8Codec at 12 kHz (standard decoder rate)
                    do {
                        let audio = try FT8Codec.transmitAudio(
                            testMessage,
                            baseFrequencyHz: 1500,
                            protocol: .ft8,
                            sampleRate: 12_000
                        )

                        // 2. Add calibrated Gaussian noise matching target SNR
                        var noisyAudio = audio
                        let count = noisyAudio.count
                        let signalRMS: Float = 0.5
                        let noiseSigma = Double(signalRMS) * pow(10.0, -snr / 20.0)

                        for i in stride(from: 0, to: count, by: 2) {
                            let u1 = max(1e-12, Double.random(in: 0...1))
                            let u2 = Double.random(in: 0...1)
                            let radius = sqrt(-2.0 * log(u1)) * noiseSigma
                            let theta = 2.0 * Double.pi * u2

                            noisyAudio[i] += Float(radius * cos(theta))
                            if i + 1 < count {
                                noisyAudio[i + 1] += Float(radius * sin(theta))
                            }
                        }

                        // 3. Attempt decoding
                        let decodedList = try FT8Codec.decode(
                            samples: noisyAudio,
                            sampleRate: 12_000,
                            protocol: .ft8,
                            maxMessages: 8
                        )

                        let match = decodedList.first { $0.text.contains("W1AW") || $0.text.contains("FN31") }
                        let duration = Date().timeIntervalSince(stepStart) * 1000.0

                        return BenchmarkStepResult(
                            stepIndex: index + 1,
                            snrDB: snr,
                            messageSent: testMessage,
                            wasDecoded: match != nil,
                            decodedMessage: match?.text,
                            decodedSNR: match != nil ? Double(match!.snrDb) : nil,
                            executionDurationMs: duration
                        )
                    } catch {
                        let duration = Date().timeIntervalSince(stepStart) * 1000.0
                        return BenchmarkStepResult(
                            stepIndex: index + 1,
                            snrDB: snr,
                            messageSent: testMessage,
                            wasDecoded: false,
                            decodedMessage: nil,
                            decodedSNR: nil,
                            executionDurationMs: duration
                        )
                    }
                }.value

                collectedResults.append(result)
                self.stepResults = collectedResults
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms pause for UI animation
            }

            let duration = Date().timeIntervalSince(startTime)
            let passedCount = collectedResults.filter(\.wasDecoded).count
            let rate = totalSteps > 0 ? (Double(passedCount) / Double(totalSteps)) * 100.0 : 0.0
            let minDecodable = collectedResults.filter(\.wasDecoded).map(\.snrDB).min()

            let report = BenchmarkSummaryReport(
                timestamp: Date(),
                radioModel: radioModel,
                testedSteps: collectedResults,
                sensitivityFloorSNR: minDecodable,
                overallSuccessRatePercent: rate,
                durationSeconds: duration
            )

            self.latestReport = report
            self.progressPercent = 1.0
            self.isTesting = false
            self.currentStatusMessage = "Benchmark complete! Sensitivity floor: \(minDecodable != nil ? String(format: "%.1f dB", minDecodable!) : "N/A"), Success rate: \(String(format: "%.1f%%", rate))"
        }
    }

    func cancel() {
        testTask?.cancel()
        testTask = nil
        isTesting = false
        currentStatusMessage = "Benchmark cancelled"
    }
}
