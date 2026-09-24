//
//  UnifiedToggleInputModeCueMenu.swift
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

import UIKit

/// The cue picker offered in the address bar's long-press menu while the options are evaluated,
/// so they can be switched in a couple of taps.
enum UnifiedToggleInputModeCueMenu {

    static func makeSection(settings: UnifiedToggleInputModeCueSettings = UnifiedToggleInputModeCueSettings()) -> UIMenu {
        let chosen = settings.style
        let actions = UnifiedToggleInputModeCueStyle.allCases.map { style in
            UIAction(title: style.title, state: style == chosen ? .on : .off) { _ in
                settings.style = style
            }
        }
        return UIMenu(title: "Duck.ai cue (prototype)", options: [.displayInline, .singleSelection], children: actions)
    }
}
