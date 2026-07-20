//
//  CardItem.swift
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

// MARK: - Configuration

/// An icon shown by a ``CardItem``, together with where it sits relative to the text.
public struct CardItemIcon {
    /// The icon's position relative to the card item's text block.
    public enum Position: Equatable {
        /// In a leading column, aligned to the top of the content.
        case leading
        /// Above the text block.
        case topLeading
        /// In a leading column, vertically centered with the content.
        case leadingColumn
    }

    /// The design-system size for a ``CardItem``'s icon.
    public enum Size {
        case size24
        case size32
        case size40
        case size56

        var points: CGFloat {
            switch self {
            case .size24: 24
            case .size32: 32
            case .size40: 40
            case .size56: 56
            }
        }
    }

    public let position: Position
    public let visual: Graphic
    public let size: Size
    /// The gap between the icon and the text block — horizontal for a leading icon, vertical for `.topLeading`.
    public let spacing: CGFloat

    public init(position: Position, visual: Graphic, size: Size = .size24, spacing: CGFloat = 8) {
        self.position = position
        self.visual = visual
        self.size = size
        self.spacing = spacing
    }
}

/// A trailing accessory shown at the end of a ``CardItem``. The colour is supplied by the caller so
/// the surrounding screen controls the tint.
public enum CardItemAccessory {
    case chevron(Color)
    case checkmark(Color)
}

/// A design-system font token for a ``CardItem``. Each value maps to a DesignResourcesKit dax font;
/// the private initializer keeps callers on this curated set rather than arbitrary fonts.
public struct CardItemFont {
    let font: Font

    private init(_ font: Font) {
        self.font = font
    }
}

public extension CardItemFont {
    static let headline = CardItemFont(Font(UIFont.daxHeadline()))
    static let bodyRegular = CardItemFont(Font(UIFont.daxBodyRegular()))
    static let subheadRegular = CardItemFont(Font(UIFont.daxSubheadRegular()))
    static let footnoteRegular = CardItemFont(Font(UIFont.daxFootnoteRegular()))
    static let footnoteSemibold = CardItemFont(Font(UIFont.daxFootnoteSemibold()))
}

/// A run of text paired with its design-system font — used for a card item's overline, its title, its
/// inline title details (e.g. a variant name or tier marker), and its body text. The card decides each
/// slot's colour unless `color` is set, which overrides it.
public struct CardItemText {
    public let text: String
    public let font: CardItemFont
    public let color: Color?
    public let modifier: AnyViewModifier?
    /// An optional second run appended inline after `text` (e.g. a "(Nearest)" indicator), in the same
    /// `font` coloured `secondaryColor`. Honored by a card item's body text run.
    /// The defaults keep every existing call site unchanged.
    public let secondaryText: String?
    public let secondaryColor: Color?

    public init(_ text: String, font: CardItemFont, color: Color? = nil, modifier: AnyViewModifier? = nil,
                secondaryText: String? = nil, secondaryColor: Color? = nil) {
        self.text = text
        self.font = font
        self.color = color
        self.modifier = modifier
        self.secondaryText = secondaryText
        self.secondaryColor = secondaryColor
    }
}

extension CardItemText {
    /// The text as a SwiftUI `Text`: the main run in `font` coloured `color` (falling back to
    /// `defaultColor`), plus — when `secondaryText` is set — an inline second run in the same `font`
    /// coloured `secondaryColor` (or `defaultColor`). The caller applies the modifier.
    func styledText(defaultColor: Color) -> Text {
        let main = Text(verbatim: text).font(font.font).foregroundColor(color ?? defaultColor)
        guard let secondaryText else { return main }
        return main + Text(verbatim: " " + secondaryText)
            .font(font.font)
            .foregroundColor(secondaryColor ?? defaultColor)
    }
}

// MARK: - Main View

/// A single card content row: an optional icon, an optional overline, a title with optional inline
/// details (e.g. a variant name or a tier marker), optional body text, and an optional trailing accessory.
/// An optional `accessibilityValue` merges the row into a single VoiceOver element carrying that value
/// (e.g. a "Selected" or "Completed" state).
///
/// `CardItem` lays out content only; the surrounding surface is supplied by the card shell that holds it
public struct CardItem: View {
    private let icon: CardItemIcon?
    private let overline: CardItemText?
    private let title: CardItemText?
    private let titleDetails: [CardItemText]
    private let text: CardItemText?
    /// The vertical gap between the title and the body text.
    private let titleTextSpacing: CGFloat
    /// The leading inset applied to the whole text block (overline, title and body) — e.g. to nudge the
    /// text in from a top-leading icon's edge.
    private let textBlockLeadingInset: CGFloat
    private let trailing: CardItemAccessory?
    private let accessibilityValue: String?

