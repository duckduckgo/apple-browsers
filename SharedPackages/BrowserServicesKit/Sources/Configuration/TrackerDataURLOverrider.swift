//
//  TrackerDataURLOverrider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import os.log

public protocol TrackerDataURLProviding {
    var trackerDataURL: URL? { get }
}

public final class TrackerDataURLOverrider: TrackerDataURLProviding {

    var privacyConfigurationManager: PrivacyConfigurationManaging
    var featureFlagger: FeatureFlagger

    public enum Constants {
        public static let baseTDSURLString = "https://staticcdn.duckduckgo.com/trackerblocking/"
    }

    public init (privacyConfigurationManager: PrivacyConfigurationManaging,
                 featureFlagger: FeatureFlagger) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.featureFlagger = featureFlagger
    }

    public var trackerDataURL: URL? {
        for experimentType in TDSExperimentType.allCases {
            if let cohort = featureFlagger.resolveCohort(for: experimentType, allowOverride: false) as? TDSExperimentType.Cohort,
               let url = trackerDataURL(for: experimentType.subfeature, cohort: cohort) {
                return url
            }
        }
        return nil
    }

    private func trackerDataURL(for subfeature: any PrivacySubfeature, cohort: TDSExperimentType.Cohort) -> URL? {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: subfeature),
              let jsonData = settings.data(using: .utf8) else { return nil }
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let urlString = cohort == .control ? settingsDict["controlUrl"] : settingsDict["treatmentUrl"] {
                return URL(string: Constants.baseTDSURLString + urlString)
            }
        } catch {
            Logger.config.info("privacyConfiguration: Failed to parse subfeature settings JSON: \(error)")
        }
        return nil
    }
}

public enum TDSExperimentType: String, CaseIterable {
    case baseline
    case feb25
    case mar25
    case apr25
    case may25
    case jun25
    case jul25
    case aug25
    case sep25
    case oct25
    case nov25
    case dec25

    public var subfeature: any PrivacySubfeature {
        switch self {
        case .baseline:
            ContentBlockingSubfeature.tdsNextExperimentBaseline
        case .feb25:
            ContentBlockingSubfeature.tdsNextExperimentFeb25
        case .mar25:
            ContentBlockingSubfeature.tdsNextExperimentMar25
        case .apr25:
            ContentBlockingSubfeature.tdsNextExperimentApr25
        case .may25:
            ContentBlockingSubfeature.tdsNextExperimentMay25
        case .jun25:
            ContentBlockingSubfeature.tdsNextExperimentJun25
        case .jul25:
            ContentBlockingSubfeature.tdsNextExperimentJul25
        case .aug25:
            ContentBlockingSubfeature.tdsNextExperimentAug25
        case .sep25:
            ContentBlockingSubfeature.tdsNextExperimentSep25
        case .oct25:
            ContentBlockingSubfeature.tdsNextExperimentOct25
        case .nov25:
            ContentBlockingSubfeature.tdsNextExperimentNov25
        case .dec25:
            ContentBlockingSubfeature.tdsNextExperimentDec25
        }
    }
}

extension TDSExperimentType: FeatureFlagDescribing {
    public var defaultValue: Bool {
        return false
    }

    public var supportsLocalOverriding: Bool {
        return false
    }

    public var source: FeatureFlagSource {
        return .remoteReleasable(.subfeature(self.subfeature))
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        return Cohort.self
    }

    public enum Cohort: String, FeatureFlagCohortDescribing {
        case control
        case treatment
    }
}
