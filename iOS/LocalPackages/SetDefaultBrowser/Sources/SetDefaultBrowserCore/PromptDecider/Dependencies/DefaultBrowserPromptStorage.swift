//
//  DefaultBrowserPromptStorage.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// A type that provides read-only access to the Set Default Browser (SAD) prompt storage state.
public protocol DefaultBrowserPromptStorage: AnyObject {
    /// The Unix timestamp of when the most recent modal was shown to the user. It returns `nil` if no modal has been shown yet.
    var lastModalShownDate: TimeInterval? { get set }
    /// The total number of SAD modals that have been shown to the user.
    var modalShownOccurrences: Int { get set }
    /// A boolean value indicating whether the user has chosen to permanently dismiss the SAD prompts.
    var isPromptPermanentlyDismissed: Bool { get set }
    /// A boolean value indicating whether the user has seen the inactive modal SAD prompt.
    var hasInactiveModalShown: Bool { get set }
}

public extension DefaultBrowserPromptStorage {

    /// A boolean value Indicating whether the user has seen at least the first modal.
    var hasSeenFirstModal: Bool {
        modalShownOccurrences >= 1
    }

    /// A boolean value Indicating whether the user has seen at least the second modal.
    var hasSeenSecondModal: Bool {
        modalShownOccurrences >= 2
    }

}
