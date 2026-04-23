//
//  FireTabsTip.swift
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

import TipKit
import DesignResourcesKit
import DesignResourcesKitIcons

@available(iOS 17.0, *)
struct FireTabsTip: Tip {
    @Parameter
    static var hasVisitedFireMode: Bool = false

    var id: String {
        "com.duckduckgo.fireTabsTip"
    }

    var title: Text {
        Text(UserText.fireModeTabSwitcherTipTitle)
            .foregroundStyle(Color(designSystemColor: .textPrimary))
    }

    var message: Text? {
        Text(UserText.fireModeTabSwitcherTipDescription)
            .foregroundStyle(Color(designSystemColor: .textSecondary))
    }

    var image: Image? {
        Image(uiImage: DesignSystemImages.Color.Size96.fireTab)
    }

    var rules: [Rule] {
        #Rule(Self.$hasVisitedFireMode) {
            $0 == false
        }
    }

    var options: [TipOption] {
        [MaxDisplayCount(5)]
    }
}
