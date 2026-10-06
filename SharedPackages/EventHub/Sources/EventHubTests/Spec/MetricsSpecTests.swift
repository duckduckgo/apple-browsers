//
//  MetricsSpecTests.swift
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
import Testing
import Foundation
@testable import EventHub

/// Apple's coverage of the cross-platform experiment-metrics specification
/// (`docs/event-hub/tests/metrics.md` in `duckduckgo/ddg-workflow`).
///
/// **Complete case roster.** Every ID the document defines appears below, so this file can be diffed
/// against the document in one place:
///
/// - Binding — M-SEL-1, M-SEL-2, M-SEL-3, M-SEL-4, M-SEL-5, M-SEL-6, M-SEL-7, M-SEL-8, M-SEL-9,
///   M-SEL-10 (M-SEL-8's parent-feature-reading clause is covered by
///   `EventHubExperimentSettingsTests`, since this suite bypasses the config-reading step)
/// - Fan-out — M-FAN-1
/// - Web-event de-duplication — M-DED-1
/// - Configuration lifecycle — M-LIF-1, M-LIF-2, M-LIF-3, M-LIF-4, M-LIF-5, M-LIF-6
///
/// The properties they evidence:
/// - **M-SEL-P1/P2** — declaration is attachment. Requests are produced per (experiment, metric), so
///   two experiments declaring the same metric name stay independent and neither borrows the other's
///   event.
/// - **M-FAN-P1** — within a conversion group `windows × thresholds` form a product; a metric's request
///   set is the union of its groups' products. Apple's framework API takes one window and one threshold
///   per call, so the fan-out is asserted here directly rather than at an absorbing seam.
/// - **M-DED-P1** — metrics consume the hub's de-duplicated stream, the decision being taken once
///   before fan-out.
/// - **M-LIF-P1** — declarations are read live, per event, from current config.
/// - **M-LIF-P2** — events reach metrics only through the hub, so disabling `eventHub` stops them.
///
/// The assertion boundary is the conversion request — `(experiment, metric, conversionWindowDays,
/// threshold)` — observed just past the experiment framework's enrollment gate. See
/// `SpyConversionReporting` for why that is the honest seam on Apple.
@Suite("Spec: experiment metrics")
struct MetricsSpecTests {

    // MARK: The specification's fixture

    /// `contentScopeExperiment1`, the experiment most cases use: four metrics, one of them on a native
    /// event, and `searchLike` carrying two conversion groups so the fan-out is observable.
    static let experiment1 = """
    { "metrics": {
        "captchaSeen": { "event": "captchaDetected", "conversions": [
            { "windows": [[0, 7]], "thresholds": [1, 3] } ] },
        "searchLike": { "event": "searchPerformed", "conversions": [
            { "windows": [[0, 0], [1, 1]], "thresholds": [1] },
            { "windows": [[0, 7]], "thresholds": [2, 3] } ] },
        "pageLoad": { "event": "pageLoaded", "conversions": [
            { "windows": [[0, 5]], "thresholds": [1] } ] },
        "appLaunched": { "event": "appLaunch", "conversions": [
            { "windows": [[0, 7]], "thresholds": [1, 2] } ] }
    } }
    """

    /// Two windows in one group, both at threshold 1.
    static let experiment3 = """
    { "metrics": { "reloadLoop": { "event": "reloadLoopDetected", "conversions": [
        { "windows": [[0, 0], [0, 7]], "thresholds": [1] } ] } } }
    """

    /// Declares `captchaSeen` on the same event as experiment 1, at a different threshold set.
    static let experiment10 = """
    { "metrics": { "captchaSeen": { "event": "captchaDetected", "conversions": [
        { "windows": [[0, 7]], "thresholds": [1] } ] } } }
    """

    /// An enrolled experiment declaring no metrics at all.
    static let experiment19 = "{}"

