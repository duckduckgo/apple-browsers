//
//  DataClearingPixels.swift
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

import Core
import Foundation
import PixelKit

enum DataClearingPixels {

    /// Fire button retriggered within 20 seconds
    case retriggerIn20s

    /// User performed action before data clearing completed
    case userActionBeforeCompletion

    /// A burn request arrived while another burn was still running, so `FireExecutor.burn` dropped it.
    case burnDropped(trigger: String, scope: String, elapsed: ElapsedBucket)
}

// MARK: - Elapsed Bucket

extension DataClearingPixels {

    /// Bucketed seconds. Deliberately not `Pixel.Event.BucketAggregation`, whose top bucket is
    /// "more than 40s" - that collapses a slow burn and an indefinite hang into one value, which is
    /// the distinction this pixel exists to make.
    enum ElapsedBucket: String {
        case lessThan1 = "1"
        case lessThan5 = "5"
        case lessThan10 = "10"
        case lessThan30 = "30"
        case lessThan60 = "60"
        case lessThan120 = "120"
        case lessThan300 = "300"
        case more

        init(seconds: TimeInterval) {
            switch seconds {
            case ...1: self = .lessThan1
            case ...5: self = .lessThan5
            case ...10: self = .lessThan10
            case ...30: self = .lessThan30
            case ...60: self = .lessThan60
            case ...120: self = .lessThan120
            case ...300: self = .lessThan300
            default: self = .more
            }
        }
    }
}

// MARK: - PixelKit.Event Protocol

extension DataClearingPixels: PixelKit.Event {

    private enum ParameterNames {
        static let trigger = "trigger"
        static let scope = "scope"
        static let elapsed = "elapsed"
    }

    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy {
        switch self {
        case .retriggerIn20s, .userActionBeforeCompletion:
            /// These two signatures are non-standard and not aligned to the current PixelKit defaults.
            /// This policy freezes them by not sending the platform marker suffix.
            return .legacyOmitted
        case .burnDropped:
            /// New pixel, and the phone/tablet split matters here: drops are markedly more frequent on iPad.
            return .standard
        }
    }

    var name: String {
        switch self {
        case .retriggerIn20s:
            return "m_fire_retrigger_in_20s"
        case .userActionBeforeCompletion:
            return "m_fire_user_action_before_completion"
        case .burnDropped:
            return "fire_burn-dropped"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .retriggerIn20s, .userActionBeforeCompletion:
            return nil
        case .burnDropped(let trigger, let scope, let elapsed):
            return [
                ParameterNames.trigger: trigger,
                ParameterNames.scope: scope,
                ParameterNames.elapsed: elapsed.rawValue
            ]
        }
    }

    var error: NSError? {
        return nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}

// MARK: - Data Clearing Completion

/// The four pixels reporting that a burn finished, and how long it took.
///
/// Kept separate from `DataClearingPixels` for two reasons, both of which would otherwise change
/// pixels this type does not own:
/// - these four have always sent the `_ios_phone` / `_ios_tablet` marker and `DataClearingPixels`
///   never has, so the two need different `platformSuffixPolicy` values. Merging them would start
///   marking `m_fire_retrigger_in_20s` and `m_fire_user_action_before_completion` too.
/// - `DataClearingPixels` reports `pixelSource`, which these four do not declare in
///   `forget_all.json5`.
enum DataClearingCompletionPixels {

    private enum ParameterNames {
        /// Seconds as a full-precision float string, matching the `durationSeconds` shared parameter
        /// in `params_dictionary.json5`. Do not change the unit or the precision without sign-off
        /// from the pixel owners: dashboards read this verbatim.
        static let duration = "dur"
    }

    case allDataCleared(duration: TimeInterval, tabCount: Int)
    case fireModeDataCleared(duration: TimeInterval, tabCount: Int)
    case normalModeDataCleared(duration: TimeInterval, tabCount: Int)
    case singleTabDataCleared(duration: TimeInterval, tabType: String, browsingMode: String, domainsCount: Int)
}

// MARK: - PixelKit.Event Protocol

extension DataClearingCompletionPixels: PixelKit.Event {
    /// This pixel signature is non-standard and not aligned to the current PixelKit defaults. This policy freezes the signature to a legacy, and incorrect, suffix ordering.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyBeforeFrequencySuffix }

    /// Empty: these names already carry their own `m_` prefix. The conformance exists solely for
    /// `platformSuffix`, which appends the form factor.
    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .allDataCleared:
            return "mf_dc"
        case .fireModeDataCleared:
            return "m_fire-mode_data-cleared"
        case .normalModeDataCleared:
            return "m_normal-mode_data-cleared"
        case .singleTabDataCleared:
            return "m_single-tab-data_cleared"
        }
    }

    /// The duration is part of the event rather than `Options.additionalParameters`, which puts it
    /// inside `uniqueByNameAndParameters` dedup. Harmless while these fire at `.standard`, but a
    /// duration makes every fire unique and would silently defeat that frequency.
    var parameters: [String: String]? {
        switch self {
        case .allDataCleared(let duration, let tabCount),
             .fireModeDataCleared(let duration, let tabCount),
             .normalModeDataCleared(let duration, let tabCount):
            return [
                ParameterNames.duration: String(duration),
                PixelParameters.tabCount: "\(tabCount)"
            ]
        case .singleTabDataCleared(let duration, let tabType, let browsingMode, let domainsCount):
            return [
                ParameterNames.duration: String(duration),
                PixelParameters.tabType: tabType,
                PixelParameters.browsingMode: browsingMode,
                PixelParameters.domainsCount: "\(domainsCount)"
            ]
        }
    }

    /// Deliberately nil: these four do not declare `pixelSource` in `forget_all.json5`.
    var standardParameters: [PixelKitStandardParameter]? {
        return nil
    }

    var error: NSError? {
        return nil
    }
}
