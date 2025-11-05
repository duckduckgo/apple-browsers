//
//  SpecialErrorPageLocalization.swift
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

import XCTest
import Foundation

struct SpecialErrorPageLocalization: Decodable {
    struct LocalizationItem: Decodable {
        let title: String
    }

    let advancedEllipsisButton: LocalizationItem
    let leaveSiteButton: LocalizationItem
    let visitSiteButton: LocalizationItem
    let malwarePageHeading: LocalizationItem
    let phishingPageHeading: LocalizationItem
    let phishingWarningText: LocalizationItem
    let scamPageHeading: LocalizationItem
    let scamWarningText: LocalizationItem

    static func load(for app: XCUIApplication) throws -> SpecialErrorPageLocalization {
        let appPath = try XCTUnwrap(app.path)
        let appBundle = try XCTUnwrap(Bundle(path: appPath))
        let cssBundlePath = try XCTUnwrap(appBundle.path(forResource: "BrowserServicesKit_ContentScopeScripts", ofType: "bundle"))
        let cssBundle = try XCTUnwrap(Bundle(path: cssBundlePath))
        let specialErrorPageLocalizationPath = try XCTUnwrap(cssBundle.path(forResource: "pages/special-error/locales/en/special-error", ofType: "json"))
        let data = try Data(contentsOf: URL(fileURLWithPath: specialErrorPageLocalizationPath))
        let decoder = JSONDecoder()
        Logger.log("Loading special error page localization from \(specialErrorPageLocalizationPath)")
        return try decoder.decode(SpecialErrorPageLocalization.self, from: data)
    }
}