    /// Declares `captchaSeen` — the same *name* as experiments 1 and 10 — bound to a different event.
    static let experiment21 = """
    { "metrics": { "captchaSeen": { "event": "reloadLoopDetected", "conversions": [
        { "windows": [[0, 7]], "thresholds": [1] } ] } } }
    """

    /// A TDS experiment, under the other parent feature. Its `settings` also carry the control and
    /// treatment URLs a real TDS experiment has, which must decode away without disturbing `metrics`.
    static let tdsExperiment007 = """
    { "controlUrl": "v5/experiments/control.json",
      "treatmentUrl": "v5/experiments/treatment.json",
      "metrics": {
        "blocklistFailure": { "event": "tdsDownloadFailed", "conversions": [
            { "windows": [[0, 7]], "thresholds": [1] } ] },
        "pageLoad": { "event": "pageLoaded", "conversions": [
            { "windows": [[0, 5]], "thresholds": [1] } ] }
    } }
    """

    static let reference: [String: String] = [
        "contentScopeExperiment1": experiment1,
        "contentScopeExperiment3": experiment3,
        "contentScopeExperiment10": experiment10,
        "contentScopeExperiment19": experiment19,
        "contentScopeExperiment21": experiment21,
        "tdsNextExperiment007": tdsExperiment007,
    ]

    /// The fixture with a given experiment's settings replaced — how the lifecycle cases apply a config
    /// that has dropped a metric.
    static func reference(_ experiment: String, replacedWith settings: String) -> [String: String] {
        var config = reference
        config[experiment] = settings
        return config
    }

    /// Experiment 1 with `captchaSeen` removed and its other three metrics untouched (M-LIF-2).
    static let experiment1WithoutCaptchaSeen = """
    { "metrics": {
        "searchLike": { "event": "searchPerformed", "conversions": [
            { "windows": [[0, 0], [1, 1]], "thresholds": [1] },
            { "windows": [[0, 7]], "thresholds": [2, 3] } ] },
        "pageLoad": { "event": "pageLoaded", "conversions": [
            { "windows": [[0, 5]], "thresholds": [1] } ] },
        "appLaunched": { "event": "appLaunch", "conversions": [
            { "windows": [[0, 7]], "thresholds": [1, 2] } ] }
    } }
    """

    /// The metrics suite configures no telemetry: it asserts conversion requests, not pixels.
    private static func fixture(enrolled: Set<String>, experiments: [String: String] = reference) -> SpecFixture {
        SpecFixture("{}", experiments: experiments, enrolled: enrolled)
    }

    // MARK: Binding — metrics attach to the experiment that declares them

