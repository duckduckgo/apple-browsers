//
//  UnifiedToggleInputModelPickerPrototype.swift
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

// Tracer bullet: compare a reusable custom model picker with the native UIMenu on the existing model chip.

struct UnifiedToggleInputModelPickerContent {

    struct Section: Identifiable {
        let id: String
        let callToAction: CallToAction?
        let items: [Item]
    }

    struct CallToAction {
        let prefix: String
        let actionTitle: String
        let flowType: UpsellFlowType
    }

    struct Item: Identifiable {
        let id: String
        let name: String
        let subtitle: String?
        let provider: AIChatModel.ModelProvider
        let badge: Badge?
        let showsInfo: Bool
        let isDimmed: Bool
    }

    enum Badge: String {
        case plus = "PLUS"
        case pro = "PRO"
    }

    let sections: [Section]
    let initiallySelectedModelID: String
}

struct UnifiedToggleInputModelPickerView: View {

    let content: UnifiedToggleInputModelPickerContent
    @Binding var selectedModelID: String
    let onSelect: (String) -> Void
    let onInfo: (String) -> Void
    let onCallToAction: (UpsellFlowType) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.itemSpacing) {
                ForEach(content.sections) { section in
                    if let callToAction = section.callToAction {
                        CallToActionView(
                            callToAction: callToAction,
                            action: { onCallToAction(callToAction.flowType) }
                        )
                    }

                    ForEach(section.items) { item in
                        ModelRow(
                            item: item,
                            isSelected: selectedModelID == item.id,
                            onSelect: {
                                selectedModelID = item.id
                                onSelect(item.id)
                            },
                            onInfo: { onInfo(item.id) }
                        )
                    }
                }
            }
            .padding(.vertical, Metrics.verticalPadding)
        }
        .background(Color(designSystemColor: .background))
    }
}

private extension UnifiedToggleInputModelPickerView {

    enum Metrics {
        static let itemSpacing: CGFloat = 4
        static let verticalPadding: CGFloat = 8
    }
}

private struct ModelRow: View {

    let item: UnifiedToggleInputModelPickerContent.Item
    let isSelected: Bool
    let onSelect: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: Metrics.rowContentSpacing) {
            Button(action: onSelect) {
                HStack(spacing: 0) {
                    HStack(spacing: Metrics.iconTextSpacing) {
                        providerIcon

                        VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                            modelName

                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .daxSubheadRegular()
                                    .foregroundStyle(Color(designSystemColor: .textSecondary))
                            }
                        }
                    }
                    .opacity(item.isDimmed ? Metrics.dimmedOpacity : 1)

                    Spacer(minLength: Metrics.minimumTrailingSpacing)

                    if let badge = item.badge {
                        Text(badge.rawValue)
                            .kerning(Metrics.badgeTracking)
                            .daxCaptionBold()
                            .foregroundStyle(Color(designSystemColor: .textTertiary))
                            .padding(.horizontal, Metrics.badgeHorizontalPadding)
                            .frame(minHeight: Metrics.badgeHeight)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.showsInfo {
                Button(action: onInfo) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size12.info)
                        .renderingMode(.template)
                        .foregroundStyle(Color(designSystemColor: .iconsTertiary))
                        .frame(width: Metrics.infoIconSize, height: Metrics.infoIconSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Model information")
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: item.subtitle == nil ? Metrics.rowHeight : Metrics.rowWithSubtitleHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Metrics.selectionCornerRadius)
                    .fill(Color(designSystemColor: .controlsFillSecondary))
            }
        }
        .padding(.horizontal, Metrics.outerHorizontalPadding)
    }

    private var providerIcon: some View {
        Image(uiImage: icon(for: item.provider))
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(Color(designSystemColor: .icons))
            .frame(width: Metrics.iconSize, height: Metrics.iconSize)
    }

    private var modelName: some View {
        let components = item.name.split(separator: " ", maxSplits: 1).map(String.init)

        return HStack(spacing: Metrics.nameSpacing) {
            Text(components.first ?? item.name)
                .daxSubheadSemibold()
                .foregroundStyle(Color(designSystemColor: .textPrimary))

            if components.count > 1 {
                Text(components[1])
                    .daxSubheadRegular()
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
        }
        .lineLimit(1)
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
        case .oss:
            return DesignSystemImages.Glyphs.Size16.aiModelOSS
        case .unknown:
            return DesignSystemImages.Glyphs.Size16.aiModelOSS
        }
    }
}

