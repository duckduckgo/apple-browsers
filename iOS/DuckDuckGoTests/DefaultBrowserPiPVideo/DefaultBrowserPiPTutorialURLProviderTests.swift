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
import Core
import SystemSettingsPiPTutorial
@testable import DuckDuckGo

@Suite("System Settings PiP Tutorial - Default Browser", .serialized)
final class DefaultBrowserPiPTutorialURLProviderTests {

    struct Context {
        let featureFlags: [FeatureFlag]
        let videoName: String

        static let `default` = Context(featureFlags: [], videoName: "default-browser-tutorial")
        static let appRebranding = Context(featureFlags: [FeatureFlag.appRebranding], videoName: "default-browser-tutorial-rebranded")
    }

    @Test(
        "Check Video Can Be Loaded From the Bundle",
        arguments: [Context.default, Context.appRebranding]
    )
    func whenVideoIsFoundInBundleThenReturnVideoURL(context: Context) throws {
        // GIVEN
        let featureFlaggerMock = MockFeatureFlagger(enabledFeatureFlags: context.featureFlags)
        let sut = DefaultBrowserPiPTutorialURLProvider(featureFlagger: featureFlaggerMock)

        // WHEN
        let result = try sut.pipTutorialURL()

        // THEN
        #expect(result.absoluteString.contains("\(context.videoName).mp4"))
    }

    @Test("Check Throw Error When Video Cannot Be Loaded From the Bundle")
    func whenVideoIsNotFoundInBundleThenReturnURLNotFoundError() {
        // GIVEN
        let featureFlaggerMock = MockFeatureFlagger()
        let fakeBundle = Bundle(for: DefaultBrowserPiPTutorialURLProviderTests.self)
        let sut = DefaultBrowserPiPTutorialURLProvider(featureFlagger: featureFlaggerMock, bundle: fakeBundle)

        // WHEN & THEN
        #expect(throws: PiPTutorialURLProviderError.urlNotFound) {
            try sut.pipTutorialURL()
        }
    }

    @Test(
        "Check Video URLs Are Returned For Supported Localizations",
        arguments: [
            "de",
            "es",
            "fr",
            "it",
            "nl",
            "pt"
        ],
        [
            Context.default,
            Context.appRebranding
        ]
    )
    func checkVideosAreFoundForSupportedLocalizations(_ localization: String, context: Context) throws {
        // GIVEN
        let featureFlaggerMock = MockFeatureFlagger(enabledFeatureFlags: context.featureFlags)
        let localizedBundlePath = try #require(Bundle.main.path(forResource: localization, ofType: "lproj"))
        let localizedBundle = try #require(Bundle(path: localizedBundlePath))
        let sut = DefaultBrowserPiPTutorialURLProvider(featureFlagger: featureFlaggerMock, bundle: localizedBundle)

        // WHEN
        let result = try sut.pipTutorialURL()

        // THEN
        #expect(result.absoluteString.contains("\(localization).lproj/\(context.videoName).mp4"))
    }

}
