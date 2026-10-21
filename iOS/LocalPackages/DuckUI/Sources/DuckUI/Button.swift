//
//  Button.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import UIComponents

// MARK: - Shared colors

struct PrimaryButtonColors {
    let standard: Color
    let pressed: Color
    let text: Color

    static let primary = PrimaryButtonColors(
        standard: Color(designSystemColor: .accentPrimary),
        pressed: Color(designSystemColor: .accentTertiary),
        text: Color(designSystemColor: .accentContentPrimary)
    )

    static let brand = PrimaryButtonColors(
        standard: Color(designSystemColor: .accentBrandPrimary),
        pressed: Color(designSystemColor: .accentBrandTertiary),
        text: Color(designSystemColor: .accentBrandContentPrimary)
    )

    static let destructive = PrimaryButtonColors(
        standard: Color(designSystemColor: .destructivePrimary),
        pressed: Color(designSystemColor: .destructiveTertiary),
        text: Color(designSystemColor: .destructiveContentPrimary)
    )
}

// MARK: - Typography helpers

private extension View {
    /// Caps Dynamic Type at `.accessibility3` so button layouts stay readable.
    func ddgButtonDynamicTypeCap() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private func buttonFont(compact: Bool) -> Font {
    .system(compact ? .subheadline : .body).weight(.medium)
}

// MARK: - Body builders

/// `forcePressed` lets debug/preview surfaces render the pressed appearance without a
/// live press gesture. Default to false in production.
@ViewBuilder
private func makePrimaryBody(
    configuration: ButtonStyleConfiguration,
    colors: PrimaryButtonColors,
    disabled: Bool,
    compact: Bool,
    fullWidth: Bool,
    isFreeform: Bool = false,
    forcePressed: Bool = false
) -> some View {
    let isPressed = configuration.isPressed || forcePressed
    let backgroundColor = isPressed ? colors.pressed : colors.standard

    configuration.label
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .font(buttonFont(compact: compact))
        .foregroundColor(colors.text)
        .if(!isFreeform) { view in
            view
                .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
                .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
                .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
        }
        .background(disabled ? backgroundColor.opacity(Consts.disabledOpacity) : backgroundColor)
        .clipShape(Capsule())
        .ddgButtonDynamicTypeCap()
}

// MARK: - Primary

public struct PrimaryButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool
    let isFreeform: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, isFreeform: Bool = false, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.isFreeform = isFreeform
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        makePrimaryBody(
            configuration: configuration,
            colors: .primary,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth,
            isFreeform: isFreeform,
            forcePressed: pressed
        )
    }
}

// MARK: - Brand (Mandarin orange)

public struct BrandButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        makePrimaryBody(
            configuration: configuration,
            colors: .brand,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth,
            forcePressed: pressed
        )
    }
}

// MARK: - Primary Destructive

public struct PrimaryDestructiveButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        makePrimaryBody(
            configuration: configuration,
            colors: .destructive,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth,
            forcePressed: pressed
        )
    }
}

// MARK: - Secondary Destructive