    public init(icon: CardItemIcon? = nil,
                overline: CardItemText? = nil,
                title: CardItemText? = nil,
                titleDetails: [CardItemText] = [],
                text: CardItemText? = nil,
                titleTextSpacing: CGFloat = 0,
                textBlockLeadingInset: CGFloat = 0,
                trailing: CardItemAccessory? = nil,
                accessibilityValue: String? = nil) {
        self.icon = icon
        self.overline = overline
        self.title = title
        self.titleDetails = titleDetails
        self.text = text
        self.titleTextSpacing = titleTextSpacing
        self.textBlockLeadingInset = textBlockLeadingInset
        self.trailing = trailing
        self.accessibilityValue = accessibilityValue
    }

    public var body: some View {
        rowContent
    }
}

// MARK: - Geometry

public extension CardItem {
    /// The leading icon column's width — the icon's size plus its trailing gap — for a `.leading` or
    /// `.leadingColumn` icon; `0` otherwise (no icon, or a `.topLeading` icon above the text). A row list
    /// uses this to inset a divider so it starts under the text.
    var leadingIconColumnWidth: CGFloat {
        guard let icon, icon.position == .leading || icon.position == .leadingColumn else { return 0 }
        return icon.size.points + icon.spacing
    }
}

// MARK: - Layout

private extension CardItem {
    var rowContent: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: rowAlignment, spacing: 0) {
                if let icon, icon.position == .leading || icon.position == .leadingColumn {
                    iconVisual(icon)
                        .padding(.trailing, icon.spacing)
                }

                VStack(alignment: .leading, spacing: icon?.spacing ?? 0) {
                    if let icon, icon.position == .topLeading {
                        iconVisual(icon)
                    }
                    textBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                trailingIcon(for: trailing)
                    .padding(.leading, 8)
                    .accessibilityHidden(true)
            }
        }
        .combinedAccessibilityValue(accessibilityValue)
    }

    var rowAlignment: VerticalAlignment {
        icon?.position == .leading ? .top : .center
    }

    var textBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let overline {
                Text(verbatim: overline.text)
                    .font(overline.font.font)
                    .foregroundColor(overline.color ?? Color(designSystemColor: .textPrimary))
                    .applyingModifier(overline.modifier)
            }
            VStack(alignment: .leading, spacing: titleTextSpacing) {
                titleLine
                if let text {
                    text.styledText(defaultColor: Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .applyingModifier(text.modifier)
                }
            }
        }
        .padding(.leading, textBlockLeadingInset)
    }

    @ViewBuilder
    var titleLine: some View {
        if title != nil || !titleDetails.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let title {
                    Text(verbatim: title.text)
                        .font(title.font.font)
                        .foregroundColor(title.color ?? Color(designSystemColor: .textPrimary))
                        .applyingModifier(title.modifier)
                }
                ForEach(Array(titleDetails.enumerated()), id: \.offset) { _, detail in
                    Text(verbatim: detail.text)
                        .font(detail.font.font)
                        .foregroundColor(detail.color ?? Color(designSystemColor: .textSecondary))
                        .applyingModifier(detail.modifier)
                }
            }
        }
    }

    func iconVisual(_ icon: CardItemIcon) -> some View {
        GraphicView(visual: icon.visual, size: icon.size.points)
    }

    @ViewBuilder
    func trailingIcon(for accessory: CardItemAccessory) -> some View {
        switch accessory {
        case .chevron(let color):
            Image(systemName: "chevron.forward")
                .foregroundColor(color)
        case .checkmark(let color):
            Image(systemName: "checkmark")
                .foregroundColor(color)
        }
    }
}

// MARK: - Helpers

private extension View {
    /// Merges the row into one accessibility element carrying `value` (e.g. "Selected", "Completed"),
    /// or leaves the view unchanged when `value` is `nil`.
    @ViewBuilder
    func combinedAccessibilityValue(_ value: String?) -> some View {
        if let value {
            accessibilityElement(children: .combine)
                .accessibilityValue(value)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyingModifier(_ modifier: AnyViewModifier?) -> some View {
        if let modifier {
            self.modifier(modifier)
        } else {
            self
        }
    }
}

// MARK: - Previews

#if DEBUG

private struct CardItemPreviewSamples: View {
    var body: some View {
        VStack(spacing: 16) {
            CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "sparkles")), size: .size24),
                title: CardItemText("Claude", font: .bodyRegular),
                titleDetails: [CardItemText("Sonnet 4.6", font: .bodyRegular), CardItemText("· PLUS", font: .footnoteRegular)],
                text: CardItemText("Uses limits faster", font: .footnoteRegular),
                trailing: .checkmark(Color(designSystemColor: .accentPrimary)))

