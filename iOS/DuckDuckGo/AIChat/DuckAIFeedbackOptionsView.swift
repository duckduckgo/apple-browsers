//
//  DuckAIFeedbackOptionsView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

struct DuckAIFeedbackOptionsView: View {

    enum Sentiment {
        case positive
        case critical
    }

    let onSelect: (Sentiment) -> Void

    var body: some View {
        List {
            Section {
                optionRow(title: UserText.aiChatFeedbackOptionPositive,
                          image: Self.positiveIcon,
                          sentiment: .positive)
                optionRow(title: UserText.aiChatFeedbackOptionCritical,
                          image: Self.criticalIcon,
                          sentiment: .critical)
            }
            .listRowBackground(Color(designSystemColor: .surface))
        }
        .listStyle(.insetGrouped)
        .hideScrollContentBackground()
        .background(Color(designSystemColor: .background))
        .tint(Color(designSystemColor: .textPrimary))
    }

    private func optionRow(title: String, image: UIImage?, sentiment: Sentiment) -> some View {
        Button {
            onSelect(sentiment)
        } label: {
            HStack(spacing: 16) {
                Image(uiImage: (image ?? UIImage()).withRenderingMode(.alwaysTemplate))
                    .foregroundStyle(Color(designSystemColor: .icons))

                Text(title)
                    .daxBodyRegular()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let positiveIcon = DesignSystemImages.Glyphs.Size24.thumbsUp
    private static let criticalIcon = DesignSystemImages.Glyphs.Size24.thumbsDown
}
