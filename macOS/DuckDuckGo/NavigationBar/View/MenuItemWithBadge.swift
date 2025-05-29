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
    static let paddingBottom: CGFloat = 4

    /// Left padding inside the badge
    static let paddingLeft: CGFloat = 7

    /// Distance from the right edge of the menu item
    static let rightMargin: CGFloat = 8

    // MARK: - Menu Item Layout Constants

    /// Corner radius for the menu item hover background
    static let menuItemCornerRadius: CGFloat = 4

    /// Horizontal padding for the menu item hover background
    static let menuItemHorizontalPadding: CGFloat = 5

    /// Size of the menu item icon
    static let iconSize: CGFloat = 16

    /// Spacing between icon and title text
    static let iconTitleSpacing: CGFloat = 6

    /// Left padding for the icon
    static let iconLeftPadding: CGFloat = 14

    /// Right padding for the badge
    static let badgeRightPadding: CGFloat = 14

    // MARK: - Menu Item Hosting View Constants

    /// Default width for the menu item hosting view
    static let hostingViewWidth: CGFloat = 250

    /// Default height for the menu item hosting view
    static let hostingViewHeight: CGFloat = 22
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
    /// Creates the path for the badge shape with asymmetric corner rounding.
    ///
    /// - Parameter rect: The rectangle bounds within which to draw the shape
    /// - Returns: A Path representing the badge shape with asymmetric corners
    func path(in rect: CGRect) -> Path {
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

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.textPrimary)
            .padding(.top, MenuItemWithBadgeConstants.paddingTop)
            .padding(.bottom, MenuItemWithBadgeConstants.paddingBottom)
            .padding(.leading, MenuItemWithBadgeConstants.paddingLeft)
            .padding(.trailing, MenuItemWithBadgeConstants.paddingRight)
            .background(BadgeShape().fill(Color(baseColor: .yellow60)))
    }
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

    /// Tracks whether the menu item is currently being hovered
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            // Background highlight that appears on hover
            RoundedRectangle(cornerRadius: MenuItemWithBadgeConstants.menuItemCornerRadius)
                .fill(isHovered ? Color.accentColor : Color.clear)
                .padding([.leading, .trailing], MenuItemWithBadgeConstants.menuItemHorizontalPadding)
                .frame(maxWidth: .infinity)

            // Main content layout
            HStack(spacing: 0) {
                // Left icon
                Image(nsImage: leftImage)
                    .resizable()
                    .foregroundColor(isHovered ? .white : .primary)
                    .frame(width: MenuItemWithBadgeConstants.iconSize, height: MenuItemWithBadgeConstants.iconSize)
                    .padding(.trailing, MenuItemWithBadgeConstants.iconTitleSpacing)
                    .padding(.leading, MenuItemWithBadgeConstants.iconLeftPadding)

                // Menu item title
                Text(title)
                    .foregroundColor(isHovered ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Badge on the right side
                BadgeView(text: badgeText)
                    .padding(.trailing, MenuItemWithBadgeConstants.badgeRightPadding)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTapMenuItem()
        }
    }
}

// MARK: - NSMenuItem Badge Extension

extension NSMenuItem {

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
    static func createMenuItemWithBadge(title: String, badgeText: String, action: Selector, target: AnyObject, image: NSImage, menu: NSMenu? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = target

        let badgeView = MenuItemWithBadge(leftImage: image, title: title, badgeText: badgeText) {
            if let target = menuItem.target {
                _ = target.perform(menuItem.action, with: menuItem)
            }
            // Dismiss the menu after performing the action
            menu?.cancelTracking()
        }

        let hostingView = NSHostingView(rootView: badgeView)
        hostingView.frame = NSRect(x: 0, y: 0, width: MenuItemWithBadgeConstants.hostingViewWidth, height: MenuItemWithBadgeConstants.hostingViewHeight)
        hostingView.autoresizingMask = [.width, .height]

        menuItem.view = hostingView

        return menuItem
    }
} 
