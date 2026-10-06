//
//  CreateImagePixelAdapterTests.swift
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

@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class CreateImagePixelAdapterTests: XCTestCase {

    private var pixelKitMock: PixelKitMock!
    private var surface: UnifiedToggleInputPixelSurface = .duckAI
    private var sut: CreateImagePixelAdapter!

    private let switchFromPrivateModel = CreateImageModelSwitch(
        fromModelId: "gpt-oss-120b",
        toModelId: "gemini-2-5-flash",
        fromModelHasExtraPrivacyProtections: true,
        entryPoint: .toolsMenu
    )

    override func setUp() {
        super.setUp()
        pixelKitMock = PixelKitMock()
        surface = .duckAI
        sut = CreateImagePixelAdapter(firing: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
                                      surface: { [unowned self] in surface })
    }

    override func tearDown() {
        sut = nil
        pixelKitMock = nil
        super.tearDown()
    }

    // MARK: - Model switched

    func testWhenTheModelIsSwitchedThenItReportsBothModelsTheEntryPointAndThePrivacyFlag() {
        sut.modelSwitched(switchFromPrivateModel)

        XCTAssertEqual(firedNames, ["aichat_unified_input_create_image_model_switched"])
        XCTAssertEqual(lastParameters, [
            "surface": "duck_ai",
            "from_model_id": "gpt-oss-120b",
            "to_model_id": "gemini-2-5-flash",
            "from_model_privacy_preserving": "true",
            "entry_point": "tools_menu"
        ])
    }

    func testWhenTheModelSwitchedFromIsNotPrivacyPreservingThenTheFlagIsReportedAsFalse() {
        sut.modelSwitched(CreateImageModelSwitch(fromModelId: "mistral-small-3",
                                                 toModelId: "gemini-2-5-flash",
                                                 fromModelHasExtraPrivacyProtections: false,
                                                 entryPoint: .chatHeaderNewImage))

        XCTAssertEqual(lastParameters?["from_model_privacy_preserving"], "false")
    }

    func testWhenTheSwitchStartsInTheChatHeaderThenTheEntryPointSaysSo() {
        sut.modelSwitched(CreateImageModelSwitch(fromModelId: "mistral-small-3",
                                                 toModelId: "gemini-2-5-flash",
                                                 fromModelHasExtraPrivacyProtections: false,
                                                 entryPoint: .chatHeaderNewImage))

        XCTAssertEqual(lastParameters?["entry_point"], "chat_header_new_image")
    }

    func testWhenTheModelIsSwitchedThenItIsSentAsADailyAndCountPixel() {
        sut.modelSwitched(switchFromPrivateModel)

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.frequency, .dailyAndCount)
    }

    // MARK: - Notice dismissed

    func testWhenTheSwitchNoticeIsDismissedThenItIsReportedAsADailyAndCountPixelWithoutParameters() {
        sut.modelSwitchNoticeDismissed()

        XCTAssertEqual(firedNames, ["aichat_unified_input_create_image_model_switch_notice_dismissed"])
        XCTAssertNil(lastParameters)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.frequency, .dailyAndCount)
    }

    // MARK: - Unavailable

    func testWhenCreateImageIsUnavailableThenItIsReportedAsADailyPixelWithoutParameters() {
        sut.createImageUnavailable()

        XCTAssertEqual(firedNames, ["aichat_unified_input_create_image_unavailable"])
        XCTAssertNil(lastParameters)
        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.frequency, .daily)
    }

    // MARK: - Surface

    func testWhenTheSurfaceChangesThenTheNextPixelReportsTheNewSurface() {
        sut.modelSwitched(switchFromPrivateModel)
        surface = .contextualChat

        sut.modelSwitched(switchFromPrivateModel)

        XCTAssertEqual(lastParameters?["surface"], "contextual_chat")
    }

    // MARK: - Helpers

    private var firedNames: [String] {
        pixelKitMock.actualFireCalls.map(\.pixel.name)
    }

    private var lastParameters: [String: String]? {
        pixelKitMock.actualFireCalls.last?.pixel.parameters
    }
}
