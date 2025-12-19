//
//  CardsListView.swift
//  DuckDuckGo
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
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

// MARK: - Remote Messaging UI Namespace

enum RemoteMessagingUI {}

// MARK: - Display Models

extension RemoteMessagingUI {

    struct CardsListDisplayModel {
        struct Item {
            let icon: String
            let title: String
            let description: String
            let disclosureIcon: Image?
            let onAppear: (() -> Void)?
            let onTapAction: (() -> Void)?
        }

        let screenTitle: String
        let icon: String?
        let items: [CardsListDisplayModel.Item]
        let onAppear: (() -> Void)?
        let primaryAction: (title: String, action: () -> Void)?
    }

}

// MARK: - Cards List View

extension RemoteMessagingUI {

    struct CardsListView: View {
        let displayModel: CardsListDisplayModel

        var body: some View {
            VStack(spacing: Metrics.CardsList.componentsVerticalSpacing) {
                VStack(spacing: Metrics.CardsList.contentInset) {
                    Header(icon: displayModel.icon, title: displayModel.screenTitle)

                    Content(items: displayModel.items)
                }

                if let primaryAction = displayModel.primaryAction {
                    Footer(title: primaryAction.title, action: primaryAction.action)
                }
            }
            .padding(.horizontal, Metrics.CardsList.contentHorizontalPadding)
            .background(Color(singleUseColor: .whatsNewBackground))
            .onAppear(perform: displayModel.onAppear)
        }
    }

}

// MARK: - Card View

extension RemoteMessagingUI {

    struct CardView: View {
        let displayModel: CardsListDisplayModel.Item

        var body: some View {
            HStack(alignment: .top, spacing: Metrics.Card.contentHorizontalSpacing) {
                VStack(alignment: .leading) {
                    Image(displayModel.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Metrics.Card.iconSize.width, height: Metrics.Card.iconSize.height)
                }

                VStack(alignment: .leading, spacing: Metrics.Card.copyVerticalSpacing) {
                    Text(verbatim: displayModel.title)
                        .font(.system(size: Metrics.Card.titleSize, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text(verbatim: displayModel.description)
                        .font(.system(size: Metrics.Card.descriptionSize))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let disclosureIcon = displayModel.disclosureIcon {
                    VStack(alignment: .leading) {
                        disclosureIcon
                    }
                }
            }
            .padding([.bottom, .top], Metrics.Card.contentVerticalPadding)
            .padding([.trailing, .leading], Metrics.Card.contentHorizontalPadding)
            .background(Color(designSystemColor: .surface))
            .cornerRadius(Metrics.Card.contentCornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.Card.contentCornerRadius)
                    .strokeBorder(.black.opacity(Metrics.Card.borderOpacity), lineWidth: Metrics.Card.borderWidth)
            }
            .onTapGesture {
                displayModel.onTapAction?()
            }
            .onFirstAppear {
                displayModel.onAppear?()
            }
        }
    }

}

// MARK: - Header

private extension RemoteMessagingUI.CardsListView {

    struct Header: View {
        let icon: String?
        let title: String

        var body: some View {
            VStack(alignment: .center, spacing: 24.0) {
                logoImage

                Text(title)
                    .font(.system(size: Metrics.CardsList.titleFontSize, weight: .bold))
                    .kerning(Metrics.CardsList.titleKerning)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.primary)
            }
        }

        @ViewBuilder
        private var logoImage: some View {
            if let icon {
                Image(icon)
                    .scaledToFit()
            } else {
                EmptyView()
            }
        }
    }

    struct Content: View {
        let items: [RemoteMessagingUI.CardsListDisplayModel.Item]

        var body: some View {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: Metrics.CardsList.cardsVerticalSpacing) {
                    ForEach(items.indices, id: \.self) { index in
                        RemoteMessagingUI.CardView(displayModel: items[index])
                    }
                }
            }
        }

    }

    struct Footer: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(verbatim: title)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.bottom, Metrics.CardsList.buttonBottomPadding)
        }
    }

}

// MARK: - Card Gradient

extension RemoteMessagingUI.CardsListView {

    struct CardGradient: View {
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            switch colorScheme {
            case .light:
                LightGradient()
            case .dark:
                DarkGradient()
            @unknown default:
                LightGradient()
            }
        }
    }

}

private extension RemoteMessagingUI.CardsListView.CardGradient {

    // Autogenerated from Figma
    struct LightGradient: View {
        var body: some View {
            AngularGradient(
                stops: [
                    Gradient.Stop(color: Color(red: 0.8, green: 0.85, blue: 1), location: 0.00),
                    Gradient.Stop(color: Color(red: 0.96, green: 0.96, blue: 0.96), location: 0.59),
                    Gradient.Stop(color: Color(red: 0.88, green: 0.82, blue: 0.93), location: 1.00),
                ],
                center: .center,
                angle: .degrees(80.67)
            )
            .blur(radius: 15)
        }
    }

