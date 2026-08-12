//
//  UnifiedToggleInputModelPicker.swift
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import UIKit

struct UnifiedToggleInputModelPickerContent {
    struct Item: Identifiable {
        let id: String
        let name: String
        let subtitle: String?
        let provider: AIChatModel.ModelProvider
        let requiredTierBadgeText: String?

        var emphasizedName: String {
            name.split(separator: " ", maxSplits: 1).first.map(String.init) ?? name
        }

        var remainingName: String {
            let components = name.split(separator: " ", maxSplits: 1).map(String.init)
            return components.count > 1 ? " \(components[1])" : ""
        }
    }

    let itemsWithRecommendationLabel: [Item]
    let itemsWithoutRecommendationLabel: [Item]
    let gatedItems: [Item]
    let selectedModelID: String?
    let showsAvailableItemsSeparator: Bool
    let gatedSectionTitle: String

    init(models: [AIChatModel], selectedModelID: String?, userTier: AIChatUserTier) {
        let groupedModels = AIChatModelSectionBuilder.groupByAccess(models: models)
        let groupedAvailableModels = AIChatModelSectionBuilder.groupByRecommendationLabel(models: groupedModels.accessible)
        itemsWithRecommendationLabel = groupedAvailableModels.withLabel.map {
            Item(model: $0, allowsSubtitle: true)
        }
        itemsWithoutRecommendationLabel = groupedAvailableModels.withoutLabel.map {
            Item(model: $0, allowsSubtitle: true)
        }
        gatedItems = groupedModels.gated.map {
            Item(model: $0.model, allowsSubtitle: false, requiredTier: $0.requiredTier)
        }
        self.selectedModelID = selectedModelID
        showsAvailableItemsSeparator = Self.shouldShowAvailableItemsSeparator(
            hasItemsWithRecommendationLabel: !groupedAvailableModels.withLabel.isEmpty,
            hasItemsWithoutRecommendationLabel: !groupedAvailableModels.withoutLabel.isEmpty)
        gatedSectionTitle = userTier == .plus ? UserText.aiChatModelPickerAvailableWithPro : UserText.aiChatModelPickerTryFree
    }

    var availableItems: [Item] {
        itemsWithRecommendationLabel + itemsWithoutRecommendationLabel
    }

    var preferredHeight: CGFloat {
        let availableItemsHeight = availableItems.reduce(CGFloat.zero) { $0 + Self.rowHeight(for: $1) }
        let gatedItemsHeight = gatedItems.reduce(CGFloat.zero) { $0 + Self.rowHeight(for: $1) }
        let availableSectionSeparatorHeight = showsAvailableItemsSeparator ? Metrics.separatorHeight : 0
        let gatedSectionHeight = gatedItems.isEmpty ? 0 : Metrics.separatorHeight + Metrics.headerHeight
        return Metrics.verticalPadding * 2 + availableItemsHeight + availableSectionSeparatorHeight + gatedItemsHeight + gatedSectionHeight
    }

    private static func shouldShowAvailableItemsSeparator(
        hasItemsWithRecommendationLabel: Bool,
        hasItemsWithoutRecommendationLabel: Bool) -> Bool {
        hasItemsWithRecommendationLabel && hasItemsWithoutRecommendationLabel
    }

    private static func rowHeight(for item: Item) -> CGFloat {
        item.subtitle == nil ? Metrics.standardRowHeight : Metrics.subtitleRowHeight
    }
}

private extension UnifiedToggleInputModelPickerContent.Item {
    init(
        model: AIChatModel,
        allowsSubtitle: Bool,
        requiredTier: AIChatModelPublicAccessTier? = nil) {
        self.init(
            id: model.id,
            name: model.name,
            subtitle: allowsSubtitle ? model.label?.localizedText : nil,
            provider: model.provider,
            requiredTierBadgeText: requiredTier?.modelPickerBadgeText
        )
    }
}

