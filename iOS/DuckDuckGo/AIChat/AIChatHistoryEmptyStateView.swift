//
//  AIChatHistoryEmptyStateView.swift
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
import SwiftUI
import AIChat
import DuckUI
import DesignResourcesKitIcons

/// Empty state for the native Duck.ai chat-history sheet — illustration, headline,
/// and a primary "Open Duck.ai" button.
struct AIChatHistoryEmptyStateView: View {

    @ObservedObject var viewModel: AIChatHistoryViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(uiImage: DesignSystemImages.Color.Size96.duckAIDDGHero)
                    .frame(width: 96, height: 96)
                Text(UserText.aiChatHistoryEmptyStateTitle)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
            }

            Button(action: viewModel.openDuckAiTapped) {
                Text(UserText.aiChatHistoryEmptyStateOpenDuckAi)
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
private struct PreviewChatHistoryReader: ChatHistoryReading {
    func chatsPublisher() -> AnyPublisher<[DuckAiChat], Error> {
        Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}

#Preview {
    AIChatHistoryEmptyStateView(viewModel: AIChatHistoryViewModel(reader: PreviewChatHistoryReader()))
}
#endif
