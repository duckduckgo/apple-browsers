//
//  RMFSheetView.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

/// A sheet action: a label and what happens when it is tapped.
public struct RMFSheetAction {
    public let title: String
    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

/// The RMF modal promo template (Figma `RMF Sheet` and `RMF Sheet / iPad`).
///
/// Top to bottom: an optional close button, a media slot, an optional eyebrow, the title, optional body
/// text, an optional content block (e.g. ``SheetChoiceList`` or ``SheetCardList``), the primary action,
/// an optional secondary action and an optional footnote.
///
/// The view draws its own background and fills the width it is offered; the presenter supplies the
/// sheet chrome (corner radius, detents). On a phone, `fullscreen` picks the tall composition, with the
/// content in a card and the actions pinned at the bottom; otherwise the sheet is content height.
/// On iPad the composition comes from the horizontal size class: Regular is content height, Compact
/// pins the actions at the bottom. When the text doesn't fit (e.g. at large Dynamic Type) the content
/// scrolls and the actions stay pinned.
///
/// The media slot keeps the size of what is placed in it, with no background panel behind it. Media is
/// treated as decorative and hidden from VoiceOver. VoiceOver reads the title, eyebrow, body, content,
/// actions and footnote, then the close button.
public struct RMFSheetView<Media: View, Content: View>: View {

    private let eyebrowText: String?
    private let title: String
    private let bodyText: String?
    private let footnote: String?
    private let primaryAction: RMFSheetAction
    private let secondaryAction: RMFSheetAction?
    private let dismissable: Bool
    private let closeAccessibilityLabel: String
    private let fullscreen: Bool
    private let onClose: () -> Void
    private let media: Media
    private let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.rmfSheetLayoutOverride) private var layoutOverride

    /// - Parameters:
    ///   - eyebrowText: Optional short label above the title, e.g. "Limited time only".
    ///   - title: The heading.
    ///   - bodyText: Optional copy under the title.
    ///   - footnote: Optional terms or settings guidance under the actions.
    ///   - primaryAction: The primary, accent-coloured action.
    ///   - secondaryAction: Optional secondary action, e.g. "Not Now".
    ///   - dismissable: Whether to show the close button.
    ///   - closeAccessibilityLabel: VoiceOver label for the close button.
    ///   - fullscreen: Phone only. Use the tall composition with the actions pinned at the bottom.
    ///   - onClose: Called when the close button is tapped.
    ///   - media: The illustration. It keeps its own size.
    ///   - content: Optional content block shown under the text.
    public init(eyebrowText: String? = nil,
                title: String,
                bodyText: String? = nil,
                footnote: String? = nil,
                primaryAction: RMFSheetAction,
                secondaryAction: RMFSheetAction? = nil,
                dismissable: Bool = true,
                closeAccessibilityLabel: String,
                fullscreen: Bool = false,
                onClose: @escaping () -> Void = {},
                @ViewBuilder media: () -> Media,
                @ViewBuilder content: () -> Content) {
        self.eyebrowText = eyebrowText
        self.title = title
        self.bodyText = bodyText
        self.footnote = footnote
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.dismissable = dismissable
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.fullscreen = fullscreen
        self.onClose = onClose
        self.media = media()
        self.content = content()
    }

