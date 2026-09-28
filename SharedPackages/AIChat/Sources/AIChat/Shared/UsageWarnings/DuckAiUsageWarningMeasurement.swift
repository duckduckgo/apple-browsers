//
//  DuckAiUsageWarningMeasurement.swift
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

/// Which card the user saw. Each platform puts this in the pixel name rather than in a parameter,
/// so the three states can be read straight off the event.
public enum DuckAiUsageWarningExposureKind: String {
    case approaching
    case limitReached
    case highUsageModelNotice
}

/// What one appearance of the card was about: the state, plus whichever of the window, the rung and
/// the model id that state has.
public struct DuckAiUsageWarningExposure: Equatable {

    public let kind: DuckAiUsageWarningExposureKind
    public let window: DuckAiUsageWindow?
    /// The rung of the approaching ladder the card was shown at: 50, 75 or 90.
    public let percentBucket: Int?
    public let modelId: String?

    public init(kind: DuckAiUsageWarningExposureKind,
                window: DuckAiUsageWindow? = nil,
                percentBucket: Int? = nil,
                modelId: String? = nil) {
        self.kind = kind
        self.window = window
        self.percentBucket = percentBucket
        self.modelId = modelId
    }
}

public extension DuckAiUsageWarningExposure {

    /// Every reached id folds into `.limitReached`: the degraded one leaves free models available,
    /// but the state the user is looking at is the same blocked one.
    init(warning: DuckAiUsageWarning) {
        switch warning.message {
        case .approaching:
            self.init(kind: .approaching,
                      window: warning.window,
                      percentBucket: Self.rung(forDisplayedPercent: warning.percent))
        case .freeReached, .dailyReached, .weeklyReachedDegraded, .weeklyReached:
            self.init(kind: .limitReached, window: warning.window)
        }
    }

    init(notice: DuckAiHighUsageModelNotice) {
        self.init(kind: .highUsageModelNotice, modelId: notice.modelId)
    }

    /// Keyed off the displayed percentage, so the reported rung can never disagree with the copy or
    /// the ring. Below the lowest rung there is nothing to report.
    private static func rung(forDisplayedPercent percent: Int) -> Int? {
        [90, 75, 50].first { percent >= $0 }
    }
}

public enum DuckAiUsageWarningMeasurementEvent: Equatable {
    case shown(DuckAiUsageWarningExposure)
    case dismissed(DuckAiUsageWarningExposure)
    case switchModelTapped(DuckAiUsageWarningExposure)
    case upsellTapped(DuckAiUsageWarningExposure)
    case promptSubmitted(DuckAiUsageWarningExposure)
    case modelSwitched(DuckAiUsageWarningExposure)
    case abandoned(DuckAiUsageWarningExposure)
}

public protocol DuckAiUsageWarningPixelFiring {
    func fire(_ event: DuckAiUsageWarningMeasurementEvent)
}

public struct NullDuckAiUsageWarningPixelFiring: DuckAiUsageWarningPixelFiring {
    public init() {}
    public func fire(_ event: DuckAiUsageWarningMeasurementEvent) {}
}

/// Turns the card's lifecycle into the events each platform reports: one impression per appearance,
/// and one follow-through per exposure — what the user did about the message before the input closed.
///
/// An exposure outlives the card. Dismissing or acting on the message takes it off screen while the
/// user carries on typing, and a prompt sent after that still belongs to the warning they saw.
public final class DuckAiUsageWarningMeasurement {

    public enum CTA {
        case switchModel
        case upsell
    }

    private struct Exposure {
        let subject: DuckAiUsageWarningExposure
        var didReportPrompt = false
        var didReportModelSwitch = false
        var didTapCTA = false

        var hasFollowThrough: Bool { didReportPrompt || didReportModelSwitch || didTapCTA }
    }

    private let pixelFiring: DuckAiUsageWarningPixelFiring
    private var exposure: Exposure?

    public init(pixelFiring: DuckAiUsageWarningPixelFiring = NullDuckAiUsageWarningPixelFiring()) {
        self.pixelFiring = pixelFiring
    }

    /// Driven by the card entering the footer slot, never by the message being resolved: the message
    /// is resolved while the input is still collapsed, and only revealed inside the expand animation.
    public func cardBecameVisible(_ subject: DuckAiUsageWarningExposure) {
        // A refresh mid-expand re-applies the same rung once the models land and the CTA copy fills
        // in. That is one appearance.
        guard exposure?.subject != subject else { return }
        endExposure()
        exposure = Exposure(subject: subject)
        pixelFiring.fire(.shown(subject))
    }

    public func warningDismissed() {
        guard let exposure = exposure else { return }
        pixelFiring.fire(.dismissed(exposure.subject))
    }

    public func ctaTapped(_ cta: CTA) {
        guard var exposure = exposure else { return }
        exposure.didTapCTA = true
        self.exposure = exposure
        switch cta {
        case .switchModel: pixelFiring.fire(.switchModelTapped(exposure.subject))
        case .upsell: pixelFiring.fire(.upsellTapped(exposure.subject))
        }
    }

    public func promptSubmitted() {
        guard var exposure = exposure, !exposure.didReportPrompt else { return }
        exposure.didReportPrompt = true
        self.exposure = exposure
        pixelFiring.fire(.promptSubmitted(exposure.subject))
    }

    /// A switch the user made themselves. The card's own switch CTA is already reported as a tap.
    public func modelSwitched() {
        guard var exposure = exposure, !exposure.didReportModelSwitch, !exposure.didTapCTA else { return }
        exposure.didReportModelSwitch = true
        self.exposure = exposure
        pixelFiring.fire(.modelSwitched(exposure.subject))
    }

    /// The input pane closing, collapsing or leaving Duck.ai mode: whatever the user was going to do
    /// about the message, they have done it.
    public func inputSessionEnded() {
        endExposure()
    }

    private func endExposure() {
        guard let exposure = exposure else { return }
        self.exposure = nil
        guard !exposure.hasFollowThrough else { return }
        pixelFiring.fire(.abandoned(exposure.subject))
    }
}
