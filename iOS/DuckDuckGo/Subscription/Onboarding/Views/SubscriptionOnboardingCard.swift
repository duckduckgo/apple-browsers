//
//  SubscriptionOnboardingCard.swift
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
import UIComponents

// MARK: - Card Shell

/// The rounded card shell for the post-subscription onboarding flow: a design-system surface with an
/// optional `header`, its main `items` content, and an optional `footer`, stacked vertically. When a
/// header is present a full-width divider separates it from the content below. `bordered` adds a
/// hairline border; `borderless` is fill-only.
///
/// For a card built from `CardItem`s, use the `CardItem` / `[CardItem]` convenience initializers — the
/// list variants lay the rows out with a divider between adjacent rows (via `CardItemList`). For richer
/// layouts pass arbitrary views through the `header` / `items` / `footer` builders.
struct SubscriptionOnboardingCard<Header: View, Items: View, Footer: View>: View {
    /// The card's visual style.
    enum Style {
        case bordered
        case borderless
    }

    private let cornerRadius: CGFloat = 26
    private let style: Style
    private let padding: CGFloat
    private let header: () -> Header
    private let items: () -> Items
    private let footer: () -> Footer

    init(style: Style = .bordered,
         padding: CGFloat = 16,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder items: @escaping () -> Items,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.style = style
        self.padding = padding
        self.header = header
        self.items = items
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
            if showsHeaderDivider {
                fullWidthDivider
            }
            items()
            footer()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(designSystemColor: .decorationQuaternary))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if style == .bordered {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(designSystemColor: .decorationTertiary), lineWidth: 1)
            }
        }
    }
}

// MARK: - Card Shell Layout

private extension SubscriptionOnboardingCard {
    var showsHeaderDivider: Bool {
        Header.self != EmptyView.self
    }

    /// A hairline that bleeds to the card's edges — the negative horizontal padding cancels the content
    /// padding, so it spans the full card width without widening the card.
    var fullWidthDivider: some View {
        Color(designSystemColor: .lines)
            .frame(height: 1)
            .padding(.horizontal, -padding)
    }
}

// MARK: - Convenience Initializers

extension SubscriptionOnboardingCard where Header == EmptyView, Items == CardItem {
    /// Creates a card holding a single `CardItem` with a footer below it.
    init(_ item: CardItem,
         style: Style = .bordered,
         padding: CGFloat = 16,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.init(style: style, padding: padding, header: { EmptyView() }, items: { item }, footer: footer)
    }
}

extension SubscriptionOnboardingCard where Items == CardItemList, Footer == EmptyView {
    /// Creates a card holding a single `CardItem`, with no header or footer. `contentInset` insets the
    /// item's content — the padding becomes part of the card. Defaults to `16` on all sides.
    init(_ item: CardItem,
         style: Style = .bordered,
         contentInset: CardItemList.ContentInset = CardItemList.ContentInset(horizontal: 16, vertical: 16)) where Header == EmptyView {
        self.init([item], style: style, padding: 0, contentInset: contentInset)
    }

    /// Creates a card from an array of `CardItem`s (laid out as divider-separated rows) with a `header`
    /// above them, separated by a full-width divider. See `CardItemList` for the row parameters.
    init(_ items: [CardItem],
         style: Style = .bordered,
         padding: CGFloat = 16,
         dividerLeadingInset: CGFloat? = nil,
         contentInset: CardItemList.ContentInset = .zero,
         onSelect: @escaping (Int) -> (() -> Void)? = { _ in nil },
         @ViewBuilder header: @escaping () -> Header) {
        self.init(style: style, padding: padding, header: header, items: {
            CardItemList(items, dividerLeadingInset: dividerLeadingInset, contentInset: contentInset, onSelect: onSelect)
        }, footer: { EmptyView() })
    }

    /// Creates a card from an array of `CardItem`s (laid out as divider-separated rows), with no header or
    /// footer (a single item, or none, draws no divider). See `CardItemList` for the row parameters.
    init(_ items: [CardItem],
         style: Style = .bordered,
         padding: CGFloat = 16,
         dividerLeadingInset: CGFloat? = nil,
         contentInset: CardItemList.ContentInset = .zero,
         onSelect: @escaping (Int) -> (() -> Void)? = { _ in nil }) where Header == EmptyView {
        self.init(style: style, padding: padding, header: { EmptyView() }, items: {
            CardItemList(items, dividerLeadingInset: dividerLeadingInset, contentInset: contentInset, onSelect: onSelect)
        }, footer: { EmptyView() })
    }
}

// MARK: - Previews

#if DEBUG

import DuckUI

private struct SubscriptionOnboardingCardPreviewSamples: View {
    @State private var selection = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SubscriptionOnboardingCard(
                    CardItem(
                        icon: CardItemIcon(position: .topLeading, visual: .image(Image(systemName: "creditcard.fill")), size: .size32, spacing: 4),
                        title: CardItemText("Recover financial losses", font: .footnoteSemibold),
                        text: CardItemText("We'll work with financial institutions to help reverse fraudulent transactions.", font: .footnoteRegular)),
                    style: .bordered)

                SubscriptionOnboardingCard(
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "checkmark.seal.fill")), size: .size40),
                        title: CardItemText("Setup 75% complete", font: .headline),
                        text: CardItemText("Some premium protections aren't active yet", font: .bodyRegular)),
                    style: .borderless) {
                        Button("Continue Setup") {}
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 16)
                    }

                SubscriptionOnboardingCard([
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "checkmark.circle.fill")), size: .size24),
                        title: CardItemText("DuckDuckGo VPN", font: .subheadRegular)),
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "circle")), size: .size24),
                        title: CardItemText("Personal Information Removal", font: .subheadRegular)),
                ], style: .borderless, padding: 0, contentInset: .init(horizontal: 16, vertical: 12)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "75%")
                            .font(.title.bold())
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Capsule()
                            .fill(Color(designSystemColor: .accentPrimary))
                            .frame(height: 8)
                    }
                    .padding(16)
                }

                SubscriptionOnboardingCard([
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "lock.shield.fill"))),
                        title: CardItemText("VPN", font: .headline),
                        text: CardItemText("An extra layer of online protection.", font: .footnoteRegular),
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "person.text.rectangle.fill"))),
                        title: CardItemText("Identity Theft Restoration", font: .headline),
                        text: CardItemText("If your identity is stolen, we'll help restore it.", font: .footnoteRegular),
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "sparkles"))),
                        title: CardItemText("Advanced AI Models", font: .headline),
                        text: CardItemText("Private conversations with 3rd-party AI chat models.", font: .footnoteRegular),
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                ], style: .borderless, padding: 0, contentInset: .init(horizontal: 16, vertical: 12))

                SubscriptionOnboardingCard([
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "brain")), size: .size24),
                        title: CardItemText("GPT-4o mini", font: .bodyRegular),
                        trailing: selection == 0 ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil),
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "cpu")), size: .size24),
                        title: CardItemText("Claude", font: .bodyRegular),
                        titleDetails: [CardItemText("· PLUS", font: .footnoteRegular)],
                        trailing: selection == 1 ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil),
                ], style: .borderless, padding: 0, contentInset: .init(horizontal: 16, vertical: 12), onSelect: { index in { selection = index } })
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
    }
}

#Preview("Rebranded / Light") {
    RebrandedPreview {
        SubscriptionOnboardingCardPreviewSamples()
    }
}

#Preview("Rebranded / Dark") {
    RebrandedPreview {
        SubscriptionOnboardingCardPreviewSamples()
    }
    .preferredColorScheme(.dark)
}

#Preview("Rebranded / Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingCardPreviewSamples()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
