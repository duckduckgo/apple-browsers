//
//  File.swift
//  BrowserServicesKit
//
//  Created by Sabrina Tardio on 27/02/25.
//

import Foundation
import MaliciousSiteProtection

final class MockMaliciousSiteProtectionFeatureFlags: MaliciousSiteProtectionFeatureFlagger, MaliciousSiteProtectionFeatureFlagsSettingsProvider {

    var isScamProtectionEnabled = false

    var shouldDetectMaliciousThreatForDomainResult = false

    var isMaliciousSiteProtectionEnabled = false

    var hashPrefixUpdateFrequency: Int = 10

    var filterSetUpdateFrequency: Int = 20

    func shouldDetectMaliciousThreat(forDomain domain: String?) -> Bool {
        shouldDetectMaliciousThreatForDomainResult
    }
}
