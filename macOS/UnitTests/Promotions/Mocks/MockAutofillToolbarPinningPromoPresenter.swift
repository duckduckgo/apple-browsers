//
//  MockAutofillToolbarPinningPromoPresenter.swift
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

import Foundation
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class MockAutofillToolbarPinningPromoPresenter: AutofillToolbarPinningPromoPresenting {

    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0
    private var completion: ((AutofillToolbarPinningPromoOutcome) -> Void)?

    func presentAutofillToolbarPinningPromo(completion: @escaping (AutofillToolbarPinningPromoOutcome) -> Void) {
        presentCallCount += 1
        self.completion = completion
    }

    func dismissAutofillToolbarPinningPromo() {
        dismissCallCount += 1
        completion = nil
    }

    /// Drives the outcome the delegate is awaiting, standing in for a CTA press or an outside click.
    func complete(with outcome: AutofillToolbarPinningPromoOutcome) {
        let completion = self.completion
        self.completion = nil
        completion?(outcome)
    }

    /// Stands in for `NavigationBarViewController` tearing down while the popover is up — the window
    /// closing, or the view controller deallocating. Its `viewWillDisappear`/`deinit` backstops report
    /// `.notPresented` so the promo queue is never left awaiting a result.
    func simulateTeardown() {
        complete(with: .notPresented)
    }
}
