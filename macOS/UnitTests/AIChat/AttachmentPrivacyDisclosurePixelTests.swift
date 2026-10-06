//
//  AttachmentPrivacyDisclosurePixelTests.swift
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

import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// The names are a contract with the pixel definitions, and what was attached is part of them.
final class AttachmentPrivacyDisclosurePixelTests: XCTestCase {

    private var pixelFiring: CapturingAttachmentPrivacyPixelFiring!

    override func setUp() {
        super.setUp()
        pixelFiring = CapturingAttachmentPrivacyPixelFiring()
    }

    override func tearDown() {
        pixelFiring = nil
        super.tearDown()
    }

    /// The tail of each name matches iOS's, so the two platforms' series can be read together.
    func testEveryActionIsSplitByWhatWasAttached() {
        let firer = makeFirer(surface: .addressBar)

        firer.fireShown(kind: .image)
        firer.fireShown(kind: .file)
        firer.fireLearnMoreTapped(kind: .image)
        firer.fireLearnMoreTapped(kind: .file)

        XCTAssertEqual(pixelFiring.firedPixels.map(\.name), [
            "aichat_attachment_privacy_image_shown",
            "aichat_attachment_privacy_file_shown",
            "aichat_attachment_privacy_image_learn_more_tapped",
            "aichat_attachment_privacy_file_learn_more_tapped"
        ])
    }

    func testTheSurfaceIsReported() {
        makeFirer(surface: .promptBar).fireShown(kind: .file)
        makeFirer(surface: .newTabPage).fireLearnMoreTapped(kind: .file)

        XCTAssertEqual(pixelFiring.firedPixels.compactMap { $0.parameters?["surface"] }, ["prompt_bar", "new_tab_page"])
    }

    func testEveryPixelIsDailyAndCount() {
        makeFirer(surface: .addressBar).fireShown(kind: .image)

        XCTAssertEqual(pixelFiring.firedFrequencies, [.dailyAndCount])
    }

    private func makeFirer(surface: AttachmentPrivacyDisclosurePixelSurface) -> AttachmentPrivacyDisclosurePixelFirer {
        AttachmentPrivacyDisclosurePixelFirer(surface: surface, pixelFiring: pixelFiring)
    }
}

private final class CapturingAttachmentPrivacyPixelFiring: PixelFiring {

    private(set) var firedPixels: [PixelKit.Event] = []
    private(set) var firedFrequencies: [PixelKit.Frequency] = []

    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock) {
        firedPixels.append(event)
        firedFrequencies.append(frequency)
        onComplete(true, nil)
    }
}
