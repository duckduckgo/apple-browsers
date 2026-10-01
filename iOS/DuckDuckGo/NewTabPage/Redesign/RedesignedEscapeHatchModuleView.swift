//
//  RedesignedEscapeHatchModuleView.swift
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

/// "Return to…" New Tab Page module: a header with a "Show All" action above a row showing the last used tab's
/// thumbnail, title, favicon, domain and last visit time, plus a trailing menu.
struct RedesignedEscapeHatchModuleView<MenuContent: View>: View {
    let title: String
    let domain: String?
    let lastVisitedText: String?
    let thumbnail: UIImage?
    var favicon: UIImage?
    var faviconDomain: String?
    var onMenuFrameChange: (CGRect) -> Void = { _ in }
    let swipeActionLabel: String
    let onSwipeCommit: () -> Void
    let onTap: () -> Void
    let onShowAllTap: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var rowHeight: CGFloat = Metrics.thumbnailSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerToBodySpacing) {
            headerView
            swipeableBodyView
        }
        .padding(Metrics.modulePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RedesignedNewTabPageModuleBackground()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            HStack(spacing: Metrics.headerIconToTitleSpacing) {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.returnTo)
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundColor(Color(designSystemColor: .icons))
                    .frame(width: Metrics.headerIconContainerWidth)
                Text(UserText.escapeHatchReturnToLabel)
                    .daxButton()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
            }

            Spacer(minLength: Metrics.headerMinimumSpacing)

            showAllButton
        }
        .frame(minHeight: Metrics.headerHeight)
    }

    private var showAllButton: some View {
        Button(action: onShowAllTap) {
            HStack(spacing: Metrics.showAllLabelToArrowSpacing) {
                Text(UserText.escapeHatchShowAllLabel)
                    .daxSubheadRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineLimit(1)
                Image(uiImage: DesignSystemImages.Glyphs.Size10.chevronRight)
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundColor(Color(designSystemColor: .icons))
                    .frame(width: Metrics.showAllArrowSize, height: Metrics.showAllArrowSize)
                    .background(
                        Circle()
                            .fill(Color(designSystemColor: .accentPrimary).opacity(Metrics.showAllArrowBackgroundOpacity))
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("NewTabPage.escapeHatch.showAll")
    }

    // MARK: - Body

    private var swipeableBodyView: some View {
        SwipeActionView(onCommit: onSwipeCommit) {
            bodyView
                // Include the gaps between the thumbnail, text and menu in the cell's drag target.
                .contentShape(Rectangle())
                // Measure the intrinsic row height so the swipe container also fits larger text sizes.
                .fixedSize(horizontal: false, vertical: true)
                .onFrameUpdate(in: .local, using: RedesignedEscapeHatchRowFrameKey.self) { frame in
                    // Hosting views can report an empty frame during measurement. Never let that
                    // collapse the swipe container, or its clipped content cannot recover its height.
                    guard frame.height.isFinite, frame.height > 0 else { return }
                    rowHeight = max(Metrics.thumbnailSize, frame.height)
                }
        } actions: {
            ZStack {
                Color(designSystemColor: .destructivePrimary)
                Text(swipeActionLabel)
                    .daxSubheadRegular()
                    .foregroundColor(Color(designSystemColor: .destructiveContentPrimary))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, Metrics.modulePadding)
            }
        }
        .frame(height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius, style: .continuous))
    }

    private var bodyView: some View {
        HStack(spacing: Metrics.bodySpacing) {
            Button(action: onTap) {
                HStack(spacing: Metrics.bodySpacing) {
                    thumbnailView
                    tabDetailsView
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityHint(Text(UserText.escapeHatchAccessibilityHint))
            .accessibilityIdentifier("NewTabPage.escapeHatch.card")
            .accessibilityAction(named: Text(swipeActionLabel), onSwipeCommit)

            menuView
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius, style: .continuous)
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(Color(designSystemColor: .controlsFillPrimary))
            }
        }
        .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
        .clipShape(shape)
    }

    private var tabDetailsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .daxSubheadSemibold()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .lineLimit(Metrics.titleLineLimit)
                .multilineTextAlignment(.leading)

            Color.clear.frame(height: Metrics.titleToCaptionMinimumSpacing)

            captionView
        }
        .padding(.top, Metrics.tabDetailsTopPadding)
        .padding(.bottom, Metrics.tabDetailsBottomPadding)
        .frame(maxWidth: .infinity, minHeight: Metrics.thumbnailSize, alignment: .leading)
    }

    private var captionView: some View {
        HStack(spacing: Metrics.captionFaviconToTextSpacing) {
            if let favicon {
                Image(uiImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.captionFaviconSize, height: Metrics.captionFaviconSize)
            } else if let faviconDomain = faviconDomain ?? domain {
                DomainFaviconView(domain: faviconDomain)
                    .id(faviconDomain)
                    .frame(width: Metrics.captionFaviconSize, height: Metrics.captionFaviconSize)
            }

            HStack(spacing: Metrics.captionTextSpacing) {
                if let domain {
                    Text(verbatim: domain)
                        .daxCaption()
                }
                if domain != nil, lastVisitedText != nil {
                    Text(verbatim: "•")
                        .daxFootnoteRegular()
                }
                if let lastVisitedText {
                    Text(lastVisitedText)
                        .daxCaption()
                }
            }
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .lineLimit(1)
        }
        .frame(minHeight: Metrics.captionHeight)
    }

    private var accessibilityLabel: String {
        let caption = [domain, lastVisitedText].compactMap { $0 }.joined(separator: ", ")
        if caption.isEmpty {
            return String(format: UserText.escapeHatchReturnToAccessibilityLabelFormat, title)
        }
        return String(format: UserText.escapeHatchReturnToWithSubtitleAccessibilityLabelFormat, title, caption)
    }

    private var menuView: some View {
        Menu {
            menuContent()
        } label: {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.menuDotsHorizontal)
                .foregroundColor(Color(designSystemColor: .icons))
                .frame(width: Metrics.menuButtonSize, height: Metrics.menuButtonSize)
                .contentShape(Circle())
        }
        .accessibilityLabel(Text(UserText.escapeHatchMoreButtonAccessibilityLabel))
        .accessibilityIdentifier("NewTabPage.escapeHatch.moreButton")
        .onFrameUpdate(in: .global, using: RedesignedEscapeHatchMenuFrameKey.self, perform: onMenuFrameChange)
    }
}

private struct RedesignedEscapeHatchRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct RedesignedEscapeHatchMenuFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private enum Metrics {
    static let modulePadding: CGFloat = 16
    static let headerToBodySpacing: CGFloat = 16

    static let headerHeight: CGFloat = 20
    static let headerMinimumSpacing: CGFloat = 8
    static let headerIconContainerWidth: CGFloat = 18
    static let headerIconToTitleSpacing: CGFloat = 6
    static let showAllLabelToArrowSpacing: CGFloat = 8
    static let showAllArrowSize: CGFloat = 20
    // The design uses a 9% accent tint; DRK does not have an equivalent semantic fill.
    static let showAllArrowBackgroundOpacity: CGFloat = 0.09

    static let bodySpacing: CGFloat = 12
    static let thumbnailSize: CGFloat = 64
    static let thumbnailCornerRadius: CGFloat = 14
    static let titleLineLimit = 2
    static let titleToCaptionMinimumSpacing: CGFloat = 4
    static let tabDetailsTopPadding: CGFloat = 6
    static let tabDetailsBottomPadding: CGFloat = 2
    static let captionHeight: CGFloat = 16
    static let captionFaviconSize: CGFloat = 16
    static let captionFaviconToTextSpacing: CGFloat = 6
    static let captionTextSpacing: CGFloat = 2
    static let menuButtonSize: CGFloat = 44
}

// MARK: - Previews

#if DEBUG

#Preview("Return to module") {
    RedesignedEscapeHatchModuleView(title: "The BEST Chicken Marinade (For Grilling or Baking) | Mom On Timeout",
                                    domain: "recipesite.com",
                                    lastVisitedText: "Yesterday",
                                    thumbnail: nil,
                                    swipeActionLabel: UserText.escapeHatchSwipeActionCloseTab,
                                    onSwipeCommit: {},
                                    onTap: {},
                                    onShowAllTap: {}) {
        Button("Return to Tab") {}
        Button("Close Tab", role: .destructive) {}
    }
    .padding(16)
}

#Preview("Return to module - short title, no domain") {
    RedesignedEscapeHatchModuleView(title: "Good Dog Name Ideas",
                                    domain: nil,
                                    lastVisitedText: "2 hours ago",
                                    thumbnail: nil,
                                    swipeActionLabel: UserText.escapeHatchSwipeActionCloseTab,
                                    onSwipeCommit: {},
                                    onTap: {},
                                    onShowAllTap: {}) {
        Button("Return to Tab") {}
    }
    .padding(16)
}

#endif
