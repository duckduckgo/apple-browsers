//
//  RedesignedFocusedSearchModulesView.swift
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

import DesignResourcesKit
import SwiftUI

struct RedesignedFocusedSearchModulesView: View {
    /// Set when no live page sits behind the editor (a loaded web page), so this view draws the modules itself.
    var embeddedModules: EmbeddedModules?
    var recentChats: SuggestionsListViewModel?
    var escapeHatch: EscapeHatchModel?
    /// Whether the escape hatch shows here. It stays laid out while hidden, so a mode switch never animates it in.
    var showsEscapeHatch = true
    var syncPromo: AnyView?
    var isAddressBarAtBottom = false
    var contentTopInset: CGFloat = 0
    var usesScrollableEscapeHatch = true
    var onEscapeHatchGeometryChange: ((EmbeddedEscapeHatchGeometry?) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if let embeddedModules {
                        RedesignedNewTabPageModulesView(favoritesModel: embeddedModules.favoritesModel)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(height: embeddedModules.isVisible ? nil : 0)
                            .opacity(embeddedModules.isVisible ? 1 : 0)
                            .allowsHitTesting(embeddedModules.isVisible)
                            .accessibilityHidden(!embeddedModules.isVisible)
                    }
                    if let escapeHatch {
                        RedesignedEscapeHatchView(model: escapeHatch)
                            .modifier(EmbeddedEscapeHatchGeometryReader())
                            .frame(maxWidth: .infinity)
                            .padding(.top, hatchTopPadding)
                            .padding(.horizontal, 16)
                            .opacity(showsEscapeHatch ? 1 : 0)
                            .allowsHitTesting(showsEscapeHatch)
                            .accessibilityHidden(!showsEscapeHatch)
                    }
                    if let recentChats {
                        VStack(spacing: FocusedChromeView.Metrics.bottomInset) {
                            if let syncPromo {
                                syncPromo
                            }
                            LegacyRecentChatsView(viewModel: recentChats, isAddressBarAtBottom: isAddressBarAtBottom, usesCardSurface: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, FocusedChromeView.Metrics.bottomInset)
                    }
                    if let embeddedModules, let messagesModel = embeddedModules.messagesModel {
                        RedesignedNewTabPageMessagesView(messagesModel: messagesModel)
                            .frame(height: embeddedModules.isVisible ? nil : 0)
                            .opacity(embeddedModules.isVisible ? 1 : 0)
                            .allowsHitTesting(embeddedModules.isVisible)
                            .accessibilityHidden(!embeddedModules.isVisible)
                    }
                }
                .animation(nil, value: embeddedModules?.isVisible)
                .animation(nil, value: showsEscapeHatch)
                .animation(nil, value: recentChats != nil)
                .modifier(FocusedContentGeometryGroup(isEnabled: usesScrollableEscapeHatch))
                .modifier(FocusedContentTopInset(topInset: contentTopInset,
                                                 onEscapeHatchGeometryChange: onEscapeHatchGeometryChange))
                .padding(.leading, geometry.safeAreaInsets.leading)
                .padding(.trailing, geometry.safeAreaInsets.trailing)
            }
            .coordinateSpace(name: EmbeddedEscapeHatchGeometryReader.scrollSpace)
            // Clip at the page edges, not the landscape safe-area edges. The content keeps
            // its safe-area alignment while the message shadows can extend into the margins.
            .ignoresSafeArea(.container, edges: .horizontal)
            .modifier(FocusedContentVerticalBounce(isEnabled: usesScrollableEscapeHatch))
            .scrollDismissesKeyboardIfAvailable()
        }
    }

    private var hatchTopPadding: CGFloat {
        guard embeddedModules?.isVisible == true else { return RedesignedNewTabPageModulesView.topPadding }
        return 0
    }
}

extension RedesignedFocusedSearchModulesView {

    /// The favorites and messages drawn inside the focused layer.
    struct EmbeddedModules {
        let favoritesModel: FavoritesViewModel?
        let messagesModel: NewTabPageMessagesModel?
        let isVisible: Bool
    }
}
