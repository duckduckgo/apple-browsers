//
//  MenuItemWithBadge.swift
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

import Cocoa
import Common
import SwiftUI
import DesignResourcesKit

// MARK: - Menu Item Badge Constants

/// Constants for configuring the appearance and layout of menu item badges.
struct MenuItemWithBadgeConstants {
    /// Corner radius for the asymmetric rounded corners (top-left and bottom-right only)
    static let cornerRadius: CGFloat = 6

    /// Fixed height of the badge
    static let height: CGFloat = 16

    /// Top padding inside the badge
    static let paddingTop: CGFloat = 3

    /// Right padding inside the badge
    static let paddingRight: CGFloat = 7

    /// Bottom padding inside the badge
    static let paddingBottom: CGFloat = 3

    /// Left padding inside the badge
    static let paddingLeft: CGFloat = 7

    /// Distance from the right edge of the menu item
    static let rightMargin: CGFloat = 8

    // MARK: - Menu Item Layout Constants

    /// Corner radius for the menu item hover background
    static let menuItemCornerRadius: CGFloat = AppVersion.isLiquidGlassSupported ? 7 : 4

    /// Horizontal padding for the menu item hover background
    static let menuItemHorizontalPadding: CGFloat = 5

    /// Size of the menu item icon
    static let iconSize: CGFloat = 12

    /// Spacing between icon and title text
    static let iconTitleSpacing: CGFloat = 6

    /// Spacing between title and badge
    static let titleBadgeSpacing: CGFloat = 16

    /// Left padding for the icon
    static let iconLeftPadding: CGFloat = 16

    /// Right padding for the badge
    static let badgeRightPadding: CGFloat = 14

    // MARK: - Menu Item Hosting View Constants

    /// Default height for the menu item hosting view
    static let hostingViewHeight: CGFloat = AppVersion.isLiquidGlassSupported ? 24 : 22

    static let hoverColor: Color = {
        if #available(macOS 12.0, *) {
            return Color(nsColor: .selectedContentBackgroundColor)
        }
        return .menuItemHover
    }()

    /// The cursor-hover highlight for a designed row — `controlAccentColor` rather than
    /// `hoverColor` (`selectedContentBackgroundColor`) above: that semantic color is designed to be
    /// viewed through AppKit's menu vibrancy/blur material — filled flatly here it renders visibly
    /// more indigo/purple than the vivid blue AppKit paints for a plain, view-less `NSMenuItem`
    /// (e.g. the native reasoning-effort menu). The flat accent color matches that native look.
    /// Shared by `ModelMenuRowView` and `SubscriberExclusiveHeaderView` so both highlight identically.
    static let cursorHighlightColor = Color(nsColor: .controlAccentColor)

    /// Vertical inset of the highlight/selection background, which also creates the visible gap
    /// between adjacent rows.
    static let rowVerticalInset: CGFloat = 3

}

// MARK: - Custom Badge Shape

/// A custom SwiftUI shape that creates a rectangle with asymmetric corner rounding.
///
/// This shape is specifically designed for badges and implements the following corner pattern:
/// - Top-left: Rounded with the specified corner radius
/// - Top-right: Square (no rounding)
/// - Bottom-left: Square (no rounding)
/// - Bottom-right: Rounded with the specified corner radius
struct BadgeShape: Shape {
    // Cache the path since it's the same for all badges with the same corner radius
    private static var cachedPath: Path?
    private static var cachedRect: CGRect = .zero

    /// Creates the path for the badge shape with asymmetric corner rounding.
    ///
    /// - Parameter rect: The rectangle bounds within which to draw the shape
    /// - Returns: A Path representing the badge shape with asymmetric corners
    func path(in rect: CGRect) -> Path {
        // Return cached path if available and rect hasn't changed significantly
        if let cached = Self.cachedPath,
           abs(Self.cachedRect.width - rect.width) < 0.1,
           abs(Self.cachedRect.height - rect.height) < 0.1 {
            return cached
        }

        var path = Path()
        let radius = MenuItemWithBadgeConstants.cornerRadius

        // Start from top-left corner (rounded)
        path.move(to: CGPoint(x: radius, y: 0))

        // Top edge to top-right corner (square)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))

        // Right edge to bottom-right corner (rounded)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                   radius: radius, startAngle: .zero, endAngle: .degrees(90), clockwise: false)

        // Bottom edge to bottom-left corner (square)
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))

        // Left edge to top-left corner (rounded)
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(center: CGPoint(x: radius, y: radius),
                   radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()

        // Cache the path for reuse
        Self.cachedPath = path
        Self.cachedRect = rect

        return path
    }
}

