//
//  ContextualOnboardingList.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI

public enum ContextualOnboardingListItem: Equatable {
    case search(title: String)
    case site(title: String)
    case surprise(title: String, visibleTitle: String)

    var visibleTitle: String {
        switch self {
        case .search(let title):
            return title
        case .site(let title):
            return title.replacingOccurrences(of: "https://", with: "")
        case .surprise(_, let visibleTitle):
            return visibleTitle
        }
    }

    public var title: String {
        switch self {
        case .search(let title):
            return title
                .replacingOccurrences(of: "”", with: "")
                .replacingOccurrences(of: "“", with: "")
        case .site(let title):
            return title
        case .surprise(let title, _):
            return title
        }
    }

    var imageName: String {
        switch self {
        case .search:
            return "SuggestLoupe"
        case .site:
            return "SuggestGlobe"
        case .surprise:
            return "Wand-16"
        }
    }

}

public struct ContextualOnboardingListView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let list: [ContextualOnboardingListItem]
    private var action: (_ item: ContextualOnboardingListItem) -> Void
    private let iconSize: CGFloat

#if os(macOS)
private var strokeColor: Color {
    return (colorScheme == .dark) ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
}
#else
private let strokeColor = Color.blue
#endif

    public init(list: [ContextualOnboardingListItem], action: @escaping (ContextualOnboardingListItem) -> Void, iconSize: CGFloat = 16.0) {
        self.list = list
        self.action = action
        self.iconSize = iconSize
    }

    public var body: some View {
        VStack {
            ForEach(list.indices, id: \.self) { index in
                OnboardingBorderedButton(
                    content: {
                        HStack {
                            Image(list[index].imageName, bundle: bundle)
                                .frame(width: iconSize, height: iconSize)
                            Text(list[index].visibleTitle)
                                .frame(alignment: .leading)
                            Spacer(minLength: 0)
                        }
                    },
                    action: {
                        action(list[index])
                    }
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("List") {
    let list = [
        ContextualOnboardingListItem.search(title: "Search"),
        ContextualOnboardingListItem.site(title: "Website"),
        ContextualOnboardingListItem.surprise(title: "Surprise", visibleTitle: "Surpeise me!"),
    ]
    return ContextualOnboardingListView(list: list) { _ in }
        .padding()
}
