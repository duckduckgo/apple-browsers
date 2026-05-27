//
//  ReturnToTabCard.swift
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
import Core
import DesignResourcesKit
import DesignResourcesKitIcons

struct ReturnToTabCard: View {
    @Environment(\.layoutDirection) private var layoutDirection

    @ObservedObject var model: EscapeHatchModel

    /// Frame of the three-dots menu button in the key window's coordinate space.
    /// Used as the popover anchor when burning a tab on iPad — the FireConfirmationPresenter
    /// expects window-space coordinates because it attaches the popover to the key window.
    @State private var menuFrameInWindow: CGRect = .zero

    var body: some View {
        GeometryReader { proxy in
            if model.isActionsEnabled {
                bodyWithActions(width: proxy.size.width)
            } else {
                contentView
            }
        }
        .frame(height: Metrics.height)
    }

    @ViewBuilder
    private func bodyWithActions(width: CGFloat) -> some View {
        SwipeActionView(onCommit: model.primarySwipeAction.perform) {
            contentView
        } actions: {
            swipeableActionsView
        }

        // `.contentMenu` causes the Preview View to overlap with surrounding elements.
        // We're relying on the `.contextMenu(preview:)` API, as it allows us to fine tune the Preview dimensions.
        .contextMenuWithPreviewIfAvailable {
            menuContentView
        } preview: {
            contentView
                .frame(width: width, height: Metrics.height)
        }
        // We're Clipping with the shape `( ]` as the `swipeableActionsView` subview is not expected to be a perfect pill, on its right hand side during Swipe
        .clipShape(LeftCapsuleShape())
    }

    private var contentView: some View {
        HStack(spacing: Metrics.innerSpacing) {
            mainView
            if model.isActionsEnabled {
                menuView
            }
        }
        .padding(contentPaddingEdges, Metrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: Metrics.height)
        .background(
            Capsule()
                .fill(Color(designSystemColor: .controlsFillSecondary))
        )
    }

    private var contentPaddingEdges: Edge.Set {
        /// Avoid trailing padding when the Menu is visible
        model.isActionsEnabled ? .leading : .horizontal
    }

    private var mainView: some View {
        Button(action: model.onCardTap) {
            HStack(spacing: Metrics.innerSpacing) {
                iconView
                VStack(alignment: .leading, spacing: Metrics.titleToSubtitleSpacing) {
                    Text(UserText.escapeHatchReturnToLabel)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                        .frame(height: Metrics.textRowHeight, alignment: .center)
                    Text(model.title)
                        .daxSubheadSemibold()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .lineLimit(1)
                        .frame(height: Metrics.textRowHeight, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityHint(Text(UserText.escapeHatchAccessibilityHint))
        .accessibilityIdentifier("NTP.escapeHatch.card")
    }

    private var menuView: some View {
        Menu {
            menuContentView
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.menuDotsHorizontal)
                .foregroundColor(Color(designSystemColor: .icons))
                .padding(.horizontal, Metrics.horizontalPadding)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(UserText.escapeHatchMoreButtonAccessibilityLabel))
        .accessibilityIdentifier("NTP.escapeHatch.moreButton")
        .onFrameUpdate(in: .global, using: MenuFrameInWindowKey.self) { menuFrameInWindow = $0 }
    }

    @ViewBuilder
    private var menuContentView: some View {
        Section(header: Text(model.subtitle)) {
            MenuActionButton(
                text: UserText.escapeHatchMenuReturnToTab,
                icon: DesignSystemImages.Glyphs.Size16.goBackCircle,
                role: .none,
                action: model.onCardTap
            )
            if model.isFireTab {
                MenuActionButton(
                    text: UserText.escapeHatchMenuBurnTab,
                    icon: DesignSystemImages.Glyphs.Size16.fire,
                    role: .destructive,
                    action: model.onBurnTabImmediately
                )
            } else {
                MenuActionButton(
                    text: UserText.escapeHatchMenuCloseTab,
                    icon: DesignSystemImages.Glyphs.Size16.closeOutline,
                    role: .destructive,
                    action: model.onCloseTab
                )
                MenuActionButton(
                    text: UserText.escapeHatchMenuBurnTab,
                    icon: DesignSystemImages.Glyphs.Size16.fire,
                    role: .destructive,
                    action: { model.onBurnTabWithConfirmation(menuFrameInWindow) }
                )
            }
            Picker(selection: model.afterInactivityOptionBinding) {
                ForEach(AfterInactivityOption.allCases, id: \.self) { option in
                    Text(option.description)
                        .tag(option)
                }
            } label: {
                Text(UserText.settingsAfterInactivityLabel)
                Text(model.afterInactivityOptionBinding.wrappedValue.description)
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                Image(uiImage: DesignSystemImages.Glyphs.Size16.settings)
                    .foregroundColor(Color(designSystemColor: .icons))

            }
            .pickerStyle(.menu)
        }
    }

    private var swipeableActionsView: some View {
        ZStack(alignment: .center) {
            Color(designSystemColor: .destructivePrimary)

            Text(model.primarySwipeAction.label)
                .daxSubheadRegular()
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Metrics.horizontalPadding)
        }
    }

    private var accessibilityLabelText: String {
        if model.subtitle.isEmpty {
            return String(format: UserText.escapeHatchReturnToAccessibilityLabelFormat, model.title)
        }
        return String(format: UserText.escapeHatchReturnToWithSubtitleAccessibilityLabelFormat, model.title, model.subtitle)
    }

    /// Favicon from .tabs cache, fire tab icon, Duck.ai logo, or placeholder depending on tab type.
    /// Decorated with a small back-arrow overlay to signal "return to" affordance.
    private var iconView: some View {
        ZStack(alignment: .bottomTrailing) {
            faviconBaseView
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.iconCornerRadius))

            backArrowOverlay
                // Flip x for RTL so the badge stays at the bottom-trailing visual corner
                // (which is bottom-left in RTL) and protrudes outward rather than inward.
                .offset(x: layoutDirection == .rightToLeft ? -Metrics.overlayOffset : Metrics.overlayOffset,
                        y: Metrics.overlayOffset)
        }
        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
    }