private extension AIChatModelPublicAccessTier {
    var modelPickerBadgeText: String? {
        switch self {
        case .free:
            return nil
        case .plus:
            return UserText.aiChatPlusModelsSectionHeader.uppercased()
        case .pro:
            return UserText.aiChatProModelsSectionHeader.uppercased()
        }
    }
}

private extension UnifiedToggleInputModelPickerContent {
    enum Metrics {
        static let verticalPadding: CGFloat = 10
        static let separatorHeight: CGFloat = 21
        static let headerHeight: CGFloat = 35
        static let standardRowHeight: CGFloat = 40
        static let subtitleRowHeight: CGFloat = 60
    }
}

@MainActor
final class UnifiedToggleInputModelPickerPresenter: NSObject {
    private weak var presentedViewController: UIViewController?

    func present(
        content: UnifiedToggleInputModelPickerContent,
        from presentingViewController: UIViewController,
        sourceView: UIView,
        onSelect: @escaping (String) -> Void
    ) {
        guard presentedViewController == nil else { return }

        let height = preferredHeight(for: content, presentingViewController: presentingViewController)
        let rootView = UnifiedToggleInputModelPickerView(
            content: content,
            height: height,
            onSelect: { [weak self] modelID in
                self?.dismiss {
                    onSelect(modelID)
                }
            }
        )
        .presentationCornerRadiusIfAvailable(Metrics.cornerRadius)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.modalPresentationStyle = .popover
        hostingController.preferredContentSize = CGSize(width: Metrics.width, height: height)

        guard let popover = hostingController.popoverPresentationController else { return }
        popover.sourceView = sourceView
        popover.sourceRect = sourceView.bounds
        popover.permittedArrowDirections = []
        popover.backgroundColor = .clear
        popover.delegate = self

        presentingViewController.present(hostingController, animated: true)
        presentedViewController = hostingController
    }

    private func preferredHeight(
        for content: UnifiedToggleInputModelPickerContent,
        presentingViewController: UIViewController
    ) -> CGFloat {
        let window = presentingViewController.view.window
        let windowHeight = window?.bounds.height ?? presentingViewController.view.bounds.height
        let safeAreaInsets = window?.safeAreaInsets ?? presentingViewController.view.safeAreaInsets
        let availableHeight = windowHeight - safeAreaInsets.top - safeAreaInsets.bottom - Metrics.minimumVerticalMargin
        return max(1, min(content.preferredHeight, min(Metrics.maximumHeight, availableHeight)))
    }

    private func dismiss(completion: @escaping () -> Void) {
        guard let presentedViewController else {
            completion()
            return
        }

        self.presentedViewController = nil
        presentedViewController.dismiss(animated: true, completion: completion)
    }
}

extension UnifiedToggleInputModelPickerPresenter: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentedViewController = nil
    }
}

private extension UnifiedToggleInputModelPickerPresenter {
    enum Metrics {
        static let width: CGFloat = 270
        static let maximumHeight: CGFloat = 496
        static let minimumVerticalMargin: CGFloat = 48
        static let cornerRadius: CGFloat = 32
    }
}

private struct UnifiedToggleInputModelPickerView: View {
    let content: UnifiedToggleInputModelPickerContent
    let height: CGFloat
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(content.itemsWithRecommendationLabel) { item in
                    UnifiedToggleInputModelPickerRow(
                        item: item,
                        isSelected: content.selectedModelID == item.id,
                        action: { onSelect(item.id) }
                    )
                }

                if content.showsAvailableItemsSeparator {
                    separator
                }

                ForEach(content.itemsWithoutRecommendationLabel) { item in
                    UnifiedToggleInputModelPickerRow(
                        item: item,
                        isSelected: content.selectedModelID == item.id,
                        action: { onSelect(item.id) }
                    )
                }

