//
//  SystemSettingsPiPTutorialURLProviderTests.swift
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

import Testing
import Foundation
import class UIKit.UIApplication
import SystemSettingsPiPTutorialTestSupport
@testable import SystemSettingsPiPTutorial

@MainActor
@Suite("System Settings PiP Tutorial - URL Provider Tests")
struct SystemSettingsPiPTutorialURLProviderTests {

    @Test("Check Registering Provider For Destination Succeeds")
    func checkRegisteringProviderForDestinationSucceeds() throws {
        // GIVEN
        let sut = SystemSettingsPiPTutorialURLProvider()
        let provider = MockPiPTutorialURLProvider()
        let destination = SystemSettingsPiPTutorialDestination.mock
        #expect(sut.providers.isEmpty)

        // WHEN
        sut.register(provider, for: destination)

        // THEN
        #expect(sut.providers.count == 1)
    }

    @Test("Check Registering Same Provider For Destination Register Only One Provider")
    func checkRegisteringProviderForSameDestinationRegisterOnlyOnce() throws {
        // GIVEN
        let sut = SystemSettingsPiPTutorialURLProvider()
        let provider = MockPiPTutorialURLProvider()
        let destination = SystemSettingsPiPTutorialDestination.mock
        #expect(sut.providers.isEmpty)

        // WHEN
        sut.register(provider, for: destination)
        sut.register(provider, for: destination)
        sut.register(provider, for: destination)
        sut.register(provider, for: destination)
        sut.register(provider, for: destination)

        // THEN
        #expect(sut.providers.count == 1)
    }

    @Test("Check Retrieving Registered Provider For Destination Succeeds")
    func checkRetrievingURLForRegisteredProviderReturnsExpectedURL() throws {
        // GIVEN
        let sut = SystemSettingsPiPTutorialURLProvider()
        let videoURL = try #require(URL(string: "https://example.com/video.mp4"))
        let provider = MockPiPTutorialURLProvider()
        provider.result = .success(videoURL)
        let destination = SystemSettingsPiPTutorialDestination.mock
        sut.register(provider, for: destination)

        // WHEN
        let result = try sut.url(for: destination)

        // THEN
        #expect(result == videoURL)
    }

    @Test("Check Retrieving Unregistered Provider For Destination Throws An Error")
    func checkRetrievingURLForUnregisteredProviderThrowsNoProviderError() throws {
        // GIVEN
        let sut = SystemSettingsPiPTutorialURLProvider()
        let videoURL = try #require(URL(string: "https://example.com/video.mp4"))
        let provider = MockPiPTutorialURLProvider()
        provider.result = .success(videoURL)
        let destination = SystemSettingsPiPTutorialDestination.mock

        // THEN
        #expect(throws: SystemSettingsPiPTutorialURLProviderError.noProviderAvailable(destination: destination)) {
            // WHEN
            try sut.url(for: destination)
        }
    }

    @Test("Check Retrieving Unregistered Provider For Destination Throws An Error")
    func checkProviderFailingToResolveURLThrowsUrlNotFoundError() throws {
        // GIVEN
        let sut = SystemSettingsPiPTutorialURLProvider()
        let provider = MockPiPTutorialURLProvider()
        provider.result = .failure(.urlNotFound)
        let destination = SystemSettingsPiPTutorialDestination.mock
        sut.register(provider, for: destination)

        // THEN
        #expect(throws: SystemSettingsPiPTutorialURLProviderError.providerError(.urlNotFound)) {
            // WHEN
            try sut.url(for: destination)
        }
    }

}