private extension ModelRow {

    enum Metrics {
        static let rowHeight: CGFloat = 36
        static let rowWithSubtitleHeight: CGFloat = 50
        static let iconSize: CGFloat = 16
        static let iconTextSpacing: CGFloat = 12
        static let rowContentSpacing: CGFloat = 8
        static let textSpacing: CGFloat = 1
        static let nameSpacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 16
        static let outerHorizontalPadding: CGFloat = 8
        static let minimumTrailingSpacing: CGFloat = 8
        static let infoIconSize: CGFloat = 12
        static let badgeHorizontalPadding: CGFloat = 4
        static let badgeHeight: CGFloat = 20
        static let badgeTracking: CGFloat = 0.5
        static let selectionCornerRadius: CGFloat = 16
        static let dimmedOpacity = 0.3
    }
}

private struct CallToActionView: View {

    let callToAction: UnifiedToggleInputModelPickerContent.CallToAction
    let action: () -> Void

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Text(callToAction.prefix)
                .daxSubheadRegular()
                .foregroundStyle(Color(designSystemColor: .textSecondary))

            Button(action: action) {
                Text(callToAction.actionTitle)
                    .daxSubheadRegular()
                    .foregroundStyle(Color(designSystemColor: .accentPrimary))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.top, Metrics.topPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .frame(minHeight: Metrics.height)
    }
}

private extension CallToActionView {

    enum Metrics {
        static let spacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let bottomPadding: CGFloat = 8
        static let height: CGFloat = 49
    }
}

#if DEBUG || ALPHA

enum UnifiedToggleInputModelPickerPrototypeLevel: String, CaseIterable {
    case free = "Free"
    case plus = "Plus"
    case pro = "Pro"
}

@MainActor
final class UnifiedToggleInputModelPickerPrototypePresenter: NSObject {

    private weak var presentedViewController: UIViewController?

