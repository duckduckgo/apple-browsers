//
//  NextStepsItemsVisibility.swift
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


import Persistence
import UIKit

/// Which of the "finish setting up" items still apply, read from the state Settings stores when the user acts on them.
struct NextStepsItemsVisibility {

    typealias Constants = SettingsViewModel.Constants

    private let keyValueStore: ThrowingKeyValueStoring
    private let now: () -> TimeInterval

    init(keyValueStore: ThrowingKeyValueStoring, now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.keyValueStore = keyValueStore
        self.now = now
    }

    var isSetAsDefaultVisible: Bool {
        !flag(Constants.didDismissSetAsDefaultBrowserKey)
    }

    /// Settles a pending default-browser check first, so the answer reflects a Set as Default the user has since completed.
    func isSetAsDefaultVisibleAfterCheck() -> Bool {
        if #available(iOS 18.2, *) {
            dismissSetAsDefaultIfAlreadyDefault()
        }
        return isSetAsDefaultVisible
    }

    var isAddToDockVisible: Bool {
        isNextStepVisible(tappedAtKey: Constants.didTapAddToDockNextStepKey)
    }

    var isAddWidgetVisible: Bool {
        isNextStepVisible(tappedAtKey: Constants.didTapAddWidgetNextStepKey)
    }

    var isNextStepsSectionHidden: Bool {
        flag(Constants.nextStepsSectionHiddenKey)
    }

    func recordSetAsDefaultTapped() {
        guard isSetAsDefaultVisible else { return }
        try? keyValueStore.set(true, forKey: Constants.shouldCheckIfDefaultBrowserKey)
    }

    func recordAddToDockTapped() {
        SettingsViewModel.recordFirstTap(forKey: Constants.didTapAddToDockNextStepKey, in: keyValueStore, now: now())
    }

    func recordAddWidgetTapped() {
        SettingsViewModel.recordFirstTap(forKey: Constants.didTapAddWidgetNextStepKey, in: keyValueStore, now: now())
    }

    /// Checks once, after the user has tapped Set as Default, whether it worked. The system limits how often it can be asked.
    @available(iOS 18.2, *)
    func dismissSetAsDefaultIfAlreadyDefault() {
        guard flag(Constants.shouldCheckIfDefaultBrowserKey) else { return }
        do {
            if try UIApplication.shared.isDefault(.webBrowser) {
                try? keyValueStore.set(true, forKey: Constants.didDismissSetAsDefaultBrowserKey)
            }
        } catch {
            try? keyValueStore.set(true, forKey: Constants.didDismissSetAsDefaultBrowserKey)
        }
        try? keyValueStore.set(false, forKey: Constants.shouldCheckIfDefaultBrowserKey)
    }

    private func isNextStepVisible(tappedAtKey: String) -> Bool {
        guard !isNextStepsSectionHidden else { return false }
        let tappedAt = try? keyValueStore.object(forKey: tappedAtKey) as? Double
        return !SettingsViewModel.hasTapDismissalElapsed(tappedAt: tappedAt, now: now(), interval: Constants.nextStepTapDismissalInterval)
    }

    private func flag(_ key: String) -> Bool {
        (try? keyValueStore.object(forKey: key) as? Bool) ?? false
    }

}