// MARK: - Badge Component

/// A SwiftUI view that displays a badge with text, using the design system colors and asymmetric corner rounding.
///
/// The badge has a distinctive visual design with:
/// - Yellow background color from the design system
/// - Asymmetric corner rounding (only top-left and bottom-right corners are rounded)
/// - Asymmetric padding for optimal text placement
/// - Primary text color that adapts to the system appearance
struct BadgeView: View {
    /// The text content to display in the badge
    let text: String

    /// `true` rounds all four corners equally (e.g. the omnibar's "Try for free"/"Upgrade" tags);
    /// `false` (default) keeps the asymmetric shape used by the PLUS/PRO/BETA/free-trial tags
    /// elsewhere in the app.
    var hasUniformCorners: Bool = false
    /// `true` once the omnibar's shared impression cap is reached — keeps the badge (and its tap
    /// action) in place but swaps the attention-grabbing yellow for a neutral fill, per the Ship
    /// Review decision to reduce long-term annoyance without removing the entry point. Only
    /// applies to the uniform-corner style; other badges using this view aren't subject to the cap.
    var isMuted: Bool = false

    // Cache commonly used styling values to avoid repeated calculations
    private static let badgeFont = Font.system(size: 11, weight: .bold)
    private static let badgeShape = BadgeShape()

    var body: some View {
        Text(text)
            .font(Self.badgeFont)
            .foregroundColor(isMuted ? Color(designSystemColor: .textPrimary) : .black)
            .padding(.top, MenuItemWithBadgeConstants.paddingTop)
            .padding(.bottom, MenuItemWithBadgeConstants.paddingBottom)
            .padding(.leading, MenuItemWithBadgeConstants.paddingLeft)
            .padding(.trailing, MenuItemWithBadgeConstants.paddingRight)
            .frame(height: MenuItemWithBadgeConstants.height)
            .background(badgeBackground)
    }

    @ViewBuilder
    private var badgeBackground: some View {
        if hasUniformCorners {
            RoundedRectangle(cornerRadius: MenuItemWithBadgeConstants.cornerRadius)
                .fill(isMuted ? Color(designSystemColor: .controlsFillSecondary) : Self.tryForFreeBadgeColor)
        } else {
            Self.badgeShape.fill(Color(baseColor: .yellow60))
        }
    }

    /// Figma's "Pollen 300" — `RebrandingColor.Pollen.pollen30` on this palette's 0-100 (rather
    /// than Figma's 50-900) step convention.
    private static let tryForFreeBadgeColor = RebrandingColor.Pollen.pollen30
}

// MARK: - Menu Item with Badge

/// A complete menu item view that displays an icon, title, and badge with proper hover behavior.
///
/// This view replicates the native menu item appearance while adding a custom badge.
/// It includes:
/// - Native-style hover highlighting with accent color background
/// - Proper spacing and alignment for all components
/// - Dynamic text color that changes on hover (white on hover, primary otherwise)
/// - Gesture handling for menu item selection
struct MenuItemWithBadge: View {
    /// The icon to display on the left side of the menu item
    let leftImage: NSImage

    /// The main title text of the menu item
    let title: String

    /// The text to display in the badge
    let badgeText: String

    /// Callback executed when the menu item is selected
    var onTapMenuItem: () -> Void

    /// Environment variable that tracks the current system color scheme (light or dark mode)
    @Environment(\.colorScheme) var colorScheme

    /// Tracks whether the menu item is currently being hovered
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            // Background highlight that appears on hover
            RoundedRectangle(cornerRadius: MenuItemWithBadgeConstants.menuItemCornerRadius)
                .fill(isHovered ? MenuItemWithBadgeConstants.hoverColor : Color.clear)
                .padding([.leading, .trailing], MenuItemWithBadgeConstants.menuItemHorizontalPadding)
                .frame(maxWidth: .infinity)

