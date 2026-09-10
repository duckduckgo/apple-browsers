//
//  AIChatContextualInputViewControllerTests.swift
//  DuckDuckGoTests
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatContextualInputViewControllerTests: XCTestCase {

    func testImmediateUTIPrivacyLabelDoesNotOverlapQuickActionsInCompressedHeight() {
        let sut = AIChatContextualInputViewController(
            voiceSearchHelper: MockVoiceSearchHelper(),
            showsBasicNativeInput: false
        )
        sut.loadViewIfNeeded()
        sut.updateStartActions(suggestions: [], quickActions: [.askAboutPage])
        sut.view.frame = CGRect(x: 0, y: 0, width: 390, height: 180)

        sut.view.setNeedsLayout()
        sut.view.layoutIfNeeded()

        let welcomeLabel = findSubview(in: sut.view) { view in
            (view as? UILabel)?.attributedText?.string.contains("private") == true
        } as? UILabel
        let quickActionsScrollView = findSubview(in: sut.view) { view in
            view is UIScrollView
        }

        XCTAssertNotNil(welcomeLabel)
        XCTAssertNotNil(quickActionsScrollView)
        if let welcomeLabel, let quickActionsScrollView {
            XCTAssertLessThanOrEqual(welcomeLabel.frame.maxY, quickActionsScrollView.frame.minY)
        }
    }

    private func findSubview(in view: UIView, matching predicate: (UIView) -> Bool) -> UIView? {
        if predicate(view) {
            return view
        }
        for subview in view.subviews {
            if let match = findSubview(in: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }
}