    public var body: some View {
        let metrics = layout.metrics

        Group {
            if metrics.usesCard {
                VStack(spacing: metrics.cardOuterGap) {
                    if dismissable {
                        closeBar(metrics)
                            .accessibilitySortPriority(1)
                    }
                    card(metrics)
                        .accessibilitySortPriority(2)
                }
            } else {
                VStack(spacing: 0) {
                    if dismissable {
                        closeBar(metrics)
                            .accessibilitySortPriority(1)
                    }
                    scrollingContent(metrics)
                        .padding(.top, dismissable ? 0 : metrics.mediaTopPaddingWithoutClose)
                        .accessibilitySortPriority(3)
                    if metrics.pinsActionsToBottom {
                        Spacer(minLength: 0)
                    }
                    actions(metrics)
                        .accessibilitySortPriority(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: metrics.pinsActionsToBottom ? .infinity : nil, alignment: .top)
        .background(Color(designSystemColor: .surfaceTertiary).ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    var layout: RMFSheetLayout {
        layoutOverride ?? RMFSheetLayout.resolve(idiom: UIDevice.current.userInterfaceIdiom,
                                                 horizontalSizeClass: horizontalSizeClass,
                                                 fullscreen: fullscreen)
    }

    private var hasContent: Bool {
        Content.self != EmptyView.self
    }

    private var hasMedia: Bool {
        Media.self != EmptyView.self
    }

    // MARK: - Regions

    private func closeBar(_ metrics: RMFSheetMetrics) -> some View {
        // CloseButtonStyle adds an invisible hit area around the visible circle; offset it so the paddings
        // are measured to the circle, as in Figma.
        let hitArea = CloseButtonStyle.Constant.padding
        let iconPadding = (metrics.closeButtonDiameter - Metrics.closeIconSize) / 2 - hitArea
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .renderingMode(.template)
                    .frame(width: Metrics.closeIconSize, height: Metrics.closeIconSize)
                    .padding(iconPadding)
            }
            .buttonStyle(CloseButtonStyle())
            .accessibilityLabel(closeAccessibilityLabel)
        }
        .padding(.top, metrics.closeTopPadding - hitArea)
        .padding(.trailing, metrics.closeTrailingPadding - hitArea)
        .padding(.bottom, metrics.closeBottomPadding - hitArea)
    }

    private func card(_ metrics: RMFSheetMetrics) -> some View {
        VStack(spacing: 0) {
            scrollingContent(metrics)
                .accessibilitySortPriority(2)
            Spacer(minLength: 0)
            actions(metrics)
                .accessibilitySortPriority(1)
        }
        .padding(.top, metrics.cardTopPadding)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(Color(designSystemColor: .surfaceTertiary))
        )
        .padding(.horizontal, metrics.cardHorizontalMargin)
        .accessibilityElement(children: .contain)
    }

    /// Media, text and content. Sized to fit when there is room; scrolls when there is not.
    @ViewBuilder
    private func scrollingContent(_ metrics: RMFSheetMetrics) -> some View {
        if #available(iOS 16, *) {
            ViewThatFits(in: .vertical) {
                mainContent(metrics)
                ScrollView(.vertical) {
                    mainContent(metrics)
                }
            }
        } else {
            ScrollView(.vertical) {
                mainContent(metrics)
            }
        }
    }

    private func mainContent(_ metrics: RMFSheetMetrics) -> some View {
        VStack(spacing: 0) {
            if hasMedia {
                media
                    .padding(.horizontal, metrics.mediaHorizontalPadding)
                    .padding(.bottom, metrics.mediaTrailing)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            message(metrics)
                .padding(.top, metrics.messageTopPadding)
                .padding(.horizontal, metrics.messageHorizontalPadding)
                .accessibilitySortPriority(2)

            if hasContent {
                content
                    .padding(.top, metrics.contentTopPadding)
                    .padding(.horizontal, metrics.contentHorizontalPadding)
                    .accessibilitySortPriority(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func message(_ metrics: RMFSheetMetrics) -> some View {
        VStack(spacing: metrics.textGap) {
            if let eyebrowText {
                Text(eyebrowText)
                    .font(RMFSheetTypography.footnoteSemibold)
                    .foregroundColor(Color(designSystemColor: .accentTextPrimary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Metrics.eyebrowHorizontalPadding)
                    .padding(.vertical, Metrics.eyebrowVerticalPadding)
                    .background(
                        Capsule()
                            .fill(Color(designSystemColor: metrics.isPad ? .accentGlowSecondary : .accentGlowPrimary))
                    )
                    .accessibilitySortPriority(2)
            }

            Text(title)
                .font(RMFSheetTypography.title1)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(3)

            if let bodyText {
                Text(bodyText)
                    .font(RMFSheetTypography.bodyRegular)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func actions(_ metrics: RMFSheetMetrics) -> some View {
        VStack(spacing: metrics.actionGap) {
            Button(action: primaryAction.action) {
                Text(primaryAction.title)
            }
            .buttonStyle(RMFSheetPrimaryButtonStyle())

            if let secondaryAction {
                Button(action: secondaryAction.action) {
                    Text(secondaryAction.title)
                }
                .buttonStyle(RMFSheetSecondaryButtonStyle())
            }

            if let footnote {
                Text(footnote)
                    .font(RMFSheetTypography.subheadRegular)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, metrics.actionsTopPadding)
        .padding(.bottom, metrics.actionsBottomPadding)
        .padding(.horizontal, metrics.actionsHorizontalPadding)
        .accessibilityElement(children: .contain)
    }
}

private enum Metrics {
    static let closeIconSize: CGFloat = 24
    static let eyebrowHorizontalPadding: CGFloat = 10
    static let eyebrowVerticalPadding: CGFloat = 3
}

// MARK: - Convenience initialisers

public extension RMFSheetView where Content == EmptyView {
    /// A sheet with media and no content block.
    init(eyebrowText: String? = nil,
         title: String,
         bodyText: String? = nil,
         footnote: String? = nil,
         primaryAction: RMFSheetAction,
         secondaryAction: RMFSheetAction? = nil,
         dismissable: Bool = true,
         closeAccessibilityLabel: String,
         fullscreen: Bool = false,
         onClose: @escaping () -> Void = {},
         @ViewBuilder media: () -> Media) {
        self.init(eyebrowText: eyebrowText, title: title, bodyText: bodyText, footnote: footnote,
                  primaryAction: primaryAction, secondaryAction: secondaryAction,
                  dismissable: dismissable, closeAccessibilityLabel: closeAccessibilityLabel,
                  fullscreen: fullscreen, onClose: onClose,
                  media: media, content: { EmptyView() })
    }
}

// MARK: - Layout override

private struct RMFSheetLayoutOverrideKey: EnvironmentKey {
    static let defaultValue: RMFSheetLayout? = nil
}

extension EnvironmentValues {
    /// Forces an ``RMFSheetLayout`` regardless of idiom and size class. Used by previews and tests.
    var rmfSheetLayoutOverride: RMFSheetLayout? {
        get { self[RMFSheetLayoutOverrideKey.self] }
        set { self[RMFSheetLayoutOverrideKey.self] = newValue }
    }
}

extension View {
    /// Forces the sheet's layout. Used by previews and tests to render iPad layouts on any device.
    func rmfSheetLayout(_ layout: RMFSheetLayout) -> some View {
        environment(\.rmfSheetLayoutOverride, layout)
    }
}

#endif