            // Main content layout
            HStack(spacing: 0) {
                // Left icon
                Image(nsImage: leftImage)
                    .resizable()
                    .foregroundColor(isHovered ? .white : .menuItemForegroundColor(for: colorScheme))
                    .frame(width: MenuItemWithBadgeConstants.iconSize, height: MenuItemWithBadgeConstants.iconSize)
                    .padding(.trailing, MenuItemWithBadgeConstants.iconTitleSpacing)
                    .padding(.leading, MenuItemWithBadgeConstants.iconLeftPadding)

                // Menu item title
                Text(title)
                    .foregroundColor(isHovered ? .white : .menuItemForegroundColor(for: colorScheme))
                    .lineLimit(1)
                    .frame(alignment: .leading)

                Spacer(minLength: MenuItemWithBadgeConstants.titleBadgeSpacing)

                // Badge on the right side
                BadgeView(text: badgeText)
                    .fixedSize()  // Prevent badge from being compressed
                    .padding(.trailing, MenuItemWithBadgeConstants.badgeRightPadding)
            }
            .frame(maxWidth: .infinity)  // Allow HStack to expand to full menu width
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTapMenuItem()
        }
    }
}

/// Extension providing dynamic color support for menu item foreground colors.
/// This is needed to match the macOS system menu colors.
private extension Color {

    /// Light mode color value using Display P3 color space. RGB values: (36, 36, 35).
    private static let light = Color(.displayP3, red: 36/255.0, green: 36/255.0, blue: 35/255.0)

    /// Dark mode color value using Display P3 color space. RGB values: (223, 223, 223).
    private static let dark = Color(.displayP3, red: 223/255.0, green: 223/255.0, blue: 223/255.0)

    /// Returns the appropriate menu item foreground color based on the current color scheme.
    ///
    /// - Parameter colorScheme: The current color scheme from the SwiftUI environment
    /// - Returns: A `Color` instance appropriate for the given color scheme
    ///
    /// - **Light mode**: RGB(36, 36, 35) - Dark gray for readability on light backgrounds
    /// - **Dark mode**: RGB(223, 223, 223) - Light gray for readability on dark backgrounds
    static func menuItemForegroundColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}

// MARK: - NSMenuItem Badge Extension

extension NSMenuItem {

    // Cache for reusable hosting view configurations
    private static let emptyView = NSView()

    /// Creates a new menu item with a badge.
    ///
    /// This factory method creates a complete menu item that includes:
    /// - An icon on the left side
    /// - A title in the center
    /// - A badge on the right side with the specified text
    /// - Hover behavior that matches native menu items
    /// - Action handling that integrates with the target-action pattern
    ///
    /// - Parameters:
    ///   - title: The main text to display in the menu item
    ///   - badgeText: The text to display in the badge (e.g., "TRY FOR FREE")
    ///   - action: The selector to call when the menu item is selected
    ///   - target: The object that will receive the action message
    ///   - image: The icon to display on the left side of the menu item
    ///   - menu: The menu instance to dismiss after action (optional)
    /// - Returns: A configured NSMenuItem with the badge view embedded
    static func createMenuItemWithBadge(title: String, badgeText: String, action: Selector, target: AnyObject, image: NSImage, menu: NSMenu) -> NSMenuItem {
        let menuItem = NSMenuItem(action: action)
        menuItem.target = target

        weak let weakTarget = target
        let menuAction = action

        let badgeView = MenuItemWithBadge(leftImage: image, title: title, badgeText: badgeText) {
            menuItem.view = Self.emptyView

            // Dismiss the menu
            menu.cancelTracking()

            // Execute the action
            if let target = weakTarget {
                DispatchQueue.main.async {
                    _ = target.perform(menuAction, with: menuItem)
                }
            }
        }

        let hostingView = NSHostingView(rootView: badgeView)
        hostingView.frame.size.height = MenuItemWithBadgeConstants.hostingViewHeight
        // Initial width
        let requiredWidth = ceil(hostingView.fittingSize.width)
        hostingView.frame.size.width = requiredWidth
        // Allow width to expand if menu gets wider
        hostingView.autoresizingMask = [.width]
        menu.minimumWidth = max(menu.minimumWidth, requiredWidth)

        menuItem.view = hostingView

        return menuItem
    }
}

// MARK: - Subscriber Exclusive Header

/// A menu header row that shows a muted title ("Subscriber exclusive.") followed by a yellow
/// "TRY FOR FREE" / "UPGRADE" badge — the same `BadgeView` used for the PLUS/PRO/BETA tags,
/// standardized across the model picker and the reasoning-effort picker's gated row per design
/// review. The whole row (not just the badge) launches the subscription flow and highlights on
/// hover, matching `ModelMenuRowView`'s fully-interactive rows — there's no separate "select vs.
/// gate" distinction here, tapping anywhere always leads to the same upsell dialog. Used at the
/// top of the gated section of the Duck.ai model picker.
struct SubscriberExclusiveHeaderView: View {
    /// Muted leading label.
    let title: String