public struct SecondaryDestructiveButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let destructiveColor = Color(designSystemColor: .destructivePrimary)
        let pressedDestructiveColor = Color(designSystemColor: .destructiveTertiary)
        let isPressed = configuration.isPressed || pressed
        let foregroundColor = disabled
            ? destructiveColor.opacity(Consts.disabledOpacity)
            : (isPressed ? pressedDestructiveColor : destructiveColor)
        let backgroundColor: Color = {
            if disabled { return Color(singleUseColor: .rebranding(.buttonsSecondaryDisabledBackground)) }
            return isPressed
                ? Color(singleUseColor: .rebranding(.buttonsSecondaryPressed))
                : Color(singleUseColor: .rebranding(.buttonsSecondaryDefault))
        }()

        return configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(buttonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
            .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
            .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
            .background(backgroundColor)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Destructive Ghost (transparent + destructive red text)

public struct DestructiveGhostButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let destructiveColor = Color(designSystemColor: .destructivePrimary)
        let pressedTextColor = Color(designSystemColor: .destructiveTertiary)
        let isPressed = configuration.isPressed || pressed

        return configuration.label
            .font(buttonFont(compact: compact))
            .foregroundColor(isPressed ? pressedTextColor : destructiveColor)
            .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
            .padding(.horizontal)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
            .background(isPressed ? Color(designSystemColor: .destructiveGlowPrimary) : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(disabled ? Consts.disabledOpacity : 1)
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Secondary (deprecated, prefer SecondaryWireButtonStyle)

public struct SecondaryButtonStyle: ButtonStyle {
    let compact: Bool
    let pressed: Bool

    public init(compact: Bool = false, pressed: Bool = false) {
        self.compact = compact
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let accent = Color(designSystemColor: .accentPrimary)
        let isPressed = configuration.isPressed || pressed
        return configuration.label
            .font(buttonFont(compact: compact))
            .foregroundColor(isPressed ? accent.opacity(Consts.pressedOpacity) : accent)
            .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
            .padding(.horizontal)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Secondary Fill

public struct SecondaryFillButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool
    let isFreeform: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, isFreeform: Bool = false, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.isFreeform = isFreeform
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        let foregroundColor = disabled
            ? Color(singleUseColor: .rebranding(.buttonsSecondaryDisabledText))
            : Color(singleUseColor: .rebranding(.buttonsSecondaryText))
        let backgroundColor: Color = {
            if disabled { return Color(singleUseColor: .rebranding(.buttonsSecondaryDisabledBackground)) }
            return isPressed
                ? Color(singleUseColor: .rebranding(.buttonsSecondaryPressed))
                : Color(singleUseColor: .rebranding(.buttonsSecondaryDefault))
        }()

        return configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(buttonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .if(!isFreeform) { view in
                view
                    .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
                    .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
                    .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
            }
            .background(backgroundColor)
            .clipShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Ghost

public struct GhostButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        let foregroundColor = isPressed
            ? Color(designSystemColor: .accentTertiary)
            : Color(designSystemColor: .accentPrimary)
        return configuration.label
            .font(buttonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
            .padding(.horizontal)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
            .background(backgroundColor(isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(disabled ? Consts.disabledOpacity : 1)
            .ddgButtonDynamicTypeCap()
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .accentGlowPrimary) : .clear
    }
}

// MARK: - Ghost Alt

public struct GhostAltButtonStyle: ButtonStyle {
    let compact: Bool
    let pressed: Bool

    public init(compact: Bool = false, pressed: Bool = false) {
        self.compact = compact
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        return configuration.label
            .font(buttonFont(compact: compact))
            .foregroundColor(Color(singleUseColor: .rebranding(.textSecondary)))
            .padding(.vertical, compact ? Consts.compactVerticalPadding : nil)
            .padding(.horizontal)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.heightSmall : Consts.heightLarge)
            .background(backgroundColor(isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(singleUseColor: .rebranding(.controlsFillPrimary)) : .clear
    }
}

// MARK: - Constants

enum Consts {
    static let heightLarge: CGFloat = 50
    static let heightSmall: CGFloat = 40
    static let compactVerticalPadding: CGFloat = 8
    static let pressedOpacity: CGFloat = 0.7
    static let disabledOpacity: CGFloat = 0.36
}

// MARK: - Debug galleries

public struct ButtonStylesGallery: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("PrimaryButtonStyle") {
                    Button("Default") {}.buttonStyle(PrimaryButtonStyle())
                    Button("Disabled") {}.buttonStyle(PrimaryButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(PrimaryButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(PrimaryButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }

                section("BrandButtonStyle") {
                    Button("Default") {}.buttonStyle(BrandButtonStyle())
                    Button("Disabled") {}.buttonStyle(BrandButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(BrandButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(BrandButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(BrandButtonStyle(fullWidth: false))
                }

                section("PrimaryDestructiveButtonStyle") {
                    Button("Default") {}.buttonStyle(PrimaryDestructiveButtonStyle())
                    Button("Disabled") {}.buttonStyle(PrimaryDestructiveButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(PrimaryDestructiveButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(PrimaryDestructiveButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(PrimaryDestructiveButtonStyle(fullWidth: false))
                }

                section("DestructiveGhostButtonStyle") {
                    Button("Default") {}.buttonStyle(DestructiveGhostButtonStyle())
                    Button("Disabled") {}.buttonStyle(DestructiveGhostButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(DestructiveGhostButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(DestructiveGhostButtonStyle(compact: true))
                }

                section("SecondaryDestructiveButtonStyle") {
                    Button("Default") {}.buttonStyle(SecondaryDestructiveButtonStyle())
                    Button("Disabled") {}.buttonStyle(SecondaryDestructiveButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(SecondaryDestructiveButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(SecondaryDestructiveButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(SecondaryDestructiveButtonStyle(fullWidth: false))
                }

                section("SecondaryButtonStyle (deprecated)") {
                    Button("Default") {}.buttonStyle(SecondaryButtonStyle())
                    Button("Pressed") {}.buttonStyle(SecondaryButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(SecondaryButtonStyle(compact: true))
                }

                section("SecondaryFillButtonStyle") {
                    Button("Default") {}.buttonStyle(SecondaryFillButtonStyle())
                    Button("Disabled") {}.buttonStyle(SecondaryFillButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(SecondaryFillButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(SecondaryFillButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(SecondaryFillButtonStyle(fullWidth: false))
                }

                section("GhostButtonStyle") {
                    Button("Default") {}.buttonStyle(GhostButtonStyle())
                    Button("Disabled") {}.buttonStyle(GhostButtonStyle(disabled: true))
                    Button("Pressed") {}.buttonStyle(GhostButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(GhostButtonStyle(compact: true))
                }

                section("GhostAltButtonStyle") {
                    Button("Default") {}.buttonStyle(GhostAltButtonStyle())
                    Button("Pressed") {}.buttonStyle(GhostAltButtonStyle(pressed: true))
                    Button("Compact") {}.buttonStyle(GhostAltButtonStyle(compact: true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(colorScheme == .light ? Color(0xF2F1F1) : Color(0x1F1F1F))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textSecondary))
            content()
        }
    }
}

#if DEBUG
#Preview("Buttons / Light") {
    ButtonStylesGallery()
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
}

#Preview("Buttons / Dark") {
    ButtonStylesGallery()
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
}

#endif
