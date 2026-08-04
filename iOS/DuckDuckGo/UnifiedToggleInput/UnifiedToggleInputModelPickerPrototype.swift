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
    let onCallToAction: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(content.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, Metrics.horizontalPadding)
                    }

                    if let callToAction = section.callToAction {
                        CallToActionView(callToAction: callToAction, action: onCallToAction)
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
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
    }
}

private struct ModelRow: View {

    let item: UnifiedToggleInputModelPickerContent.Item
    let isSelected: Bool
    let onSelect: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: Metrics.iconTextSpacing) {
                    providerIcon

                    VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                        modelName

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .daxFootnoteRegular()
                                .foregroundStyle(Color(designSystemColor: .textSecondary))
                        }
                    }

                    Spacer(minLength: Metrics.minimumTrailingSpacing)

                    if let badge = item.badge {
                        Text(badge.rawValue)
                            .daxCaption1()
                            .foregroundStyle(Color(designSystemColor: .textTertiary))
                    }
                }
                .padding(.leading, Metrics.horizontalPadding)
                .padding(.trailing, item.showsInfo ? Metrics.infoSpacing : Metrics.horizontalPadding)
                .frame(maxWidth: .infinity, minHeight: item.subtitle == nil ? Metrics.rowHeight : Metrics.rowWithSubtitleHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.showsInfo {
                Button(action: onInfo) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.infoSolid)
                        .renderingMode(.template)
                        .foregroundStyle(Color(designSystemColor: .iconsTertiary))
                        .frame(width: Metrics.infoButtonWidth, height: Metrics.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Model information")
            }
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Metrics.selectionCornerRadius)
                    .fill(Color(designSystemColor: .controlsFillPrimary))
            }
        }
        .padding(.horizontal, Metrics.outerHorizontalPadding)
        .opacity(item.isDimmed ? Metrics.dimmedOpacity : 1)
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
                .daxBodyBold()
                .foregroundStyle(Color(designSystemColor: .textPrimary))

            if components.count > 1 {
                Text(components[1])
                    .daxBodyRegular()
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
        static let rowHeight: CGFloat = 48
        static let rowWithSubtitleHeight: CGFloat = 56
        static let iconSize: CGFloat = 18
        static let iconTextSpacing: CGFloat = 14
        static let textSpacing: CGFloat = 1
        static let nameSpacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 12
        static let outerHorizontalPadding: CGFloat = 8
        static let minimumTrailingSpacing: CGFloat = 8
        static let infoSpacing: CGFloat = 4
        static let infoButtonWidth: CGFloat = 40
        static let selectionCornerRadius: CGFloat = 12
        static let dimmedOpacity = 0.32
    }
}

private struct CallToActionView: View {

    let callToAction: UnifiedToggleInputModelPickerContent.CallToAction
    let action: () -> Void

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Text(callToAction.prefix)
                .daxFootnoteRegular()
                .foregroundStyle(Color(designSystemColor: .textSecondary))

            Button(action: action) {
                Text(callToAction.actionTitle)
                    .daxFootnoteRegular()
                    .foregroundStyle(Color(designSystemColor: .accentPrimary))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
    }
}

private extension CallToActionView {

    enum Metrics {
        static let spacing: CGFloat = 4
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 12
    }
}

#if DEBUG

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
                 onCallToAction: @escaping () -> Void) {
        guard presentedViewController == nil else { return }

        let rootView = UnifiedToggleInputModelPickerPrototypeHost(
            onSelect: onSelect,
            onInfo: onInfo,
            onCallToAction: onCallToAction
        )
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
        popover.backgroundColor = UIColor(designSystemColor: .background)
        popover.delegate = self

        presentingViewController.present(hostingController, animated: true)
        presentedViewController = hostingController
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

private extension UnifiedToggleInputModelPickerPrototypePresenter {

    enum Metrics {
        static let width: CGFloat = 348
        static let height: CGFloat = 640
        static let minimumVerticalMargin: CGFloat = 48
    }
}

private struct UnifiedToggleInputModelPickerPrototypeHost: View {

    @State private var level = UnifiedToggleInputModelPickerPrototypeLevel.free
    @State private var selectedModelID = UnifiedToggleInputModelPickerPrototypeFixtures.content(for: .free).initiallySelectedModelID

    let onSelect: (String) -> Void
    let onInfo: (String) -> Void
    let onCallToAction: () -> Void

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
                callToAction: .init(prefix: "Subscriber exclusive.", actionTitle: "Try for free"),
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
                callToAction: .init(prefix: "Pro exclusive.", actionTitle: "Upgrade"),
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