    /// Trailing badge text.
    let badgeText: String

    /// See `BadgeView.isMuted`.
    var isBadgeMuted: Bool = false

    /// Callback executed when the row is tapped, anywhere.
    var onTap: () -> Void

    @State private var isHovered = false

    private var titleColor: Color {
        isHovered ? .white : Color(designSystemColor: .textPrimary)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MenuItemWithBadgeConstants.menuItemCornerRadius)
                .fill(isHovered ? MenuItemWithBadgeConstants.cursorHighlightColor : .clear)
                .padding([.leading, .trailing], MenuItemWithBadgeConstants.menuItemHorizontalPadding)
                .padding(.vertical, MenuItemWithBadgeConstants.rowVerticalInset)

            // Padding lives on the leading/trailing leaves themselves (title, badge), not wrapped
            // around the whole HStack — matching ModelMenuRowView's structure exactly, rather than
            // trusting that two differently-shaped layouts happen to resolve to the same pixel
            // position once both get stretched to the menu's final width. They didn't.
            HStack(spacing: 8) {
                Text(title)
                    .foregroundColor(titleColor)
                    .padding(.leading, MenuItemWithBadgeConstants.iconLeftPadding)
                Spacer(minLength: 8)
                BadgeView(text: badgeText, hasUniformCorners: true, isMuted: isBadgeMuted)
                    .fixedSize()
                    .padding(.trailing, MenuItemWithBadgeConstants.badgeRightPadding)
            }
            .frame(maxWidth: .infinity)
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matches ModelMenuRowView's own single-line row height, not the shared, shorter
        // hostingViewHeight (used by unrelated menu badges elsewhere) — with no background fill
        // this was never noticeably short, but once hover added a highlight rectangle here too,
        // the shorter height read as a cramped, undersized version of the rows around it.
        .frame(height: ModelMenuRowView.height(hasSubtitle: false))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}

extension NSMenuItem {

    /// Creates a header row with a muted title and a trailing badge. The whole row is interactive:
    /// tapping anywhere dismisses the menu and performs `action` on `target`.
    static func createSubscriberExclusiveHeader(title: String, badgeText: String, isBadgeMuted: Bool = false, action: Selector, target: AnyObject, menu: NSMenu) -> NSMenuItem {
        let menuItem = NSMenuItem(action: action)
        menuItem.target = target

        weak let weakTarget = target
        let menuAction = action

        let headerView = SubscriberExclusiveHeaderView(title: title, badgeText: badgeText, isBadgeMuted: isBadgeMuted) {
            menu.cancelTracking()
            if let target = weakTarget {
                DispatchQueue.main.async {
                    _ = target.perform(menuAction, with: menuItem)
                }
            }
        }

        let hostingView = NSHostingView(rootView: headerView)
        hostingView.frame.size.height = ModelMenuRowView.height(hasSubtitle: false)
        let requiredWidth = ceil(hostingView.fittingSize.width)
        hostingView.frame.size.width = requiredWidth
        hostingView.autoresizingMask = [.width]
        menu.minimumWidth = max(menu.minimumWidth, requiredWidth)

        menuItem.view = hostingView

        return menuItem
    }
}

// MARK: - Model Picker Row