    @ViewBuilder
    private var faviconBaseView: some View {
        switch model.tabType {
        case .fire:
            Image(uiImage: DesignSystemImages.Color.Size96.fireTab)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .aiChat:
            Image(uiImage: UIImage(resource: .duckAIDefault))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .regular:
            if let domain = model.domain {
                DomainFaviconView(domain: domain)
                    .id(domain)
            } else {
                RoundedRectangle(cornerRadius: Metrics.iconCornerRadius)
                    .fill(Color(designSystemColor: .controlsFillPrimary))
            }
        }
    }

    /// Uses rebranded `decorationPrimary` (9% vs default 30% opacity); will become global default after rebrand rollout.
    private var backArrowOverlay: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size12.goBackCircleRecolorable)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: Metrics.overlayContainerSize, height: Metrics.overlayContainerSize)
            .overlay(
                Circle()
                    .strokeBorder(Color(singleUseColor: .rebranding(.decorationPrimary)),
                                  lineWidth: Metrics.overlayStrokeWidth)
            )
    }
}

/// Holds FaviconViewModel in @StateObject so it's created once per domain instead of on every body.
private struct DomainFaviconView: View {
    let domain: String

    @StateObject private var viewModel: FaviconViewModel

    init(domain: String) {
        self.domain = domain
        _viewModel = StateObject(wrappedValue: FaviconViewModel(domain: domain, useFakeFavicon: true, cacheType: .tabs))
    }

    var body: some View {
        FaviconView(viewModel: viewModel)
    }
}

/// One-line menu row: icon glyph on the leading side, text on the trailing side (Apple's standard `Label` layout).
/// Captures the icon-coloring asymmetry: non-destructive rows apply the `icons` design token explicitly;
/// destructive rows inherit SwiftUI's auto-tint from `role: .destructive`.
private struct MenuActionButton: View {
    let text: String
    let icon: UIImage
    let role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label {
                Text(text)
            } icon: {
                Image(uiImage: icon)
                    .foregroundColor(role == nil ? Color(designSystemColor: .icons) : nil)
            }
        }
    }
}

private struct MenuFrameInWindowKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private enum Metrics {
    static let height: CGFloat = 56
    static let horizontalPadding: CGFloat = 16
    static let innerSpacing: CGFloat = 8
    static let titleToSubtitleSpacing: CGFloat = 0
    static let textRowHeight: CGFloat = 20
    static let iconSize: CGFloat = 24
    static let iconCornerRadius: CGFloat = 6
    static let overlayContainerSize: CGFloat = 12
    static let overlayStrokeWidth: CGFloat = 1
    static let overlayOffset: CGFloat = 3
}

// MARK: - Previews

#if DEBUG

#Preview("Return to tab card") {
    let target = Tab(fireTab: false)
    ReturnToTabCard(model: .preview(title: "Tokamak - Wikipedia",
                                    subtitle: "en.wikipedia.org/wiki/Tokamak",
                                    tabType: .regular,
                                    domain: "en.wikipedia.org",
                                    targetTab: target,
                                    tabCount: 9))
        .padding()
        .frame(width: 360)
}

#Preview("Return to Duck.ai") {
    let target = Tab(fireTab: false)
    ReturnToTabCard(model: .preview(title: "Good Dog Name Ideas",
                                    subtitle: "Duck.ai",
                                    tabType: .aiChat,
                                    domain: nil,
                                    targetTab: target,
                                    tabCount: 9))
        .padding()
        .frame(width: 360)
}

#Preview("Return to Fire Tab") {
    let target = Tab(fireTab: true)
    ReturnToTabCard(model: .preview(title: "Last Used Fire Tab",
                                    subtitle: "",
                                    tabType: .fire,
                                    domain: nil,
                                    targetTab: target,
                                    tabCount: 1))
        .padding()
        .frame(width: 360)
}

#Preview("Return to tab — New Tab selected") {
    let target = Tab(fireTab: false)
    ReturnToTabCard(model: .preview(title: "Tokamak - Wikipedia",
                                    subtitle: "en.wikipedia.org/wiki/Tokamak",
                                    tabType: .regular,
                                    domain: "en.wikipedia.org",
                                    targetTab: target,
                                    tabCount: 9,
                                    afterInactivityOption: .newTab))
        .padding()
        .frame(width: 360)
}

#endif