    @Test("M-SEL-1: each experiment declaring a metric requests it")
    func eachExperimentDeclaringAMetricRequestsIt() {
        // Experiments 1 and 10 bind `captchaSeen` to the same event, at different threshold sets.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1", "contentScopeExperiment10"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
            "contentScopeExperiment10/captchaSeen/0-7/1",
        ])
    }

    @Test("M-SEL-2: only the declaring experiment requests")
    func onlyTheDeclaringExperimentRequests() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1", "contentScopeExperiment3"])
        f.send("reloadLoopDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment3/reloadLoop/0-7/1",
            "contentScopeExperiment3/reloadLoop/0/1",
        ])
    }

    @Test("M-SEL-3: a shared metric name bound to different events requests per experiment")
    func aSharedMetricNameBoundToDifferentEventsRequestsPerExperiment() {
        // `captchaSeen` is bound to `captchaDetected` in experiment 1 but to `reloadLoopDetected` in
        // experiment 21, so this event reaches 21's copy of the name and not 1's.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1", "contentScopeExperiment3", "contentScopeExperiment21"])
        f.send("reloadLoopDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment21/captchaSeen/0-7/1",
            "contentScopeExperiment3/reloadLoop/0-7/1",
            "contentScopeExperiment3/reloadLoop/0/1",
        ])
    }

    @Test("M-SEL-4: the event named by another experiment's identically-named metric requests nothing here")
    func theEventNamedByAnotherExperimentsIdenticallyNamedMetricRequestsNothingHere() {
        // The mirror of M-SEL-3: experiment 21's `captchaSeen` does not answer to `captchaDetected`.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1", "contentScopeExperiment21"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
        ])
    }

    @Test("M-SEL-5: an enrolled experiment declaring no metrics requests nothing")
    func anEnrolledExperimentDeclaringNoMetricsRequestsNothing() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment19"])
        let page = f.openPage()
        f.send("reloadLoopDetected", reason: "any", on: page)
        f.send("captchaDetected", reason: "any", on: page)

        #expect(f.requested.isEmpty)
    }

    @Test("M-SEL-6: a declared metric whose experiment is not enrolled requests nothing")
    func aDeclaredMetricWhoseExperimentIsNotEnrolledRequestsNothing() {
        // `tdsDownloadFailed` is declared only by tdsNextExperiment007, which the user is not in.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.send("tdsDownloadFailed", reason: "any", on: f.openPage())

        #expect(f.requested.isEmpty)
    }

    @Test("M-SEL-7: a user enrolled in no experiments requests nothing")
    func aUserEnrolledInNoExperimentsRequestsNothing() {
        let f = Self.fixture(enrolled: [])
        let page = f.openPage()
        f.send("captchaDetected", reason: "any", on: page)
        f.send("reloadLoopDetected", reason: "any", on: page)
        f.send("searchPerformed", reason: "any", on: page)
        f.sendNative("appLaunch", payload: ["launchType": "cold"])

        #expect(f.requested.isEmpty)
    }

    @Test("M-SEL-8: metrics attach under both experiment parent features")
    func metricsAttachUnderBothExperimentParentFeatures() {
        // contentScopeExperiment1 sits under `contentScopeExperiments`, tdsNextExperiment007 under
        // `contentBlocking`, so both experiments' `pageLoad` is requested.
        //
        // This suite injects its experiment settings straight into the hub, so the case's other
        // clause — that both parent features are *read* — cannot be observed here: nothing below runs
        // the config-reading step. `EventHubExperimentSettingsTests` pins that leg.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1", "tdsNextExperiment007"])
        f.send("pageLoaded", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/pageLoad/0-5/1",
            "tdsNextExperiment007/pageLoad/0-5/1",
        ])
    }

    @Test("M-SEL-9: an event matching no declared metric is ignored")
    func anEventMatchingNoDeclaredMetricIsIgnored() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.send("somethingUnrelated", reason: "any", on: f.openPage())

        #expect(f.requested.isEmpty)
    }

    @Test("M-SEL-10: a native event with no tab context produces requests")
    func aNativeEventWithNoTabContextProducesRequests() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.sendNative("appLaunch", payload: ["launchType": "cold"])

        #expect(f.requested == [
            "contentScopeExperiment1/appLaunched/0-7/1",
            "contentScopeExperiment1/appLaunched/0-7/2",
        ])
    }

    // MARK: Fan-out — a declaration is a set of requests

    @Test("M-FAN-1: windows and thresholds multiply out within a group; groups do not combine")
    func windowsAndThresholdsMultiplyOutWithinAGroupAndGroupsDoNotCombine() {
        // `searchLike` group 1 is [0,0] and [1,1] at threshold 1; group 2 is [0,7] at thresholds 2 and
        // 3. Four requests, not the six a cross-group product would give.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.send("searchPerformed", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/searchLike/0-7/2",
            "contentScopeExperiment1/searchLike/0-7/3",
            "contentScopeExperiment1/searchLike/0/1",
            "contentScopeExperiment1/searchLike/1/1",
        ])
    }

    // MARK: Web-event de-duplication

    @Test("M-DED-1: repeated occurrences on one page request once")
    func repeatedOccurrencesOnOnePageRequestOnce() {
        // The metrics leg of D-DEL-4: the hub takes one decision before fan-out, so the second and
        // third occurrences reach no handler at all.
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        let page = f.openPage()
        f.send("captchaDetected", reason: "overlay", on: page)
        f.send("captchaDetected", reason: "overlay", on: page)
        f.send("captchaDetected", reason: "overlay", on: page)

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
        ])
    }

    // MARK: Configuration lifecycle

    @Test("M-LIF-1: a metric and its experiment enabled in one config change both take effect")
    func aMetricAndItsExperimentEnabledInOneConfigChangeBothTakeEffect() {
        // Phase 1: experiment 3 is in config but declares no metrics, and the user is not enrolled.
        // The event is sent anyway — stricter than the document, which only describes phase 2's event.
        let f = Self.fixture(enrolled: [], experiments: Self.reference("contentScopeExperiment3", replacedWith: "{}"))
        f.send("reloadLoopDetected", reason: "any", on: f.openPage())
        #expect(f.requested.isEmpty)

        // Phase 2: the metrics arrive and the user enrolls in the same config change.
        f.setExperiments(Self.reference)
        f.enroll(in: ["contentScopeExperiment3"])
        f.send("reloadLoopDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment3/reloadLoop/0-7/1",
            "contentScopeExperiment3/reloadLoop/0/1",
        ])
    }

    @Test("M-LIF-2: a removed metric stops requesting when the new config applies")
    func aRemovedMetricStopsRequestingWhenTheNewConfigApplies() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        // Removal is the kill switch: effective as soon as the config applies.
        f.setExperiments(Self.reference("contentScopeExperiment1", replacedWith: Self.experiment1WithoutCaptchaSeen))
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
        ])
    }

    @Test("M-LIF-3: a metric declared before its experiment enrolls is inert, then requests on enrollment")
    func aMetricDeclaredBeforeItsExperimentEnrollsIsInertThenRequestsOnEnrollment() {
        let f = Self.fixture(enrolled: [])
        f.send("captchaDetected", reason: "any", on: f.openPage())
        #expect(f.requested.isEmpty)

        f.enroll(in: ["contentScopeExperiment1"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
        ])
    }

    @Test("M-LIF-4: removing a shared-name metric from one experiment stops that experiment only")
    func removingASharedNameMetricFromOneExperimentStopsThatExperimentOnly() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1", "contentScopeExperiment10"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        // Only experiment 10 loses the metric, so experiment 1 requests a second time and 10 stays
        // silent. Requests accumulate across phases, hence experiment 1's pair appearing twice.
        f.setExperiments(Self.reference("contentScopeExperiment10", replacedWith: "{}"))
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
            "contentScopeExperiment1/captchaSeen/0-7/3",
            "contentScopeExperiment10/captchaSeen/0-7/1",
        ])
    }

    @Test("M-LIF-5: a disabled experiment stops requesting when the new config applies")
    func aDisabledExperimentStopsRequestingWhenTheNewConfigApplies() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        // The experiment-level kill switch, distinct from removing the metric (M-LIF-2): its metrics
        // stay declared. A `state: disabled` experiment leaves `allActiveExperiments`, which is what
        // dropping it from the enrolled set models here.
        f.enroll(in: [])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
        ])
    }

    @Test("M-LIF-6: disabling the eventHub feature stops events reaching metrics")
    func disablingTheEventHubFeatureStopsEventsReachingMetrics() {
        let f = Self.fixture(enrolled: ["contentScopeExperiment1"])
        f.send("captchaDetected", reason: "any", on: f.openPage())

        // Evidence for M-LIF-P2: events reach metrics only through the hub. The experiment, its
        // metrics and the enrollment are all untouched — only the feature's own state changes.
        f.setFeatureEnabled(false)
        f.send("captchaDetected", reason: "any", on: f.openPage())

        #expect(f.requested == [
            "contentScopeExperiment1/captchaSeen/0-7/1",
            "contentScopeExperiment1/captchaSeen/0-7/3",
        ])
    }
}
