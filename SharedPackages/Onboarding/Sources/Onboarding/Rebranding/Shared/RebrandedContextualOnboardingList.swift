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
                    Button(action: { action(list[index]) }) {
                        HStack(spacing: theme.optionsListMetrics.innerContentHorizontalSpacing) {
                            Image(list[index].imageName, bundle: bundle)
                                .frame(width: theme.optionsListMetrics.iconSize.width, height: theme.optionsListMetrics.iconSize.height)
                            Text(list[index].visibleTitle)
                                .frame(alignment: .leading)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(theme.optionsListButtonStyle.style)
                }
            }
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
