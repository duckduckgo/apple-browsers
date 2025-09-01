//
//  DefaultBrowserPiPTutorialURLProviderTests.swift
//  DuckDuckGo
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
import Testing
import SystemSettingsPiPTutorial
@testable import DuckDuckGo

@Suite("System Settings PiP Tutorial - Default Browser", .serialized)
final class DefaultBrowserPiPTutorialURLProviderTests {

    @Test("Check Video Can Be Loaded From the Bundle")
    func whenVideoIsFoundInBundleThenReturnVideoURL() throws {
        // GIVEN
        let sut = DefaultBrowserPiPTutorialURLProvider()

        // WHEN
        let result = try sut.pipTutorialURL()

        // THEN
        #expect(result.absoluteString.contains("default-browser-tutorial.mp4"))
    }

    @Test("Check Throw Error When Video Cannot Be Loaded From the Bundle")
    func whenVideoIsNotFoundInBundleThenReturnURLNotFoundError() {
        // GIVEN
        let fakeBundle = Bundle(for: DefaultBrowserPiPTutorialURLProviderTests.self)
        let sut = DefaultBrowserPiPTutorialURLProvider(bundle: fakeBundle)

        // WHEN & THEN
        #expect(throws: PiPTutorialURLProviderError.urlNotFound) {
            try sut.pipTutorialURL()
        }
    }

    @Test(
        "Check Video URLs Are Returned For Supported Localizations",
        arguments: [
            "en",
            "de",
            "es",
            "fr",
            "it",
            "nl",
            "pt"
        ]
    )
    func checkVideosAreFoundForSupportedLocalizations(_ localization: String) throws {
        // GIVEN
        let localizedBundlePath = try #require(Bundle.main.path(forResource: localization, ofType: "lproj"))
        let localizedBundle = try #require(Bundle(path: localizedBundlePath))
        let sut = DefaultBrowserPiPTutorialURLProvider(bundle: localizedBundle)

        // WHEN
        let result = try sut.pipTutorialURL()

        // THEN
        #expect(result.absoluteString.contains("\(localization).lproj/default-browser-tutorial.mp4"))
    }

}
