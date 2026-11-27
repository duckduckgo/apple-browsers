//
//  IdleReturnOutcome+DrawAtLaunch.swift
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

    /// Whether a warm return puts up the New Tab Page before its first frame, instead of showing the previous page first.
    /// Only for an after-idle New Tab Page return, and only when:
    /// - No launch action is waiting. A link arrives before the draw, so it opens as it would without it.
    /// - No tab clearing is configured or running. It replaces the tabs, so there's nothing to land on yet.
    /// - No Duck.ai voice session is active. The return must not leave it.
    /// - Nothing is presented. A screen can't be closed before the app is active, and hiding it doesn't undo
    ///   what its presentation did to the page behind it, so those returns keep closing it first.
    /// - There's a page to replace. If the current tab is already a New Tab Page, it's kept.
    func drawsNewTabPageOnForeground(isFeatureOn: Bool, hasLaunchAction: Bool, isClearingTabs: Bool,
                                     isVoiceSessionActive: Bool, hasPageToReplace: Bool, isScreenPresented: Bool) -> Bool {
        guard isFeatureOn, case .afterIdle(.ntp, _) = self else { return false }
        return !hasLaunchAction && !isClearingTabs && !isVoiceSessionActive && !isScreenPresented && hasPageToReplace
    }

}