            CardItem(
                icon: CardItemIcon(position: .topLeading, visual: .image(Image(systemName: "dollarsign.circle.fill")), size: .size56, spacing: 4),
                title: CardItemText("Recover financial losses", font: .headline),
                text: CardItemText("""
                    We'll work with financial institutions to help reverse any fraudulent \
                    transactions, and we'll reimburse certain out-of-pocket expenses*** in the \
                    event that you become a victim of identity theft or fraud.
                    """, font: .subheadRegular))

            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "lock.shield.fill")), size: .size24),
                title: CardItemText("VPN", font: .bodyRegular),
                text: CardItemText("Get an extra layer of online protection with the VPN built for speed and simplicity.", font: .footnoteRegular),
                trailing: .chevron(Color(designSystemColor: .iconsTertiary)))
        }
        .padding()
    }
}

private struct CardItemSparseSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                CardItem(
                    icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "lock.shield.fill"))),
                    title: CardItemText("DuckDuckGo VPN", font: .bodyRegular))

                CardItem(title: CardItemText("Open settings", font: .headline), trailing: .chevron(Color(designSystemColor: .iconsTertiary)))

                CardItem(
                    icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "person.fill"))),
                    title: CardItemText("Account", font: .headline),
                    text: CardItemText("Manage your account", font: .footnoteRegular),
                    trailing: .chevron(Color(designSystemColor: .iconsTertiary)))

                CardItem(title: CardItemText("Advanced Models", font: .headline), titleDetails: [CardItemText("· PLUS", font: .footnoteRegular)])

                CardItem(title: CardItemText("Title only", font: .headline))
            }
            .background(Color(designSystemColor: .surface))

            Group {
                CardItem(text: CardItemText("Body text only — no icon, no title.", font: .footnoteRegular))

                CardItem(icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "star.fill"))))

                CardItem(
                    icon: CardItemIcon(position: .topLeading, visual: .image(Image(systemName: "star.fill")), spacing: 4),
                    title: CardItemText("Top-leading icon, no body", font: .headline))

                CardItem(overline: CardItemText("OVERLINE", font: .footnoteRegular), title: CardItemText("Overline + title", font: .headline))

                CardItem()
            }
            .background(Color(designSystemColor: .surface))
        }
        .padding()
    }
}

private struct PreviewBlur: ViewModifier {
    func body(content: Content) -> some View {
        content.blur(radius: 6)
    }
}

private struct PreviewDim: ViewModifier {
    func body(content: Content) -> some View {
        content.opacity(0.3)
    }
}

private struct CardItemModifierSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "eye.slash.fill")), size: .size24),
                overline: CardItemText("YOUR IP ADDRESS", font: .footnoteRegular),
                title: CardItemText("31.120.130.50", font: .bodyRegular, modifier: AnyViewModifier(PreviewBlur())),
                text: CardItemText("Madrid, Spain", font: .footnoteRegular, modifier: AnyViewModifier(PreviewBlur())))

            CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "moon.fill")), size: .size24),
                title: CardItemText("Dimmed title", font: .headline, modifier: AnyViewModifier(PreviewDim())),
                text: CardItemText("Body stays untouched", font: .footnoteRegular))
        }
        .padding()
    }
}

/// Showcases ``CardItemText``'s optional inline secondary run (`secondaryText` / `secondaryColor`) — e.g. a
/// "(Nearest)" indicator tinted differently from the body — versus the same body text without one.
private struct CardItemSecondaryTextSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "location.fill")), size: .size24),
                overline: CardItemText("NEW IP ADDRESS", font: .footnoteRegular),
                title: CardItemText("45.132.71.9", font: .bodyRegular),
                text: CardItemText("🇪🇸 Valencia, Spain", font: .footnoteRegular,
                                   color: Color(designSystemColor: .textPrimary),
                                   secondaryText: "(Nearest)",
                                   secondaryColor: Color(designSystemColor: .textSecondary)))

            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "location.fill")), size: .size24),
                overline: CardItemText("NEW IP ADDRESS", font: .footnoteRegular),
                title: CardItemText("45.132.71.9", font: .bodyRegular),
                text: CardItemText("🇪🇸 Valencia, Spain", font: .footnoteRegular,
                                   color: Color(designSystemColor: .textPrimary)))
        }
        .padding()
    }
}

#Preview("Light") {
    CardItemPreviewSamples()
}

#Preview("Dark") {
    CardItemPreviewSamples()
        .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    CardItemPreviewSamples()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Sparse fields") {
    CardItemSparseSamples()
}

#Preview("Modifiers") {
    CardItemModifierSamples()
}

#Preview("Secondary text") {
    CardItemSecondaryTextSamples()
}

#endif

#endif
