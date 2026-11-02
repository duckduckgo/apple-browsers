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
    let favoritesModel: FavoritesViewModel?
    let messagesModel: NewTabPageMessagesModel?
    var showsSearchModules = true
    var recentChats: SuggestionsListViewModel?
    var escapeHatch: EscapeHatchModel?
    var syncPromo: AnyView?
    var isAddressBarAtBottom = false
    var contentTopInset: CGFloat = 0
    var usesScrollableEscapeHatch = true
    var onEscapeHatchGeometryChange: ((EmbeddedEscapeHatchGeometry?) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    RedesignedNewTabPageModulesView(favoritesModel: favoritesModel)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(CollapsedUnlessShown(isShown: showsSearchModules))
                    if let escapeHatch {
                        RedesignedEscapeHatchView(model: escapeHatch)
                            .modifier(EmbeddedEscapeHatchGeometryReader())
                            .frame(maxWidth: .infinity)
                            .padding(.top, hatchTopPadding)
                            .padding(.horizontal, 16)
                    }
                    if let recentChats {
                        VStack(spacing: FocusedChromeView.Metrics.bottomInset) {
                            if let syncPromo {
                                syncPromo
                            }
                            LegacyRecentChatsView(viewModel: recentChats, isAddressBarAtBottom: isAddressBarAtBottom)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, FocusedChromeView.Metrics.bottomInset)
                    }
                    if let messagesModel {
                        RedesignedNewTabPageMessagesView(messagesModel: messagesModel)
                            .modifier(CollapsedUnlessShown(isShown: showsSearchModules))
                    }
                }
                .animation(nil, value: showsSearchModules)
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
        guard !showsSearchModules else { return 0 }
        return RedesignedNewTabPageModulesView.topPadding
    }
}

/// Collapses, hides and disables a view while it is not shown.
private struct CollapsedUnlessShown: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        content
            .frame(height: isShown ? nil : 0)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }
}
