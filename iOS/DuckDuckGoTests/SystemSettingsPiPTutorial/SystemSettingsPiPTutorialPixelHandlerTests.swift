//
//  SystemSettingsPiPTutorialPixelHandlerTests.swift
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
import Core
import Testing
@testable import DuckDuckGo

@Suite("System Settings PiP Tutorial - Pixel Handler Tests")
final class SystemSettingsPiPTutorialPixelHandlerTests {
    private let pixelFiringMock: PixelFiringMock.Type

    init() {
        pixelFiringMock = PixelFiringMock.self
    }

    deinit {
        pixelFiringMock.tearDown()
    }

    @Test(
        "Check parameter is extracted properly from URL",
        arguments: zip(
            [
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/en.lproj/default-browser-tutorial.mp4",
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/de.lproj/default-browser-tutorial.mp4",
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/es.lproj/default-browser-tutorial.mp4",
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/fr.lproj/default-browser-tutorial.mp4",
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/it.lproj/default-browser-tutorial.mp4",
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/nl.lproj/default-browser-tutorial.mp4",
                "file:///private/var/containers/Bundle/Application/6CB3B838-5751-46A8-A148-C5A6C2F85C71/DuckDuckGo.app/pt.lproj/default-browser-tutorial.mp4",
            ],
            [
                "en.lproj/default-browser-tutorial.mp4",
                "de.lproj/default-browser-tutorial.mp4",
                "es.lproj/default-browser-tutorial.mp4",
                "fr.lproj/default-browser-tutorial.mp4",
                "it.lproj/default-browser-tutorial.mp4",
                "nl.lproj/default-browser-tutorial.mp4",
                "pt.lproj/default-browser-tutorial.mp4",
            ]
        )
    )
    func whenURLPathIsNotNilThenParametersIsSetCorrectly(urlPath: String, expectedResult: String) async throws {
        // GIVEN
        let error = NSError(domain: #function, code: 0)
        let sut = SystemSettingsPiPTutorialPixelHandler(dailyPixelFiring: pixelFiringMock)

        // WHEN
        sut.fireFailedToLoadPiPTutorialEvent(error: error, urlPath: urlPath)

        // THEN
        #expect(pixelFiringMock.lastDailyPixelInfo?.pixelName == Pixel.Event.systemSettingsPiPTutorialFailedToLoadVideo.name)
        #expect(pixelFiringMock.lastDailyPixelInfo?.params == ["video_url_path": expectedResult])
        #expect(pixelFiringMock.lastDailyPixelInfo?.error as? NSError == error)
    }

    @Test("Check parameter is extracted properly from URL ")
    func whenURLPathIsNilThenParametersIsNotSet() async throws {
        // GIVEN
        let error = NSError(domain: #function, code: 0)
        let sut = SystemSettingsPiPTutorialPixelHandler(dailyPixelFiring: pixelFiringMock)

        // WHEN
        sut.fireFailedToLoadPiPTutorialEvent(error: error, urlPath: nil)

        // THEN
        #expect(pixelFiringMock.lastDailyPixelInfo?.pixelName == Pixel.Event.systemSettingsPiPTutorialFailedToLoadVideo.name)
        #expect(pixelFiringMock.lastDailyPixelInfo?.params == [:])
        #expect(pixelFiringMock.lastDailyPixelInfo?.error as? NSError == error)
    }

}