/// A designed model-picker row matching the Duck.ai model menu: leading provider icon, a two-tone
/// title (bold family + regular variant), an optional descriptive subtitle, and a trailing grey
/// label (tier / "BETA"). Gated rows render dimmed but remain interactive (they route to the
/// subscription flow). The selected row shows a subtle highlight.
struct ModelMenuRowView: View {
    let icon: NSImage?
    let boldTitle: String
    let regularTitle: String
    let subtitle: String?
    /// The reasoning picker's native sibling rows set their subtitle at 11pt; the model picker's
    /// own rows have always used 12pt. Defaulted so only the reasoning-picker call site needs to
    /// override it.
    let subtitleFontSize: CGFloat
    let trailingText: String?
    /// A yellow "TRY FOR FREE" / "UPGRADE" pill, shown instead of `trailingText` when non-nil —
    /// used for the reasoning picker's gated row (the model picker's own gated rows keep the plain
    /// PLUS/PRO `trailingText`; only their section header shows this badge).
    let trailingBadgeText: String?
    /// See `BadgeView.isMuted`.
    let isBadgeMuted: Bool
    /// `true` renders `boldTitle` semibold with `regularTitle` appended in regular weight (the
    /// model picker's "family + variant" look, e.g. "GPT-5.4" + "mini"). `false` renders the whole
    /// `boldTitle` string in regular weight — used for the reasoning picker's gated row, which has
    /// no family/variant split and must match its native siblings' regular-weight title.
    let emphasizesTitle: Bool
    let isSelected: Bool
    /// Gated (subscriber-only) models render dimmed — but a gated row offering its own upsell
    /// badge (the reasoning picker's gated effort) does not, matching the web model picker's
    /// convention that any row with a live CTA reads as fully available.
    let isDimmed: Bool
    /// Whether tapping *anywhere* on the row (not just a `trailingBadgeText` badge) does something.
    /// `true` both for a genuinely selectable row and for a gated row that still routes to the
    /// upsell dialog on tap — either way something happens, so the row also highlights on hover.
    /// `false` only for a row with no action at all (a gated model row, or a gated effort with the
    /// upsell feature flag off) — matching the web model picker, which shows no CTA in that case.
    let isInteractive: Bool
    var onTap: () -> Void
    /// Fires when `trailingBadgeText`'s badge is tapped, independent of `isInteractive`/`onTap` —
    /// the reasoning picker's gated row is a disabled row (dimmed, not selectable) that still
    /// needs its badge to open the upsell dialog.
    var onTapBadge: (() -> Void)?

    @State private var isHovered = false

    // singleLineHeight is only ever hit by model rows now (they dropped subtitles entirely; the
    // reasoning picker's rows always have one, via effort.subtitle, so they always take
    // twoLineHeight). It used to be 38 to avoid a visible jump against 46 when a model *did* have
    // a subtitle — with that case gone, it can be its own, shorter, single-line height.
    private static let singleLineHeight: CGFloat = 32
    private static let twoLineHeight: CGFloat = 46

    static func height(hasSubtitle: Bool) -> CGFloat {
        hasSubtitle ? twoLineHeight : singleLineHeight
    }

    /// `isInteractive` now covers both a genuinely selectable row and a gated row that still routes
    /// to the upsell dialog on tap (see `isInteractive`'s own doc comment) — either way, something
    /// happens when this row is tapped, so it highlights on hover like any other actionable row.
    private var isCursorHighlighted: Bool {
        isInteractive && isHovered
    }

    private var backgroundFill: Color {
        isCursorHighlighted ? MenuItemWithBadgeConstants.cursorHighlightColor : .clear
    }

    private var titleColor: Color {
        if isCursorHighlighted { return .white }
        return isDimmed ? Color(nsColor: .tertiaryLabelColor) : Color(nsColor: .labelColor)
    }

    private var subtitleColor: Color {
        isCursorHighlighted ? .white.opacity(0.85) : Color(nsColor: .secondaryLabelColor)
    }

    private var trailingColor: Color {
        isCursorHighlighted ? .white : Color(designSystemColor: .textSecondary)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MenuItemWithBadgeConstants.menuItemCornerRadius)
                .fill(backgroundFill)
                .padding([.leading, .trailing], MenuItemWithBadgeConstants.menuItemHorizontalPadding)
                .padding(.vertical, MenuItemWithBadgeConstants.rowVerticalInset)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Checkmark gutter — reserved on every row so titles align; the ✓ marks the
                    // selected model, matching the native reasoning-effort menu's selection indicator.
                    ZStack {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(titleColor)
                        }
                    }
                    .frame(width: 14)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)

                    Group {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .foregroundColor(titleColor)
                                .frame(width: 16, height: 16)
                        } else {
                            Color.clear.frame(width: 16, height: 16)
                        }
                    }
                    .padding(.trailing, MenuItemWithBadgeConstants.iconTitleSpacing)

                    VStack(alignment: .leading, spacing: 1) {
                        Group {
                            if emphasizesTitle {
                                Text(boldTitle).fontWeight(.semibold)
                                    + Text(regularTitle.isEmpty ? "" : " \(regularTitle)").fontWeight(.regular)
                            } else {
                                Text(boldTitle).fontWeight(.regular)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(titleColor)
                        .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: subtitleFontSize))
                                .foregroundColor(subtitleColor)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: MenuItemWithBadgeConstants.titleBadgeSpacing)

                if let trailingBadgeText {
                    BadgeView(text: trailingBadgeText, hasUniformCorners: true, isMuted: isBadgeMuted)
                        .fixedSize()
                        .padding(.trailing, MenuItemWithBadgeConstants.badgeRightPadding)
                        .onTapGesture { onTapBadge?() }
                } else if let trailingText {
                    // Matches BadgeView's own two-part right inset — its text sits paddingRight
                    // *inside* the yellow box, which itself sits badgeRightPadding from the row
                    // edge — so the plain PLUS/PRO/BETA word lines up with the badge's word, not
                    // just with its box. Without the first padding, the box edges align but the
                    // words don't: the badge's background eats space its text doesn't have.
                    Text(trailingText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(trailingColor)
                        .padding(.leading, MenuItemWithBadgeConstants.paddingLeft)
                        .padding(.trailing, MenuItemWithBadgeConstants.paddingRight)
                        .padding(.trailing, MenuItemWithBadgeConstants.badgeRightPadding)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height(hasSubtitle: subtitle != nil))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // The whole row is the tap target — including the gap before the trailing content and
        // the trailing PLUS/PRO/BETA label itself — not just the icon/title's own narrow bounding
        // box. Gating on isInteractive here (rather than allowsHitTesting on this view) matters:
        // allowsHitTesting(false) at this level would also block the trailing badge's own,
        // independent onTapGesture below it, since it's a descendant of this view.
        .onTapGesture { if isInteractive { onTap() } }
    }
}

