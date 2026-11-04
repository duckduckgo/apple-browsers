//
//  IdleReturnLaunchLanding.swift
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

import Foundation

extension IdleReturnOutcome {

    /// Whether a cold start opens straight on the New Tab Page, instead of showing the restored page and replacing it after launch.
    /// Only for an after-idle New Tab Page return, and only when:
    /// - No launch action opened the app. The action decides where the user lands.
    /// - App Lock is off. With it on, the lock screen hides the restored page anyway, so it's replaced after unlock.
    /// - There's a page to replace. If the restored tab is already a New Tab Page, the normal launch lands there.
    func drawsNewTabPageAtLaunch(isFeatureOn: Bool, hasLaunchAction: Bool, isAppLockEnabled: Bool, hasPageToReplace: Bool) -> Bool {
        guard isFeatureOn, case .afterIdle(.ntp, _) = self else { return false }
        return !hasLaunchAction && !isAppLockEnabled && hasPageToReplace
    }

}

/// Tells the launch handling that the after-idle New Tab Page is already drawn, so it records that page instead of opening one.
/// A class so every foreground shares it: the first to take it records the page, later returns don't.
/// Only this is kept, not the outcome: the page can be drawn long before the user arrives, so the
/// outcome is decided again then.
@MainActor
final class IdleReturnLaunchLanding {

    private var drewNewTabPage: Bool

    init(drewNewTabPage: Bool) {
        self.drewNewTabPage = drewNewTabPage
    }

    /// True for the first caller only, so the arrival is recorded once however many foregrounds try.
    func takeDrawnNewTabPage() -> Bool {
        defer { drewNewTabPage = false }
        return drewNewTabPage
    }

}
