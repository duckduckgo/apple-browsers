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

    let model: EscapeHatchModel

    var body: some View {
        HStack(spacing: Metrics.innerSpacing) {
            mainView
            if model.isActionsEnabled {
                menuView
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: Metrics.height)
        .background(
            Capsule()
                .fill(Color(designSystemColor: .controlsFillSecondary))
        )
        .if(model.isActionsEnabled) {
            $0.contextMenu { menuContentView }
        }
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
    }

    @ViewBuilder
    private var menuContentView: some View {
        Section(header: Text(model.subtitle)) {
            Button(action: model.onCardTap) {
                Label {
                    Text(UserText.escapeHatchMenuReturnToTab)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.goBackCircle)
                        .foregroundColor(Color(designSystemColor: .icons))
                }
            }
            Button(role: .destructive, action: model.onCloseTab) {
                Label {
                    Text(UserText.escapeHatchMenuCloseTab)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                }
            }
            Button(role: .destructive, action: model.onBurnTab) {
                Label {
                    Text(UserText.escapeHatchMenuBurnTab)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.fire)
                }
            }
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

#endif