extension NSMenuItem {

    /// Creates a designed model-picker row (see `ModelMenuRowView`). On tap it dismisses the menu
    /// and performs `action` on `target`, so the caller can select the model or route a gated
    /// selection to the subscription flow. `badgeAction`, when given, fires independently from a
    /// tap on the trailing badge specifically — for a row that's otherwise disabled (`isInteractive`
    /// false) but still needs its badge to open the upsell dialog.
    static func createModelRow(icon: NSImage?,
                               boldTitle: String,
                               regularTitle: String,
                               subtitle: String?,
                               subtitleFontSize: CGFloat = 12,
                               trailingText: String?,
                               trailingBadgeText: String? = nil,
                               isBadgeMuted: Bool = false,
                               emphasizesTitle: Bool = true,
                               isSelected: Bool,
                               isDimmed: Bool,
                               isInteractive: Bool,
                               action: Selector,
                               badgeAction: Selector? = nil,
                               target: AnyObject,
                               menu: NSMenu) -> NSMenuItem {
        let menuItem = NSMenuItem(action: action)
        menuItem.target = target
        // Gated rows are non-interactive: not clickable, not keyboard-selectable — unless a
        // badgeAction is present, in which case AppKit must not treat the item as fully disabled,
        // or it may withhold events from the custom view entirely, including from the badge.
        menuItem.isEnabled = isInteractive || badgeAction != nil

        weak let weakTarget = target
        let menuAction = action

        let row = ModelMenuRowView(icon: icon,
                                    boldTitle: boldTitle,
                                    regularTitle: regularTitle,
                                    subtitle: subtitle,
                                    subtitleFontSize: subtitleFontSize,
                                    trailingText: trailingText,
                                    trailingBadgeText: trailingBadgeText,
                                    isBadgeMuted: isBadgeMuted,
                                    emphasizesTitle: emphasizesTitle,
                                    isSelected: isSelected,
                                    isDimmed: isDimmed,
                                    isInteractive: isInteractive,
                                    onTap: {
                                        menu.cancelTracking()
                                        if let target = weakTarget {
                                            DispatchQueue.main.async {
                                                _ = target.perform(menuAction, with: menuItem)
                                            }
                                        }
                                    },
                                    onTapBadge: badgeAction.map { badgeSelector in
                                        {
                                            menu.cancelTracking()
                                            if let target = weakTarget {
                                                DispatchQueue.main.async {
                                                    _ = target.perform(badgeSelector, with: menuItem)
                                                }
                                            }
                                        }
                                    })

        let hostingView = NSHostingView(rootView: row)
        hostingView.frame.size.height = ModelMenuRowView.height(hasSubtitle: subtitle != nil)
        let requiredWidth = ceil(hostingView.fittingSize.width)
        hostingView.frame.size.width = requiredWidth
        hostingView.autoresizingMask = [.width]
        menu.minimumWidth = max(menu.minimumWidth, requiredWidth)

        menuItem.view = hostingView

        return menuItem
    }
}
