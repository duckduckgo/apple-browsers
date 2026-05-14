//
//  RebrandedContextualOnboardingList.swift
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

public extension OnboardingRebranding {

    struct ContextualOnboardingListView: View {
        @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var theme: OnboardingTheme.ContextualOnboardingMetrics

        private let list: [ContextualOnboardingListItem]
        private let action: (_ item: ContextualOnboardingListItem) -> Void

        public init(list: [ContextualOnboardingListItem], action: @escaping (ContextualOnboardingListItem) -> Void) {
            self.list = list
            self.action = action
        }

        public var body: some View {
            VStack(spacing: theme.optionsListMetrics.interItemSpacing) {
                ForEach(list.indices, id: \.self) { index in
                    ContextualOnboardingListViewItem(
                        item: list[index],
                        iconSize: theme.optionsListMetrics.iconSize,
                        action: { action(list[index]) }
                    )
                }
            }
        }
    }

    struct ContextualOnboardingListViewItem: View {
        @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var theme

        private let item: ContextualOnboardingListItem
        private let iconSize: CGSize
        private let action: () -> Void

        public init(item: ContextualOnboardingListItem, iconSize: CGSize, action: @escaping () -> Void) {
            self.item = item
            self.iconSize = iconSize
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                HStack(spacing: theme.optionsListMetrics.innerContentHorizontalSpacing) {
                    icon
                        .frame(width: iconSize.width, height: iconSize.height)
                    Text(item.visibleTitle)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(theme.optionsListButtonStyle.style)
        }

        private var icon: Image {
#if os(iOS)
            Image(uiImage: item.image)
#elseif os(macOS)
            Image(nsImage: item.image)
#endif
        }
    }

}

#if os(iOS)
#Preview("OnboardingOptionsListView ") {
    let list = [
        ContextualOnboardingListItem.search(title: "Search"),
        ContextualOnboardingListItem.site(title: "Website"),
        ContextualOnboardingListItem.surprise(title: "Surprise", visibleTitle: "Surpeise me!"),
    ]
    return OnboardingRebranding.ContextualOnboardingListView(list: list) { _ in }
        .applyOnboardingTheme(.iOSRebranding2026, stepProgressTheme: .rebranding2026)
        .padding()
}
#endif
