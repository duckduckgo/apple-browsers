//
//  StatusIndicator.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import UIComponents

// `StatusIndicator` and `StatusIndicatorView` now live in the UIComponents package. These app-side
// extensions supply the app's localized status copy and keep existing `StatusIndicatorView(status:)`
// call sites working without threading text through each one.
extension StatusIndicator {
    var text: String {
        switch self {
        case .alwaysOn:
            return UserText.settingsAlwaysOn
        case .on:
            return UserText.settingsOn
        case .off:
            return UserText.settingsOff
        }
    }
}

extension StatusIndicatorView {
    init(status: StatusIndicator, isDotHidden: Bool = false) {
        self.init(status: status, text: status.text, isDotHidden: isDotHidden)
    }
}
