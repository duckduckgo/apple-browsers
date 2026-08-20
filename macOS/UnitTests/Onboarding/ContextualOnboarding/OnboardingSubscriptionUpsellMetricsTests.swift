//
//  OnboardingSubscriptionUpsellMetricsTests.swift
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

import FeatureFlags_macOS
import Onboarding
import PixelExperimentKit
import PixelKit
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingSubscriptionUpsellMetricsTests: XCTestCase {

    private var firedEvents: [PixelKit.Event]!
    private let subfeatureID = PrivacyProSubfeature.onboardingSubscriptionUpsellExperiment.rawValue

    override func setUp() {
        firedEvents = []
    }

    override func tearDown() {
        firedEvents = nil
    }

    // MARK: - Reporter

    func testWhenMetricIsReportedThenNameValueAndWindowMatchWindows() {
        configureExperimentKit(enrolled: true)

        OnboardingSubscriptionUpsellMetricsReporter().report(.tryForFreeClick)

        let events = firedEvents.filter { $0.parameters?["metric"] == "tryForFreeClick" }
        XCTAssertEqual(events.count, 1)
        // "1" rather than "true": Windows emits the threshold count, and the two are pooled.
        XCTAssertEqual(events.first?.parameters?["value"], "1")
        XCTAssertEqual(events.first?.parameters?["conversionWindowDays"], "0")
    }

    func testWhenDayZeroMetricsAreReportedThenEachEmitsASingleEvent() {
        configureExperimentKit(enrolled: true)
        let dayZero: [OnboardingSubscriptionUpsellMetric] = [.upsellShown, .tryForFreeClick, .noThanksClick, .upsellDismissed]

        dayZero.forEach { OnboardingSubscriptionUpsellMetricsReporter().report($0) }

        for metric in dayZero {
            let windows = firedEvents
                .filter { $0.parameters?["metric"] == metric.rawValue }
                .compactMap { $0.parameters?["conversionWindowDays"] }
            XCTAssertEqual(windows, ["0"], "unexpected windows for \(metric.rawValue)")
        }
    }

    func testWhenTrialStartedIsReportedThenItEmitsBothWindows() {
        configureExperimentKit(enrolled: true)

        OnboardingSubscriptionUpsellMetricsReporter().report(.trialStarted)

        let windows = firedEvents
            .filter { $0.parameters?["metric"] == "trialStarted" }
            .compactMap { $0.parameters?["conversionWindowDays"] }
        XCTAssertEqual(Set(windows), ["0", "0-7"])
    }

    func testWhenNotEnrolledThenNothingIsReported() {
        configureExperimentKit(enrolled: false)

        OnboardingSubscriptionUpsellMetric.allCases.forEach { OnboardingSubscriptionUpsellMetricsReporter().report($0) }

        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Dialog actions

    func testWhenRebrandedUpsellActionsRunThenTheyReportDistinctMetrics() {
        let metrics = SpyUpsellMetricsReporter()
        let delegate = MockOnboardingNavigationDelegate()

        let dialog = RebrandedContextualDaxDialogsFactory.subscriptionUpsellDialog(
            delegate: delegate, metrics: metrics, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})

        dialog.acceptAction()
        XCTAssertEqual(metrics.reported, [.tryForFreeClick])
        XCTAssertTrue(delegate.didNavigateToPurchasePage)

        metrics.reported = []
        dialog.declineAction()
        XCTAssertEqual(metrics.reported, [.noThanksClick])

        metrics.reported = []
        dialog.onManualDismiss()
        XCTAssertEqual(metrics.reported, [.upsellDismissed])
    }

    func testWhenLegacyUpsellActionsRunThenTheyReportDistinctMetrics() {
        let metrics = SpyUpsellMetricsReporter()
        let delegate = MockOnboardingNavigationDelegate()

        let dialog = DefaultContextualDaxDialogViewFactory.subscriptionUpsellDialog(
            delegate: delegate, metrics: metrics, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})

        dialog.acceptAction()
        XCTAssertEqual(metrics.reported, [.tryForFreeClick])
        XCTAssertTrue(delegate.didNavigateToPurchasePage)

        metrics.reported = []
        dialog.declineAction()
        XCTAssertEqual(metrics.reported, [.noThanksClick])

        metrics.reported = []
        dialog.onManualDismiss()
        XCTAssertEqual(metrics.reported, [.upsellDismissed])
    }

    func testWhenUpsellCTAsRunThenTheyDoNotAlsoReportDismissal() {
        let metrics = SpyUpsellMetricsReporter()
        let dialog = RebrandedContextualDaxDialogsFactory.subscriptionUpsellDialog(
            delegate: MockOnboardingNavigationDelegate(), metrics: metrics, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})

        dialog.acceptAction()
        dialog.declineAction()

        XCTAssertFalse(metrics.reported.contains(.upsellDismissed))
    }
}

// MARK: - Helpers

extension OnboardingSubscriptionUpsellMetric: CaseIterable {
    public static var allCases: [OnboardingSubscriptionUpsellMetric] {
        [.upsellShown, .tryForFreeClick, .noThanksClick, .upsellDismissed, .trialStarted]
    }
}

private extension OnboardingSubscriptionUpsellMetricsTests {

    func configureExperimentKit(enrolled: Bool) {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.allActiveExperiments = enrolled
            ? [subfeatureID: ExperimentData(parentID: PrivacyFeature.privacyPro.rawValue,
                                            cohortID: FeatureFlag.OnboardingSubscriptionUpsellCohort.treatment.rawValue,
                                            enrollmentDate: Date())]
            : [:]
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
            fire: { event, _, _ in self.firedEvents.append(event) }
        )
    }
}

private final class SpyUpsellMetricsReporter: OnboardingSubscriptionUpsellMetricsReporting {
    var reported: [OnboardingSubscriptionUpsellMetric] = []

    func report(_ metric: OnboardingSubscriptionUpsellMetric) {
        reported.append(metric)
    }
}

private final class MockOnboardingNavigationDelegate: OnboardingNavigationDelegate {
    var didNavigateToPurchasePage = false

    func searchFromOnboarding(for query: String) {}

    func navigateFromOnboarding(to url: URL) {
        didNavigateToPurchasePage = true
    }
}
