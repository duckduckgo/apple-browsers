//
//  DebugScreensViewModel+Screens.swift
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
import SwiftUI
import UIKit

extension DebugScreensViewModel {

    /// Just add your view or debug building logic to this array. In the UI this will be ordered by the title.
    /// Note that the storyboard is not passed to the controller builder - ideally we'll mirgate away from that to SwiftUI entirely
    var screens: [DebugScreen] {
        return [
            .view(title: "AI Chat", { _ in
                AIChatDebugView()
            }),
            .view(title: "Feature Flags", { _ in
                FeatureFlagsMenuView()
            }),
            .controller(title: "Image Cache", { d in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "ImageCacheDebugViewController") { coder in
                    ImageCacheDebugViewController(coder: coder,
                                                  bookmarksDatabase: d.bookmarksDatabase,
                                                  fireproofing: d.fireproofing)
                }
            }),
            .controller(title: "Sync", { d in
                let storyboard = UIStoryboard(name: "Debug", bundle: nil)
                return storyboard.instantiateViewController(identifier: "SyncDebugViewController") { coder in
                    SyncDebugViewController(coder: coder,
                                            sync: d.syncService,
                                            bookmarksDatabase: d.bookmarksDatabase)
                }
            }),
            .view(title: "Crashes", { _ in
                CrashDebugScreen()
            })
        ]
    }

}
