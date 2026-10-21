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
import DesignResourcesKitIcons

public enum ContextualOnboardingListItem: Equatable {
    case search(title: String)
    case site(title: String)
    case surprise(title: String, visibleTitle: String)
    case aiChat(title: String)

    public var visibleTitle: String {
        switch self {
        case .search(let title):
            return title
        case .site(let title):
            return title.replacingOccurrences(of: "https://", with: "")
        case .surprise(_, let visibleTitle):
            return visibleTitle
        case .aiChat(let title):
            return title
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
        case .aiChat(let title):
            return title
        }
    }

    public var image: DesignSystemImage {
        switch self {
        case .search:
            return DesignSystemImages.Glyphs.Size16.findSearch
        case .site:
            return DesignSystemImages.Glyphs.Size16.globe
        case .surprise:
            return DesignSystemImages.Glyphs.Size16.wand
        case .aiChat:
            return DesignSystemImages.Glyphs.Size16.aiChat
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
                            icon(forItemAt: index)
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

    private func icon(forItemAt index: Int) -> Image {
#if os(iOS)
        Image(uiImage: list[index].image)
#elseif os(macOS)
        Image(nsImage: list[index].image)
#endif
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
