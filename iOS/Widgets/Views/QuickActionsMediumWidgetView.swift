//
//  QuickActionsMediumWidgetView.swift
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


import SwiftUI
import WidgetKit
import AppIntents
import DesignResourcesKit
import DesignResourcesKitIcons

@available(iOS 17.0, *)
struct QuickActionsMediumWidgetView: View {
    var entry: QuickActionsMediumEntry

    private let shortcuts: [ShortcutOption] = [.voiceSearch,
                                               .passwords,
                                               .favorites,
                                               .emailProtection]

    var body: some View {
        DesignSystemWidgetContainerView {
            VStack(spacing: 0) {
                Link(destination: DeepLinks.newSearch) {
                    ResponsiveSearchFieldView(isAIChatEnabled: entry.isAIChatEnabled, showLogo: true, isRightIconEnabled: true)
                }
                .padding(.bottom, 16)

                HStack {
                    ForEach(shortcuts.indices, id: \.self) { index in
                        let shortcut = shortcuts[index]

                        Link(destination: shortcut.destination) {
                            ResponsiveIconView(image: shortcut.icon)
                        }

                        if index < shortcuts.count - 1 {
                            Spacer(minLength: 16)
                        }
                    }
                }
            }
        }
    }
}