                if !content.gatedItems.isEmpty {
                    separator
                    gatedModelsHeader

                    ForEach(content.gatedItems) { item in
                        UnifiedToggleInputModelPickerRow(
                            item: item,
                            isSelected: false,
                            action: { onSelect(item.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
        }
        .frame(width: Metrics.width, height: height, alignment: .top)
        .background(menuBackground)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityIdentifier("ModelPicker")
    }

    private var separator: some View {
        Color(designSystemColor: .lines)
            .frame(height: 1 / UIScreen.main.scale)
            .frame(height: Metrics.separatorHeight)
            .padding(.horizontal, Metrics.separatorHorizontalPadding)
            .accessibilityHidden(true)
    }

    private var gatedModelsHeader: some View {
        Text(content.gatedSectionTitle)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(designSystemColor: .textTertiary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.headerHorizontalPadding)
            .frame(height: Metrics.headerHeight)
    }

    @ViewBuilder
    private var menuBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.regularMaterial)
        }
    }
}

private extension UnifiedToggleInputModelPickerView {
    enum Metrics {
        static let width: CGFloat = 270
        static let cornerRadius: CGFloat = 32
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
        static let separatorHeight: CGFloat = 21
        static let separatorHorizontalPadding: CGFloat = 8
        static let headerHeight: CGFloat = 35
        static let headerHorizontalPadding: CGFloat = 8
    }
}

private struct UnifiedToggleInputModelPickerRow: View {
    let item: UnifiedToggleInputModelPickerContent.Item
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ModelPicker.\(item.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .frame(height: item.subtitle == nil ? Metrics.standardHeight : Metrics.subtitleHeight)
    }

    private var rowContent: some View {
        HStack(spacing: Metrics.itemSpacing) {
            HStack(spacing: Metrics.leadingSpacing) {
                providerIcon

                VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                    modelName

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .daxFootnoteRegular()
                            .foregroundStyle(Color(designSystemColor: .textSecondary))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            trailingContent
        }
        .padding(.leading, Metrics.leadingPadding)
        .padding(.trailing, Metrics.trailingPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var providerIcon: some View {
        Image(uiImage: icon(for: item.provider))
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(Color(designSystemColor: .icons))
            .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            .accessibilityHidden(true)
    }

    private var modelName: some View {
        (Text(verbatim: item.emphasizedName)
            .font(Font(UIFont.daxBodyBold()))
        + Text(verbatim: item.remainingName)
            .font(Font(UIFont.daxBodyRegular())))
            .foregroundStyle(Color(designSystemColor: .textPrimary))
            .lineLimit(1)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let requiredTierBadgeText = item.requiredTierBadgeText {
            Text(requiredTierBadgeText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(designSystemColor: .textSecondary))
                .lineLimit(1)
                .frame(height: Metrics.trailingContentHeight)
        } else {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(designSystemColor: .textPrimary))
                .frame(width: Metrics.checkmarkWidth, height: Metrics.trailingContentHeight)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
    }

    private func icon(for provider: AIChatModel.ModelProvider) -> UIImage {
        switch provider {
        case .openAI:
            return DesignSystemImages.Glyphs.Size16.aiModelOpenAI
        case .meta:
            return DesignSystemImages.Glyphs.Size16.aiModelLlama
        case .anthropic:
            return DesignSystemImages.Glyphs.Size16.aiModelClaude
        case .mistral:
            return DesignSystemImages.Glyphs.Size16.aiModelMistral
        case .oss, .unknown:
            return DesignSystemImages.Glyphs.Size16.aiModelOSS
        }
    }
}

private extension UnifiedToggleInputModelPickerRow {
    enum Metrics {
        static let standardHeight: CGFloat = 40
        static let subtitleHeight: CGFloat = 60
        static let checkmarkWidth: CGFloat = 24
        static let trailingContentHeight: CGFloat = 22
        static let itemSpacing: CGFloat = 6
        static let leadingSpacing: CGFloat = 8
        static let textSpacing: CGFloat = 2
        static let leadingPadding: CGFloat = 6
        static let trailingPadding: CGFloat = 8
        static let iconSize: CGFloat = 16
    }
}

private extension View {
    @ViewBuilder
    func presentationCornerRadiusIfAvailable(_ cornerRadius: CGFloat) -> some View {
        if #available(iOS 16.4, *) {
            presentationCornerRadius(cornerRadius)
        } else {
            self
        }
    }
}