    // Autogenerated from Figma
    struct DarkGradient: View {
        var body: some View {
            ZStack {
                EllipticalGradient(
                    colors: [
                        Color(red: 0.07, green: 0.01, blue: 0.21).opacity(0.8),
                        .clear,
                    ],
                    center: UnitPoint(x: -0.03, y: -0.08),
                    endRadiusFraction: 1
                )
                EllipticalGradient(
                    colors: [
                        Color(red: 0.17, green: 0.08, blue: 0.44).opacity(0.6),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.71, y: -0.41),
                    endRadiusFraction: 1
                )
                EllipticalGradient(
                    colors: [
                        Color(red: 0.92, green: 0.53, blue: 0.42).opacity(0.8),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.76, y: -0.37),
                    endRadiusFraction: 1
                )
                EllipticalGradient(
                    colors: [
                        Color(red: 0.04, green: 0.13, blue: 0.35).opacity(0.8),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.17, y: -0.19),
                    endRadiusFraction: 1
                )
            }
            .background(Color(red: 0.03, green: 0, blue: 0.1))
        }
    }

}

// MARK: - Metrics

private enum Metrics {

    enum CardsList {
        @MainActor
        static let contentHorizontalPadding: CGFloat = MetricBuilder<CGFloat>.init(iPhone: 24.0, iPad: 48.0).build()
        static let componentsVerticalSpacing: CGFloat = 24.0
        @MainActor
        static let contentInset: CGFloat = MetricBuilder<CGFloat>.init(iPhone: 24.0, iPad: 48.0).build()
        static let titleFontSize: CGFloat = 28.0
        static let titleKerning: CGFloat = 0.38
        static let cardsVerticalSpacing: CGFloat = 12.0
        @MainActor
        static let buttonBottomPadding: CGFloat = MetricBuilder<CGFloat>.init(iPhone: 12.0, iPad: 24.0).build()
    }

    enum Card {
        static let contentHorizontalSpacing: CGFloat = 12.0
        static let contentVerticalPadding: CGFloat = 16.0
        static let contentHorizontalPadding: CGFloat = 12.0
        static let iconSize = CGSize(width: 48.0, height: 48.0)
        static let copyVerticalSpacing: CGFloat = 4.0
        static let titleSize: CGFloat = 15.0
        static let descriptionSize: CGFloat = 13.0
        static let contentCornerRadius: CGFloat = 12.0
        static let borderOpacity: CGFloat = 0.05
        static let borderWidth: CGFloat = 1
    }

}

// MARK: - Previews

#if DEBUG
struct CardsList_Previews: PreviewProvider {
    static func cardsList(shouldShowAction: Bool, repeatedItems: Bool = false) -> RemoteMessagingUI.CardsListView {
        let action: (String, () -> Void)? = if shouldShowAction {
            ("Got It", {})
        } else {
            nil
        }

        let listItems = if repeatedItems {
            items.reduce(into: [RemoteMessagingUI.CardsListDisplayModel.Item]()) { partial, item in
                partial.append(contentsOf: Array(repeating: item, count: 5))
            }
        } else {
            items
        }

        return .init(displayModel: .init(
            screenTitle: "What’s New",
            icon: "RemoteMessageDDGAnnouncement",
            items: listItems,
            onAppear: nil,
            primaryAction: action
        ))
    }

    static let items: [RemoteMessagingUI.CardsListDisplayModel.Item] = [
        .init(
            icon: "RemoteImageAI",
            title: "Hide AI Images in Search",
            description: "Easily hide AI images in your search results with the \"AI images\" search filter.",
            disclosureIcon: chevron,
            onAppear: nil,
            onTapAction: nil
        ),
        .init(
            icon: "RemoteRadar",
            title: "Enhanced Scam Blocker",
            description: "Browse confidently with protection against even more sneaky online threats.",
            disclosureIcon: chevron,
            onAppear: nil,
            onTapAction: nil
        ),
        .init(
            icon: "RemoteKeyImport",
            title: "Import From Safari",
            description: "Add your saved bookmarks and passwords in seconds!",
            disclosureIcon: chevron,
            onAppear: nil,
            onTapAction: nil
        )
    ]

    static let chevron: Image = Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronRightSmall)

    static var previews: some View {
        cardsList(shouldShowAction: true)
            .previewDisplayName("What’s New + Main Action - Light Mode")
            .preferredColorScheme(.light)

        cardsList(shouldShowAction: true)
            .previewDisplayName("What’s New + Main Action - Dark Mode")
            .preferredColorScheme(.dark)

        cardsList(shouldShowAction: true, repeatedItems: true)
            .previewDisplayName("What’s New - Multiple Items")

        cardsList(shouldShowAction: false)
            .previewDisplayName("What’s New No Main Action - Light Mode")
            .preferredColorScheme(.light)

        cardsList(shouldShowAction: false)
            .previewDisplayName("What’s New No Main Action - Dark Mode")
            .preferredColorScheme(.dark)
    }
}
#endif
