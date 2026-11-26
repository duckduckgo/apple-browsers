//
//  InitialViewLoader.swift
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

/// Draws the scene's first screen once, deciding at that moment whether it is the after-idle New Tab Page.
@MainActor
struct InitialViewLoader {

    /// Whether the first screen hasn't been drawn yet.
    private(set) var isPending = true
    /// Whether the first screen was the after-idle New Tab Page.
    private(set) var drewIdleReturnNewTabPage = false

    private let defersUntilForeground: Bool
    private let drawsIdleReturnNewTabPage: (_ hasLaunchAction: Bool) -> Bool
    private let start: (_ drawsIdleReturnNewTabPage: Bool) -> Void

    init(defersUntilForeground: Bool,
         drawsIdleReturnNewTabPage: @escaping (_ hasLaunchAction: Bool) -> Bool,
         start: @escaping (_ drawsIdleReturnNewTabPage: Bool) -> Void) {
        self.defersUntilForeground = defersUntilForeground
        self.drawsIdleReturnNewTabPage = drawsIdleReturnNewTabPage
        self.start = start
    }

    /// Draws the first screen when the scene connects, unless it waits for the first foreground.
    mutating func loadAtConnection(hasLaunchAction: Bool) {
        guard !defersUntilForeground else { return }
        loadIfPending(hasLaunchAction: hasLaunchAction)
    }

    /// Draws the first screen unless it has been drawn already.
    mutating func loadIfPending(hasLaunchAction: Bool) {
        guard isPending else { return }
        isPending = false
        drewIdleReturnNewTabPage = drawsIdleReturnNewTabPage(hasLaunchAction)
        start(drewIdleReturnNewTabPage)
    }

}
