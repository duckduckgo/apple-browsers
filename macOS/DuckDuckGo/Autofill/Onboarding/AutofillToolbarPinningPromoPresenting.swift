//
//  AutofillToolbarPinningPromoPresenting.swift
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

/// How the "Add passwords shortcut?" popover ended.
enum AutofillToolbarPinningPromoOutcome: Equatable {
    /// A CTA was pressed. `pin` is true for "Add Shortcut", false for "No Thanks".
    ///
    /// The presenter reports the choice but does not act on it: `AutofillToolbarPinningPromoDelegate`
    /// performs the pin, so that it cannot race the promo result it is reporting.
    case actioned(pin: Bool)

    /// The popover closed without either CTA being pressed, e.g. a click outside it.
    case dismissed

    /// The popover could not be shown at all, so the user never saw it.
    case notPresented
}

/// Presents the "Add passwords shortcut?" popover on behalf of the promo queue.
///
/// Implemented by `NavigationBarViewController` because presentation depends on state only it owns:
/// it is the popover's `NSPopoverDelegate`, and anchoring un-hides the password button that is
/// otherwise hidden whenever autofill is unpinned — which is always the case when this promo shows.
@MainActor
protocol AutofillToolbarPinningPromoPresenting: AnyObject {
    /// `completion` is called exactly once, whichever way the popover ends.
    func presentAutofillToolbarPinningPromo(completion: @escaping (AutofillToolbarPinningPromoOutcome) -> Void)

    /// Closes the popover without reporting an outcome. Safe to call when nothing is showing.
    func dismissAutofillToolbarPinningPromo()
}
