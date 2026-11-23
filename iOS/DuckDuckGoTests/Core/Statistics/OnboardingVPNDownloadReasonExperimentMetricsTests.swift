//
//  OnboardingVPNDownloadReasonExperimentMetricsTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Testing
import PixelExperimentKit
@testable import Core

@Suite("Onboarding VPN download-reason experiment metrics")
final class OnboardingVPNDownloadReasonExperimentMetricsTests {

    private struct ThresholdCall: Equatable {
        let metric: String
        let window: ConversionWindow
        let threshold: Int
    }

    private struct ValueCall: Equatable {
        let metric: String
        let window: ConversionWindow
        let value: String
    }

    private let userDefaults: UserDefaults
    private let suiteName = "OnboardingVPNDownloadReasonExperimentMetricsTests-\(UUID().uuidString)"
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var thresholdCalls: [ThresholdCall] = []
    private var valueCalls: [ValueCall] = []
    private var subfeatureIDs: Set<String> = []
    private var reasonToken: String?

    init() {
        userDefaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeSUT() -> OnboardingVPNDownloadReasonExperimentMetrics {
        OnboardingVPNDownloadReasonExperimentMetrics(
            downloadReasonToken: { [unowned self] in self.reasonToken },
            userDefaults: userDefaults,
            calendar: calendar,
            fireExperimentPixel: { [unowned self] subfeatureID, metric, window, value in
                self.subfeatureIDs.insert(subfeatureID)
                self.valueCalls.append(ValueCall(metric: metric, window: window, value: value))
            },
            fireExperimentPixelIfThresholdReached: { [unowned self] subfeatureID, metric, window, threshold in
                self.subfeatureIDs.insert(subfeatureID)
                self.thresholdCalls.append(ThresholdCall(metric: metric, window: window, threshold: threshold))
            }
        )
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func windows(for metric: String, threshold: Int) -> Set<ConversionWindow> {
        Set(thresholdCalls.filter { $0.metric == metric && $0.threshold == threshold }.map(\.window))
    }

    // MARK: - Per download reason

    @available(iOS 16, macOS 13, *)
    @Test("App use fires per reason on D1, D5-7 and D8-14", .timeLimit(.minutes(1)))
    func appUseByReason() {
        reasonToken = "vpn"

        makeSUT().fireAppUseMetrics()

        #expect(windows(for: "download_reason_app_use_vpn", threshold: 1) == [1...1, 5...7, 8...14])
        #expect(thresholdCalls.allSatisfy { $0.metric == "download_reason_app_use_vpn" })
        #expect(subfeatureIDs == ["onboardingVPNDownloadReasonExperiment"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Search fires per reason on D0, D1, D5-7 and D8-14", .timeLimit(.minutes(1)))
    func searchByReason() {
        reasonToken = "ad-blocking"

        makeSUT().fireSearchMetrics()

        let metric = "download_reason_search_retention_ad-blocking"
        #expect(windows(for: metric, threshold: 1) == [0...0, 1...1, 5...7, 8...14])
        for threshold in [4, 6, 11, 21, 30] {
            #expect(windows(for: metric, threshold: threshold) == [5...7, 8...14])
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Duck.ai prompts fire per reason on D0, D1, D5-7 and D8-14", .timeLimit(.minutes(1)))
    func aiPromptByReason() {
        reasonToken = "ai-chat"

        makeSUT().fireAIPromptMetrics()

        #expect(windows(for: "download_reason_ai_prompt_ai-chat", threshold: 1) == [0...0, 1...1, 5...7, 8...14])
        #expect(thresholdCalls.count == 4)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without a download reason, nothing per reason fires", .timeLimit(.minutes(1)))
    func noReason() {
        reasonToken = nil
        let sut = makeSUT()

        sut.fireAppUseMetrics()
        sut.fireSearchMetrics()
        sut.fireAIPromptMetrics()

        #expect(thresholdCalls.isEmpty)
    }

    // MARK: - Search only

    @available(iOS 16, macOS 13, *)
    @Test("Search only uses the standard search windows and thresholds", .timeLimit(.minutes(1)))
    func searchOnly() {
        makeSUT().fireSearchOnlyMetrics()

        #expect(windows(for: "search_only", threshold: 1) == [0...0, 1...1, 2...2, 3...3, 4...4, 5...5, 6...6, 7...7, 5...7, 8...14])
        for threshold in [4, 6, 11, 21, 30] {
            #expect(windows(for: "search_only", threshold: threshold) == [5...7, 8...14])
        }
        #expect(thresholdCalls.allSatisfy { $0.metric == "search_only" })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Search only also fires per reason, with the per-reason search windows", .timeLimit(.minutes(1)))
    func searchOnlyByReason() {
        reasonToken = "no-ai"

        makeSUT().fireSearchOnlyMetrics()

        let metric = "download_reason_search_only_no-ai"
        #expect(windows(for: metric, threshold: 1) == [0...0, 1...1, 5...7, 8...14])
        for threshold in [4, 6, 11, 21, 30] {
            #expect(windows(for: metric, threshold: threshold) == [5...7, 8...14])
        }
    }

    // MARK: - Subscribers

    @available(iOS 16, macOS 13, *)
    @Test("A purchase sends subscribed for D0-4", .timeLimit(.minutes(1)))
    func purchaseSendsSubscribed() {
        makeSUT().recordSubscriptionPurchase(enrollmentDate: date(1), now: date(2))

        #expect(valueCalls == [ValueCall(metric: "subscribed", window: 0...4, value: "1")])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A purchase on D0-4 adds the subscriber metrics to app use and search", .timeLimit(.minutes(1)),
          arguments: [1, 5])
    func purchaseWithinWindowMakesSubscriber(purchaseDay: Int) {
        let sut = makeSUT()
        sut.recordSubscriptionPurchase(enrollmentDate: date(1, hour: 23), now: date(purchaseDay, hour: 0))

        sut.fireAppUseMetrics()
        sut.fireSearchMetrics()

        #expect(windows(for: "subscriber_app_use", threshold: 1) == [5...7])
        for threshold in [1, 4, 6, 11, 21, 30] {
            #expect(windows(for: "subscriber_search", threshold: threshold) == [5...7])
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A purchase after D4 doesn't make the user a subscriber", .timeLimit(.minutes(1)))
    func purchaseAfterWindowDoesNotMakeSubscriber() {
        let sut = makeSUT()
        sut.recordSubscriptionPurchase(enrollmentDate: date(1), now: date(6))

        sut.fireAppUseMetrics()
        sut.fireSearchMetrics()

        #expect(!thresholdCalls.contains { $0.metric.hasPrefix("subscriber_") })
    }

    @available(iOS 16, macOS 13, *)
    @Test("A purchase by a device that isn't enrolled doesn't make it a subscriber", .timeLimit(.minutes(1)))
    func purchaseWithoutEnrollmentDoesNotMakeSubscriber() {
        let sut = makeSUT()
        sut.recordSubscriptionPurchase(enrollmentDate: nil, now: date(2))

        sut.fireAppUseMetrics()

        #expect(!thresholdCalls.contains { $0.metric.hasPrefix("subscriber_") })
    }

    // MARK: - VPN

    @available(iOS 16, macOS 13, *)
    @Test("VPN activation and use fire in their windows", .timeLimit(.minutes(1)))
    func vpnMetrics() {
        let sut = makeSUT()

        sut.fireVPNActivated()
        sut.fireVPNUse()

        #expect(valueCalls == [
            ValueCall(metric: "vpn_activated", window: 0...7, value: "1"),
            ValueCall(metric: "vpn_use", window: 8...14, value: "1")
        ])
    }
}
