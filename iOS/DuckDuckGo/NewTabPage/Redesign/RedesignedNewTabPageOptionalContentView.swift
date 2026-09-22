//
//  RedesignedNewTabPageOptionalContentView.swift
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

import SwiftUI

/// Renders the same eligible messages and return-to-tab model as the production resting page.
struct RedesignedNewTabPageOptionalContentView: View {
    @ObservedObject var pageModel: NewTabPageViewModel
    @ObservedObject var messagesModel: NewTabPageMessagesModel

    var body: some View {
        if pageModel.escapeHatch != nil || !messagesModel.homeMessageViewModels.isEmpty {
            VStack(spacing: 20) {
                if let escapeHatch = pageModel.escapeHatch {
                    EscapeHatchView(model: escapeHatch)
                        .frame(maxWidth: .infinity)
                }
                ForEach(messagesModel.homeMessageViewModels, id: \.viewIdentity) { messageModel in
                    HomeMessageView(viewModel: messageModel)
                        .frame(maxWidth: .infinity)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
