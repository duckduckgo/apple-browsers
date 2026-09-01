//
//  PromoServiceFactory+AutofillToolbarPinning.swift
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

extension PromoServiceFactory {

    /// Builds the Autofill Toolbar Pinning Promo (migrated from the standalone "Add passwords shortcut?" popover).
    @MainActor
    static func autofillToolbarPinning(dependencies: PromoDependencies) -> Promo {
        let windowControllersManager = dependencies.windowControllersManager
        let delegate = AutofillToolbarPinningPromoDelegate(
            featureFlagger: dependencies.featureFlagger,
            pinningManager: dependencies.pinningManager,
            presenterProvider: {
                windowControllersManager.lastKeyMainWindowController?
                    .mainViewController
                    .navigationBarViewController
            })

        // Same treatment as the Default Browser popover: an in-app popover that stays up until the user acts.
        return InternalPromo(id: "autofill-toolbar-pinning",
                             triggers: [.firstPasswordSaved],
                             initiated: .user,
                             promoType: PromoType(.semiModal),
                             context: .global,
                             delegate: delegate)
    }
}
