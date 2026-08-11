//
//  SubscriptionOnboardingProgressCardView.swift
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
import UIComponents

struct SubscriptionOnboardingProgressCardView: View {
    private enum Metrics {
        static let headerPadding: CGFloat = 24
        static let percentageFontSize: CGFloat = 34
        static let progressBarTopSpacing: CGFloat = 8
        static let contentInsetHorizontal: CGFloat = 24
        static let contentInsetVertical: CGFloat = 16
        static let iconTextSpacing: CGFloat = 14
    }

    private let percentage: Int
    private let items: [SubscriptionOnboardingChecklistItem]
    private let completedItems: Set<SubscriptionOnboardingChecklistItem>
    private let onSelect: ((SubscriptionOnboardingChecklistItem) -> Void)?

    init(percentage: Int,
         items: [SubscriptionOnboardingChecklistItem],
         completedItems: Set<SubscriptionOnboardingChecklistItem>,
         onSelect: ((SubscriptionOnboardingChecklistItem) -> Void)? = nil) {
        self.percentage = percentage
        self.items = items
        self.completedItems = completedItems
        self.onSelect = onSelect
    }

    var body: some View {
        SubscriptionOnboardingCard(
            checklistItems,
            style: .borderless,
            padding: 0,
            contentInset: .init(horizontal: Metrics.contentInsetHorizontal, vertical: Metrics.contentInsetVertical),
            onSelect: rowSelectAction,
            header: { progressHeader })
        .foregroundColor(Color(designSystemColor: .textPrimary))
    }
}

// MARK: - Layout

private extension SubscriptionOnboardingProgressCardView {
    var progressHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(percentage)%")
                // No dax token at this display size
                .font(.system(size: Metrics.percentageFontSize, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Text(verbatim: UserText.subscriptionOnboardingProgressCompletedLabel)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textSecondary))

            SubscriptionOnboardingProgressBar(percentage: percentage)
                .padding(.top, Metrics.progressBarTopSpacing)
        }
        .padding(Metrics.headerPadding)
    }

    var rowSelectAction: (Int) -> (() -> Void)? {
        guard let onSelect else { return { _ in nil } }
        return CardItemList.selectAction(over: items, where: isSelectable) { onSelect($0) }
    }

    var checklistItems: [CardItem] {
        items.map { item in
            CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: visual(for: item), size: .size24, spacing: Metrics.iconTextSpacing),
                title: CardItemText(item.title, font: .bodyRegular),
                trailing: isSelectable(item) ? .chevron(Color(designSystemColor: .iconsTertiary)) : nil,
                accessibilityValue: completedItems.contains(item)
                    ? UserText.subscriptionOnboardingProgressRowCompletedValue
                    : UserText.subscriptionOnboardingProgressRowNotCompletedValue)
        }
    }

    /// Completed rows show the animated check.
    func visual(for item: SubscriptionOnboardingChecklistItem) -> Graphic {
        if completedItems.contains(item) {
            return .lottie(name: "check-color")
        }
        let glyph = item == .pir
            ? DesignSystemImages.Glyphs.Size24.profileBlocked
            : DesignSystemImages.Glyphs.Size24.checkCircle
        return .image(Image(uiImage: glyph))
    }

    /// Only an incomplete PIR row is interactive, otherwise the row does nothing.
    func isSelectable(_ item: SubscriptionOnboardingChecklistItem) -> Bool {
        onSelect != nil && item == .pir && !completedItems.contains(item)
    }
}

// MARK: - Progress Bar

private struct SubscriptionOnboardingProgressBar: View {
    private enum Metrics {
        static let trackHeight: CGFloat = 12
    }

    /// The completion percentage, bounded to `0...100`
    let percentage: Int

    var body: some View {
        Capsule()
            .fill(Color(designSystemColor: .controlsFillPrimary))
            .frame(height: Metrics.trackHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(designSystemColor: .alertGreen))
                        .frame(width: fraction * proxy.size.width)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(UserText.subscriptionOnboardingProgressAccessibilityLabel)
            .accessibilityValue(String(format: UserText.subscriptionOnboardingProgressAccessibilityValue, percentage))
    }
}

private extension SubscriptionOnboardingProgressBar {
    var fraction: Double {
        Double(percentage) / 100
    }
}

#if DEBUG

private struct SubscriptionOnboardingProgressCardViewPreview: View {
    let pirComplete: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SubscriptionOnboardingProgressCardView(
                    percentage: 80,
                    items: Self.items,
                    completedItems: pirComplete ? Set(Self.items) : Self.completedExceptPIR,
                    onSelect: { _ in })
                SubscriptionOnboardingProgressCardView(
                    percentage: 100,
                    items: Self.items,
                    completedItems: Set(Self.items))
                SubscriptionOnboardingProgressCardView(
                    percentage: 80,
                    items: Self.items,
                    completedItems: Self.completedExceptVPN)
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
        .graphicLottieRenderer(.app)
    }

    private static let items = SubscriptionOnboardingChecklistItem.allCases
    private static let completedExceptPIR: Set<SubscriptionOnboardingChecklistItem> = [.vpn, .widget, .idtr, .duckAI]
    private static let completedExceptVPN: Set<SubscriptionOnboardingChecklistItem> = [.widget, .idtr, .duckAI, .pir]
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingProgressCardViewPreview(pirComplete: false)
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingProgressCardViewPreview(pirComplete: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingProgressCardViewPreview(pirComplete: false)
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
