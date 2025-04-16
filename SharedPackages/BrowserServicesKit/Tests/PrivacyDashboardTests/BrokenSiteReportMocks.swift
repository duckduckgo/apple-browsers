//
//  BrokenSiteReportMocks.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PrivacyDashboard

struct BrokenSiteReportMocks {

    static var report: BrokenSiteReport {
#if os(iOS)
        BrokenSiteReport(siteUrl: URL(string: "https://duckduckgo.com")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: .appMenu,
                         siteType: .desktop,
                         atb: "test",
                         model: "test",
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         variant: "",
                         cookieConsentInfo: nil,
                         debugFlags: "",
                         privacyExperiments: [:])
#else
        BrokenSiteReport(siteUrl: URL(string: "https://duckduckgo.com")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: .appMenu,
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         cookieConsentInfo: nil,
                         debugFlags: "",
                         privacyExperiments: [:])
#endif
    }

    static var report2: BrokenSiteReport {
#if os(iOS)
        BrokenSiteReport(siteUrl: URL(string: "https://somethingelse.zz")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: .appMenu,
                         siteType: .desktop,
                         atb: "test",
                         model: "test",
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         variant: "",
                         cookieConsentInfo: nil,
                         debugFlags: "",
                         privacyExperiments: [:])
#else
        BrokenSiteReport(siteUrl: URL(string: "https://somethingelse.zz")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: .appMenu,
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         cookieConsentInfo: nil,
                         debugFlags: "",
                         privacyExperiments: [:])
#endif
    }

    static var report3: BrokenSiteReport {
#if os(iOS)
        BrokenSiteReport(siteUrl: URL(string: "https://www.subdomain.example.com/some/pathname?t=param#aaa")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: .appMenu,
                         siteType: .desktop,
                         atb: "test",
                         model: "test",
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         variant: "",
                         cookieConsentInfo: nil,
                         debugFlags: "",
                         privacyExperiments: [:])
#else
        BrokenSiteReport(siteUrl: URL(string: "https://www.subdomain.example.com/some/pathname?t=param#aaa")!,
                         category: "test",
                         description: "test",
                         osVersion: "test",
                         manufacturer: "Apple",
                         upgradedHttps: true,
                         tdsETag: "test",
                         configVersion: "123456789",
                         blockedTrackerDomains: [],
                         installedSurrogates: [],
                         isGPCEnabled: true,
                         ampURL: "test",
                         urlParametersRemoved: true,
                         protectionsState: true,
                         reportFlow: .appMenu,
                         errors: nil,
                         httpStatusCodes: nil,
                         openerContext: nil,
                         vpnOn: false,
                         jsPerformance: nil,
                         userRefreshCount: 0,
                         cookieConsentInfo: nil,
                         debugFlags: "",
                         privacyExperiments: [:])
#endif
    }
}
