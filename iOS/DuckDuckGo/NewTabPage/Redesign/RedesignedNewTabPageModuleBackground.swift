//
//  RedesignedNewTabPageModuleBackground.swift
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

import Combine
import DesignResourcesKit
import SwiftUI

/// Surface shared by redesigned NTP cards, independent of the search input's raised or Liquid Glass card.
/// Frosted and tinted over the illustration, the standard surface on a plain page.
struct RedesignedNewTabPageModuleBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let customizationStore: NewTabPageCustomizationStore
    @State private var theme: NewTabPageTheme

    init(customizationStore: NewTabPageCustomizationStore = NewTabPageCustomizationStore()) {
        self.customizationStore = customizationStore
        _theme = State(initialValue: customizationStore.theme)
    }

    var body: some View {
        surface
            .onReceive(customizationStore.themePublisher.receive(on: DispatchQueue.main)) { theme in
                self.theme = theme
            }
    }

    @ViewBuilder
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: RedesignedNewTabPageCardBackground.cornerRadius, style: .continuous)
        switch theme {
        case .plain:
            shape.fill(Color(designSystemColor: .surface))
        case .blue:
            if reduceTransparency {
                shape.fill(Color(designSystemColor: .surfaceSecondary))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color(singleUseColor: .newTabPageModuleTint)))
            }
        }
    }
}
