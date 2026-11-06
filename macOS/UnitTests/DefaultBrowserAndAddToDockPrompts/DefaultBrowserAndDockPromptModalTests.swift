//
//  DefaultBrowserAndDockPromptModalTests.swift
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
import SharedTestUtilities
import SwiftUI
import Utilities
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DefaultBrowserAndDockPromptModalTests: XCTestCase {

    private func makeModal(onConfirm: @escaping () -> Void = {},
                           onDismiss: @escaping () -> Void = {}) -> DefaultBrowserAndDockPromptModal {
        DefaultBrowserAndDockPromptModal(type: .setAsDefaultPrompt,
                                         uiProvider: MockDefaultBrowserAndDockPromptUIProvider(),
                                         accessibilityIdentifier: "test.identifier",
                                         onConfirm: onConfirm,
                                         onDismiss: onDismiss)
    }

    private func viewModel(of modal: DefaultBrowserAndDockPromptModal) -> DefaultBrowserAndDockPromptInactiveUserViewModel? {
        (modal.window.contentViewController as? NSHostingController<DefaultBrowserAndDockPromptInactiveUserView>)?.rootView.viewModel
    }

    func testWhenPrimaryActionInvokedThenOnConfirmCalled() throws {
        var confirmCount = 0
        var dismissCount = 0
        let modal = makeModal(onConfirm: { confirmCount += 1 }, onDismiss: { dismissCount += 1 })

        try XCTUnwrap(viewModel(of: modal)).primaryButtonAction()

        XCTAssertEqual(confirmCount, 1)
        XCTAssertEqual(dismissCount, 0)
    }

    func testWhenDismissActionInvokedThenOnDismissCalled() throws {
        var confirmCount = 0
        var dismissCount = 0
        let modal = makeModal(onConfirm: { confirmCount += 1 }, onDismiss: { dismissCount += 1 })

        try XCTUnwrap(viewModel(of: modal)).dismissButtonAction()

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(confirmCount, 0)
    }

    func testWhenDismissedWithoutBeingPresentedThenNothingHappens() async {
        let modal = makeModal()

        await modal.dismiss()

        XCTAssertNil(modal.window.sheetParent)
    }

    func testWhenDismissedTwiceThenSecondCallIsHarmless() async {
        let parent = MockWindow()
        let modal = makeModal()
        modal.present(over: parent)

        await modal.dismiss()
        await modal.dismiss()

        XCTAssertTrue(parent.beginSheetCalled)
        XCTAssertNil(modal.window.sheetParent)
    }
}
