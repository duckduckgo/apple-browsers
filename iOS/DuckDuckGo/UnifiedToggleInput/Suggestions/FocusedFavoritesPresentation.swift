//
//  FocusedFavoritesPresentation.swift
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

/// Owns the existing focused favorites controller independently of the suggestions layout.
/// The content resolver supplies visibility; this component does not change eligibility or actions.
@MainActor
final class FocusedFavoritesPresentation {

    private let makeViewController: () -> NewTabPageViewController?
    private var cachedViewController: NewTabPageViewController?

    init(makeViewController: @escaping () -> NewTabPageViewController?) {
        self.makeViewController = makeViewController
    }

    /// Retain one controller across view rebuilds and mode changes so its data subscriptions,
    /// action handlers, and scroll state stay with the same instance.
    var viewController: NewTabPageViewController? {
        if let cachedViewController { return cachedViewController }
        cachedViewController = makeViewController()
        return cachedViewController
    }

    func updateOpenedAfterIdle(_ openedAfterIdle: Bool) {
        cachedViewController?.setOpenedAfterIdle(openedAfterIdle)
    }
}