    func present(from presentingViewController: UIViewController,
                 sourceView: UIView,
                 onSelect: @escaping (String) -> Void,
                 onInfo: @escaping (String) -> Void,
                 onCallToAction: @escaping (UpsellFlowType) -> Void) {
        guard presentedViewController == nil else { return }

        let rootView = UnifiedToggleInputModelPickerPrototypeHost(
            onSelect: onSelect,
            onInfo: onInfo,
            onCallToAction: { [weak self] flowType in
                self?.dismiss {
                    onCallToAction(flowType)
                }
            }
        )
        .presentationCornerRadiusIfAvailable(Metrics.cornerRadius)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = UIColor(designSystemColor: .background)
        hostingController.modalPresentationStyle = .popover

        let availableHeight = presentingViewController.view.window?.bounds.height
            ?? presentingViewController.view.bounds.height
        hostingController.preferredContentSize = CGSize(
            width: Metrics.width,
            height: min(Metrics.height, availableHeight - Metrics.minimumVerticalMargin)
        )

        guard let popover = hostingController.popoverPresentationController else { return }
        popover.sourceView = sourceView
        popover.sourceRect = sourceView.bounds
        popover.permittedArrowDirections = [.up, .down]
        // popover.permittedArrowDirections = []
        popover.backgroundColor = UIColor(designSystemColor: .background)
        popover.delegate = self

        presentingViewController.present(hostingController, animated: true)
        presentedViewController = hostingController
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

@MainActor
final class UnifiedToggleInputModelPickerPrototypeV2Presenter: NSObject {

    private weak var presentedViewController: UIViewController?

    func present(from presentingViewController: UIViewController,
                 sourceView: UIView,
                 onSelect: @escaping (String) -> Void,
                 onCallToAction: @escaping (UpsellFlowType) -> Void) {
        guard presentedViewController == nil else { return }

        let rootView = UnifiedToggleInputModelPickerPrototypeV2View(
            content: .free,
            onSelect: onSelect,
            onCallToAction: { [weak self] flowType in
                self?.dismiss {
                    onCallToAction(flowType)
                }
            }
        )
        .presentationCornerRadiusIfAvailable(Metrics.cornerRadius)
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.modalPresentationStyle = .popover
        hostingController.preferredContentSize = CGSize(width: Metrics.width, height: Metrics.height)

        guard let popover = hostingController.popoverPresentationController else { return }
        popover.sourceView = sourceView
        popover.sourceRect = sourceView.bounds
        popover.permittedArrowDirections = []
        popover.backgroundColor = .clear
        popover.delegate = self

        presentingViewController.present(hostingController, animated: true)
        presentedViewController = hostingController
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

private struct UnifiedToggleInputModelPickerPrototypeV2Content {

    struct Item: Identifiable {
        let id: String
        let emphasizedName: String
        let remainingName: String
        let subtitle: String?
        let provider: AIChatModel.ModelProvider
        let isEnabled: Bool
    }

    let availableItems: [Item]
    let advancedItems: [Item]
    let initiallySelectedModelID: String

    static let free = UnifiedToggleInputModelPickerPrototypeV2Content(
        availableItems: [
            item("gpt-5.4-nano", emphasizedName: "GPT-5.4", remainingName: " nano", subtitle: "Best for everyday use", provider: .openAI),
            item("gpt-5-mini", emphasizedName: "GPT-5", remainingName: " mini", subtitle: "Solid but uses limits faster", provider: .openAI),
            item("claude-haiku-3.5", emphasizedName: "Claude", remainingName: " Haiku 3.5", subtitle: "Solid but uses limits faster", provider: .anthropic),
            item("mistral-small-3", emphasizedName: "Mistral", remainingName: " Small 3", provider: .mistral),
            item("gpt-oss-120b", emphasizedName: "gpt-oss", remainingName: " 120B", provider: .oss),
            item("gemma-4-31b", emphasizedName: "Gemma 4", remainingName: " 31B", provider: .oss),
        ],
        advancedItems: [
            item("gpt-5.4", emphasizedName: "", remainingName: "GPT-5.4", provider: .openAI, isEnabled: false),
            item("claude-sonnet-4.6", emphasizedName: "", remainingName: "Claude Sonnet 4.6", provider: .openAI, isEnabled: false),
            item("claude-opus-4.8", emphasizedName: "", remainingName: "Claude Opus 4.8", provider: .anthropic, isEnabled: false),
        ],
        initiallySelectedModelID: "gpt-5.4-nano"
    )

    private static func item(_ id: String,
                             emphasizedName: String,
                             remainingName: String,
                             subtitle: String? = nil,
                             provider: AIChatModel.ModelProvider,
                             isEnabled: Bool = true) -> Item {
        .init(
            id: id,
            emphasizedName: emphasizedName,
            remainingName: remainingName,
            subtitle: subtitle,
            provider: provider,
            isEnabled: isEnabled
        )
    }
}

private struct UnifiedToggleInputModelPickerPrototypeV2View: View {

    let content: UnifiedToggleInputModelPickerPrototypeV2Content
    let onSelect: (String) -> Void
    let onCallToAction: (UpsellFlowType) -> Void

    @State private var selectedModelID: String

    init(content: UnifiedToggleInputModelPickerPrototypeV2Content,
         onSelect: @escaping (String) -> Void,
         onCallToAction: @escaping (UpsellFlowType) -> Void) {
        self.content = content
        self.onSelect = onSelect
        self.onCallToAction = onCallToAction
        _selectedModelID = State(initialValue: content.initiallySelectedModelID)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(content.availableItems) { item in
                UnifiedToggleInputModelPickerPrototypeV2Row(
                    item: item,
                    isSelected: selectedModelID == item.id,
                    action: {
                        selectedModelID = item.id
                        onSelect(item.id)
                    }
                )
            }

            separator
            advancedModelsHeader

            ForEach(content.advancedItems) { item in
                UnifiedToggleInputModelPickerPrototypeV2Row(
                    item: item,
                    isSelected: false,
                    action: {
                        onCallToAction(.purchase)
                    }
                )
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(width: Metrics.width, height: Metrics.height, alignment: .top)
        .background(menuBackground)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityIdentifier("ModelPickerPrototypeV2")
    }

    private var separator: some View {
        Color(designSystemColor: .lines)
            .frame(height: 1 / UIScreen.main.scale)
            .frame(height: Metrics.separatorHeight)
            .padding(.horizontal, Metrics.separatorHorizontalPadding)
            .accessibilityHidden(true)
    }

    private var advancedModelsHeader: some View {
        HStack(spacing: Metrics.headerSpacing) {
            Text(verbatim: "Advanced Models")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(designSystemColor: .textTertiary))

            Spacer(minLength: 0)

            Button {
                onCallToAction(.purchase)
            } label: {
                Text(verbatim: "TRY FOR FREE")
                    .daxCaptionBold()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .padding(.horizontal, Metrics.callToActionHorizontalPadding)
                    .frame(height: Metrics.callToActionHeight)
                    .background(RebrandingColor.Pollen.pollen30, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ModelPickerPrototypeV2TryForFreeButton")
        }
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

private extension UnifiedToggleInputModelPickerPrototypeV2View {

    enum Metrics {
        static let width: CGFloat = 270
        static let height: CGFloat = 496
        static let cornerRadius: CGFloat = 32
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 10
        static let separatorHeight: CGFloat = 21
        static let separatorHorizontalPadding: CGFloat = 8
        static let headerHeight: CGFloat = 35
        static let headerHorizontalPadding: CGFloat = 8
        static let headerSpacing: CGFloat = 8
        static let callToActionHorizontalPadding: CGFloat = 8
        static let callToActionHeight: CGFloat = 24
    }
}

private struct UnifiedToggleInputModelPickerPrototypeV2Row: View {

    let item: UnifiedToggleInputModelPickerPrototypeV2Content.Item
    let isSelected: Bool
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ModelPickerPrototypeV2.\(item.id)")
            } else {
                rowContent
                    .accessibilityElement(children: .combine)
            }
        }
        .opacity(item.isEnabled ? 1 : Metrics.disabledOpacity)
        .frame(height: item.subtitle == nil ? Metrics.standardHeight : Metrics.subtitleHeight)
    }

    private var rowContent: some View {
        HStack(spacing: Metrics.itemSpacing) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(designSystemColor: .textPrimary))
                .frame(width: Metrics.selectionWidth, height: Metrics.selectionHeight)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)

            HStack(spacing: Metrics.leadingSpacing) {
                providerIcon

                VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                    modelName

                    if let subtitle = item.subtitle {
                        Text(verbatim: subtitle)
                            .daxFootnoteRegular()
                            .foregroundStyle(Color(designSystemColor: .textSecondary))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

private extension UnifiedToggleInputModelPickerPrototypeV2Row {

    enum Metrics {
        static let standardHeight: CGFloat = 40
        static let subtitleHeight: CGFloat = 60
        static let selectionWidth: CGFloat = 24
        static let selectionHeight: CGFloat = 22
        static let itemSpacing: CGFloat = 6
        static let leadingSpacing: CGFloat = 8
        static let textSpacing: CGFloat = 2
        static let leadingPadding: CGFloat = 6
        static let trailingPadding: CGFloat = 8
        static let iconSize: CGFloat = 16
        static let disabledOpacity = 0.3
    }
}

@MainActor
final class UnifiedToggleInputSubscriptionUpsellPrototypePresenter {

    private weak var presentedViewController: UIViewController?

    func present(from presentingViewController: UIViewController,
                 onSubscribe: @escaping () -> Void,
                 onHaveSubscription: @escaping () -> Void) {
        guard presentedViewController == nil else { return }

        let rootView = UnifiedToggleInputSubscriptionUpsellPrototypeView(
            onSubscribe: { [weak self] in
                self?.dismiss(completion: onSubscribe)
            },
            onHaveSubscription: { [weak self] in
                self?.dismiss(completion: onHaveSubscription)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve

        presentingViewController.present(hostingController, animated: true)
        presentedViewController = hostingController
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        guard let presentedViewController else {
            completion?()
            return
        }

        self.presentedViewController = nil
        presentedViewController.dismiss(animated: true, completion: completion)
    }
}

private struct UnifiedToggleInputSubscriptionUpsellPrototypeView: View {

    let onSubscribe: () -> Void
    let onHaveSubscription: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(designSystemColor: .decorationTertiary)
                .ignoresSafeArea()

            alertCard
                .padding(.horizontal, Metrics.screenHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var alertCard: some View {
        if #available(iOS 26.0, *) {
            alertContent
                .frame(maxWidth: Metrics.cardWidth)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                )
        } else {
            alertContent
                .frame(maxWidth: Metrics.cardWidth)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                )
        }
    }

    private var alertContent: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                Image(uiImage: DesignSystemImages.Color.Size96.duckAISubscription)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                    .accessibilityHidden(true)

                Text(verbatim: "Upgrade Duck.ai with a DuckDuckGo subscription")
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: """
                    Get access to advanced AI models in Duck.ai by subscribing to DuckDuckGo, \
                    which also includes our VPN and other premium privacy protections.
                    """)
                    .daxBodyRegular()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.textHorizontalPadding)
            .padding(.top, Metrics.textTopPadding)
            .padding(.bottom, Metrics.textBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Metrics.contentSpacing) {
                Button(action: onSubscribe) {
                    Text(verbatim: "Subscribe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SubscriptionUpsellButtonStyle(appearance: .primary))
                .accessibilityIdentifier("SubscriptionUpsellSubscribeButton")

                Button(action: onHaveSubscription) {
                    Text(verbatim: "I Have a Subscription")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SubscriptionUpsellButtonStyle(appearance: .secondary))
                .accessibilityIdentifier("SubscriptionUpsellHaveSubscriptionButton")

                Button(action: onDismiss) {
                    Text(verbatim: "Not Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SubscriptionUpsellButtonStyle(appearance: .cancel))
                .accessibilityIdentifier("SubscriptionUpsellNotNowButton")
            }
        }
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("SubscriptionUpsellAlert")
    }
}

private extension UnifiedToggleInputSubscriptionUpsellPrototypeView {

    enum Metrics {
        static let cardWidth: CGFloat = 338
        static let cardCornerRadius: CGFloat = 34
        static let cardPadding: CGFloat = 14
        static let screenHorizontalPadding: CGFloat = 32
        static let contentSpacing: CGFloat = 10
        static let textHorizontalPadding: CGFloat = 8
        static let textTopPadding: CGFloat = 8
        static let textBottomPadding: CGFloat = 24
        static let imageSize: CGFloat = 72
    }
}

private struct SubscriptionUpsellButtonStyle: ButtonStyle {

    enum Appearance {
        case primary
        case secondary
        case cancel
    }

    let appearance: Appearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.height)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }

    private var foregroundColor: Color {
        switch appearance {
        case .primary:
            return Color(designSystemColor: .accentContentPrimary)
        case .secondary, .cancel:
            return Color(designSystemColor: .textPrimary)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch appearance {
        case .primary:
            return Color(designSystemColor: isPressed ? .accentTertiary : .accentPrimary)
        case .secondary:
            return Color(designSystemColor: isPressed ? .controlsFillTertiary : .controlsFillSecondary)
        case .cancel:
            return Color(designSystemColor: isPressed ? .decorationTertiary : .decorationSecondary)
        }
    }
}

private extension SubscriptionUpsellButtonStyle {

    enum Metrics {
        static let height: CGFloat = 48
    }
}

extension UnifiedToggleInputModelPickerPrototypePresenter: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentedViewController = nil
    }
}

extension UnifiedToggleInputModelPickerPrototypeV2Presenter: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentedViewController = nil
    }
}

private extension UnifiedToggleInputModelPickerPrototypeV2Presenter {

    enum Metrics {
        static let width: CGFloat = 270
        static let height: CGFloat = 496
        static let cornerRadius: CGFloat = 32
    }
}

private extension UnifiedToggleInputModelPickerPrototypePresenter {

    enum Metrics {
        static let width: CGFloat = 290
        static let height: CGFloat = 600
        static let cornerRadius: CGFloat = 48
        static let minimumVerticalMargin: CGFloat = 48
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

private struct UnifiedToggleInputModelPickerPrototypeHost: View {

    @State private var level = UnifiedToggleInputModelPickerPrototypeLevel.free
    @State private var selectedModelID = UnifiedToggleInputModelPickerPrototypeFixtures.content(for: .free).initiallySelectedModelID

    let onSelect: (String) -> Void
    let onInfo: (String) -> Void
    let onCallToAction: (UpsellFlowType) -> Void

    private var content: UnifiedToggleInputModelPickerContent {
        UnifiedToggleInputModelPickerPrototypeFixtures.content(for: level)
    }

    var body: some View {
        VStack(spacing: 0) {
            UnifiedToggleInputModelPickerView(
                content: content,
                selectedModelID: $selectedModelID,
                onSelect: onSelect,
                onInfo: onInfo,
                onCallToAction: onCallToAction
            )

            Divider()

            HStack(spacing: Metrics.controlSpacing) {
                Text("Prototype")
                    .daxCaption1()
                    .foregroundStyle(Color(designSystemColor: .textSecondary))

                ForEach(UnifiedToggleInputModelPickerPrototypeLevel.allCases, id: \.self) { level in
                    Button {
                        self.level = level
                        selectedModelID = UnifiedToggleInputModelPickerPrototypeFixtures.content(for: level).initiallySelectedModelID
                    } label: {
                        Text(level.rawValue)
                            .daxCaption1()
                            .foregroundStyle(Color(designSystemColor: .textPrimary))
                            .padding(.horizontal, Metrics.levelHorizontalPadding)
                            .padding(.vertical, Metrics.levelVerticalPadding)
                            .background {
                                if self.level == level {
                                    Capsule()
                                        .fill(Color(designSystemColor: .controlsFillPrimary))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Metrics.controlPadding)
            .background(Color(designSystemColor: .surfaceTertiary))
        }
    }
}

private extension UnifiedToggleInputModelPickerPrototypeHost {

    enum Metrics {
        static let controlSpacing: CGFloat = 4
        static let controlPadding: CGFloat = 8
        static let levelHorizontalPadding: CGFloat = 8
        static let levelVerticalPadding: CGFloat = 5
    }
}

private enum UnifiedToggleInputModelPickerPrototypeFixtures {

    static func content(for level: UnifiedToggleInputModelPickerPrototypeLevel) -> UnifiedToggleInputModelPickerContent {
        switch level {
        case .free:
            return freeContent
        case .plus:
            return plusContent
        case .pro:
            return proContent
        }
    }

    private static let freeContent = UnifiedToggleInputModelPickerContent(
        sections: [
            .init(id: "free", callToAction: nil, items: [
                item("gpt-5.4-nano", "GPT-5.4 Nano", subtitle: "Everyday use", provider: .openAI),
                item("gpt-5.4-mini", "GPT-5.4 Mini", subtitle: "Uses limits faster", provider: .openAI),
                item("gpt-oss-120b", "gpt-oss 120B", subtitle: "Extra privacy", provider: .oss, showsInfo: true),
                item("claude-haiku-4.5", "Claude Haiku 4.5", provider: .anthropic),
                item("mistral-small-4", "Mistral Small 4", provider: .mistral),
                item("llama-4-scout", "Llama 4 Scout", provider: .meta),
            ]),
            .init(
                id: "subscriber-exclusive",
                callToAction: .init(prefix: "Subscriber exclusive.", actionTitle: "Try for free", flowType: .purchase),
                items: [
                    item("gpt-5.2", "GPT-5.2", provider: .openAI, badge: .plus, isDimmed: true),
                    item("gpt-5.5", "GPT-5.5", provider: .openAI, badge: .pro, isDimmed: true),
                    item("claude-sonnet-4.5", "Claude Sonnet 4.5", provider: .anthropic, badge: .plus, isDimmed: true),
                    item("claude-opus-4.6", "Claude Opus 4.6", provider: .anthropic, badge: .pro, isDimmed: true),
                    item("llama-4-maverick", "Llama 4 Maverick", provider: .meta, badge: .plus, isDimmed: true),
                ]
            ),
        ],
        initiallySelectedModelID: "gpt-5.4-nano"
    )

    private static let plusContent = UnifiedToggleInputModelPickerContent(
        sections: [
            .init(id: "plus", callToAction: nil, items: [
                item("gpt-5.4", "GPT-5.4", subtitle: "Everyday use", provider: .openAI, badge: .plus),
                item("claude-sonnet-4.5", "Claude Sonnet 4.5", subtitle: "Uses limits faster", provider: .anthropic, badge: .plus),
                item("gpt-oss-120b", "gpt-oss 120B", subtitle: "Extra privacy", provider: .oss, showsInfo: true),
                item("claude-haiku-4.5", "Claude Haiku 4.5", provider: .anthropic),
                item("mistral-small-4", "Mistral Small 4", provider: .mistral),
                item("llama-4-scout", "Llama 4 Scout", provider: .meta),
                item("gpt-5.4-nano", "GPT-5.4 Nano", provider: .openAI),
                item("gpt-5.4-mini", "GPT-5.4 Mini", provider: .openAI),
                item("llama-4-maverick", "Llama 4 Maverick", provider: .meta, badge: .plus),
            ]),
            .init(
                id: "pro-exclusive",
                callToAction: .init(prefix: "Pro exclusive.", actionTitle: "Upgrade", flowType: .upgrade),
                items: [
                    item("gpt-5.5", "GPT-5.5", provider: .openAI, badge: .pro, isDimmed: true),
                    item("claude-opus-4.6", "Claude Opus 4.6", provider: .anthropic, badge: .pro, isDimmed: true),
                ]
            ),
        ],
        initiallySelectedModelID: "gpt-5.4"
    )

    private static let proContent = UnifiedToggleInputModelPickerContent(
        sections: [
            .init(id: "pro", callToAction: nil, items: [
                item("gpt-5.4", "GPT-5.4", subtitle: "Everyday use", provider: .openAI, badge: .plus),
                item("claude-opus-4.7", "Claude Opus 4.7", subtitle: "Uses limits faster", provider: .anthropic, badge: .pro),
                item("gpt-oss-120b", "gpt-oss 120B", subtitle: "Extra privacy", provider: .oss, showsInfo: true),
                item("llama-4-maverick", "Llama 4 Maverick", provider: .meta, badge: .plus),
                item("claude-sonnet-4.6", "Claude Sonnet 4.6", provider: .anthropic, badge: .plus),
                item("gpt-5.5", "GPT-5.5", provider: .openAI, badge: .pro),
                item("gpt-5.4-nano", "GPT-5.4 Nano", provider: .openAI),
                item("gpt-5.4-mini", "GPT-5.4 Mini", provider: .openAI),
                item("claude-haiku-4.5", "Claude Haiku 4.5", provider: .anthropic),
                item("mistral-small-4", "Mistral Small 4", provider: .mistral),
                item("llama-4-scout", "Llama 4 Scout", provider: .meta),
            ]),
        ],
        initiallySelectedModelID: "gpt-5.4"
    )

    private static func item(_ id: String,
                             _ name: String,
                             subtitle: String? = nil,
                             provider: AIChatModel.ModelProvider,
                             badge: UnifiedToggleInputModelPickerContent.Badge? = nil,
                             showsInfo: Bool = false,
                             isDimmed: Bool = false) -> UnifiedToggleInputModelPickerContent.Item {
        .init(
            id: id,
            name: name,
            subtitle: subtitle,
            provider: provider,
            badge: badge,
            showsInfo: showsInfo,
            isDimmed: isDimmed
        )
    }
}

#endif
