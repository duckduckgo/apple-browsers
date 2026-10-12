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

    /// A cold start lands on the New Tab Page directly, rather than replacing the restored page after authentication.
    /// - App Lock: nothing covers the window before authentication on a cold launch.
    /// - No page to replace: the restored state already lands on a New Tab Page, including when tabs are cleared on launch.
    func drawsNewTabPageAtLaunch(isAppLockEnabled: Bool, hasPageToReplace: Bool) -> Bool {
        guard case .afterIdle(.ntp, _) = self else { return false }
        return !isAppLockEnabled && hasPageToReplace
    }

}
