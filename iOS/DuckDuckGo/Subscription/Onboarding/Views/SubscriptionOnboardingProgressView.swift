//
//  SubscriptionOnboardingProgressView.swift
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

/// The completion progress card: a percentage read-out with a green progress bar in the header (with the
/// card's automatic divider below it), then the activation checklist — a filled check for completed
/// items, an outlined circle with a chevron affordance for the ones still to do. The percentage and items
/// are supplied by the caller, so the same card renders the intermediate and complete states. Tapping an
/// incomplete row (e.g. Personal Information Removal) is handled by the caller.
struct SubscriptionOnboardingProgressView: View {
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

private extension SubscriptionOnboardingProgressView {
    var progressHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(clampedPercentage)%")
                // No dax token at this display size
                .font(.system(size: Metrics.percentageFontSize, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Text(verbatim: UserText.subscriptionOnboardingProgressCompletedLabel)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textSecondary))

            SubscriptionOnboardingProgressBar(percentage: clampedPercentage)
                .padding(.top, Metrics.progressBarTopSpacing)
        }
        .padding(Metrics.headerPadding)
    }

    // TODO|htang: remove once percentage clamping is centralized in SubscriptionOnboardingFlowViewModel.
    var clampedPercentage: Int {
        min(max(percentage, 0), 100)
    }

    /// The tap action for the row at `index`, or `nil` when it isn't selectable — only an incomplete PIR row is.
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

    /// Completed rows show the animated check
    func visual(for item: SubscriptionOnboardingChecklistItem) -> Graphic {
        if completedItems.contains(item) {
            // TODO|htang: production host must inject a graphicLottieRenderer that honors .frozenAtEnd (Reduce Motion); only a preview renderer exists so far.
            return .lottie(name: "check-color")
        }
        let glyph = item == .pir
            ? DesignSystemImages.Glyphs.Size24.profileBlocked
            : DesignSystemImages.Glyphs.Size24.checkCircle
        return .image(Image(uiImage: glyph))
    }

    /// Only an incomplete PIR row is interactive — so only it is tappable and shows a chevron.
    func isSelectable(_ item: SubscriptionOnboardingChecklistItem) -> Bool {
        item == .pir && !completedItems.contains(item)
    }
}

// MARK: - Progress Bar

/// The completion screen's progress bar: a solid green fill on a light-grey track. 
private struct SubscriptionOnboardingProgressBar: View {
    private enum Metrics {
        static let trackHeight: CGFloat = 12
    }

    /// The completion percentage, expected in `0...100` (the caller clamps it).
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

import Lottie

private struct SubscriptionOnboardingProgressViewPreview: View {
    let pirComplete: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SubscriptionOnboardingProgressView(
                    percentage: 75,
                    items: Self.items,
                    completedItems: pirComplete ? Set(Self.items) : Self.completedExceptPIR,
                    onSelect: { _ in })
                SubscriptionOnboardingProgressView(
                    percentage: 100,
                    items: Self.items,
                    completedItems: Set(Self.items))
                SubscriptionOnboardingProgressView(
                    percentage: 75,
                    items: Self.items,
                    completedItems: Self.completedExceptVPN)
            }
            .padding()
        }
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
        .graphicLottieRenderer(Self.previewLottieRenderer)
    }

    private static let items: [SubscriptionOnboardingChecklistItem] = [.vpn, .idtr, .duckAI, .pir]
    private static let completedExceptPIR: Set<SubscriptionOnboardingChecklistItem> = [.vpn, .idtr, .duckAI]
    private static let completedExceptVPN: Set<SubscriptionOnboardingChecklistItem> = [.idtr, .duckAI, .pir]

    /// Renders the completed-check Lottie (`check-color`) in previews; at runtime the app injects its
    /// own renderer.
    private static let previewLottieRenderer = GraphicLottieRenderer { name, _ in
        AnyView(
            Lottie.LottieView(animation: .named(name))
                .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
        )
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(pirComplete: false)
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(pirComplete: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingProgressViewPreview(pirComplete: false)
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
