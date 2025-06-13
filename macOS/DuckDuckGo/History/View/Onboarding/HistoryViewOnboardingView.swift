//
//  HistoryViewOnboardingView.swift
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
import SwiftUIExtensions

struct HistoryViewOnboardingView: View {

    enum Const {
        static let width: CGFloat = 384
    }

    @ObservedObject var model: HistoryViewOnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Image(.historyViewOnboarding)
                .padding(.bottom, 8)

            Text(UserText.historyViewOnboardingTitle)
                .fixMultilineScrollableText()
                .font(.system(size: 15).weight(.semibold))
                .padding(.bottom, 12)

            Text(.init(UserText.historyViewOnboardingMessage(shortcut: "⌘Y")))
                .fixMultilineScrollableText()
                .font(.system(size: 13))
                .padding(.bottom, 8)

            Text(.init(UserText.historyViewOnboardingLocalStorageExplanation))
                .fixMultilineScrollableText()
                .font(.system(size: 13))
                .padding(.bottom, 20)

            HStack {
                Button {
                    model.notNow()
                } label: {
                    Text(UserText.close)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0))

                Button {
                    model.showHistory()
                } label: {
                    Text(UserText.historyViewOnboardingAccept)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: Const.width)
    }
}

#Preview {
    HistoryViewOnboardingView(model: .init(ctaCallback: { _ in }))
        .frame(width: HistoryViewOnboardingView.Const.width)
}
