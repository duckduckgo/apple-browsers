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
    var escapeHatch: EscapeHatchModel?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    RedesignedNewTabPageModulesView(favoritesModel: favoritesModel)
                    if let escapeHatch {
                        EscapeHatchView(model: escapeHatch, usesMaterialBackground: true)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                    }
                    if let messagesModel {
                        RedesignedNewTabPageMessagesView(messagesModel: messagesModel)
                    }
                }
                .padding(.leading, geometry.safeAreaInsets.leading)
                .padding(.trailing, geometry.safeAreaInsets.trailing)
            }
            // Clip at the page edges, not the landscape safe-area edges. The content keeps
            // its safe-area alignment while the message shadows can extend into the margins.
            .ignoresSafeArea(.container, edges: .horizontal)
            .scrollDismissesKeyboardIfAvailable()
        }
        .background(Color(designSystemColor: .background))
    }
}
