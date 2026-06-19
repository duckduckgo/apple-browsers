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
import DesignResourcesKitIcons
import UIComponents

// MARK: - Shared colors

private struct PrimaryButtonColors {
    let standard: Color
    let pressed: Color
    let disabled: Color
    let text: Color
    let textDisabled: Color

    static let primary = PrimaryButtonColors(
        standard: Color(designSystemColor: .buttonsPrimaryDefault),
        pressed: Color(designSystemColor: .buttonsPrimaryPressed),
        disabled: Color(designSystemColor: .buttonsPrimaryDisabled),
        text: Color(designSystemColor: .buttonsPrimaryText),
        textDisabled: Color(designSystemColor: .buttonsPrimaryTextDisabled)
    )

    static let destructive = PrimaryButtonColors(
        standard: Color(designSystemColor: .destructivePrimary),
        pressed: Color(designSystemColor: .buttonsDestructivePrimaryPressed),
        disabled: Color(designSystemColor: .destructivePrimary).opacity(0.36),
        text: Color(designSystemColor: .buttonsWhite),
        textDisabled: Color(designSystemColor: .buttonsWhite).opacity(0.36)
    )

    static let rebrandedPrimary = PrimaryButtonColors(
        standard: Color(designSystemColor: .accentPrimary),
        pressed: Color(designSystemColor: .accentTertiary),
        disabled: Color(designSystemColor: .accentPrimary),
        text: Color(designSystemColor: .accentContentPrimary),
        textDisabled: Color(designSystemColor: .accentContentPrimary)
    )

    static let rebrandedBrand = PrimaryButtonColors(
        standard: Color(designSystemColor: .accentBrandPrimary),
        pressed: Color(designSystemColor: .accentBrandTertiary),
        disabled: Color(designSystemColor: .accentBrandPrimary),
        text: Color(designSystemColor: .accentBrandContentPrimary),
        textDisabled: Color(designSystemColor: .accentBrandContentPrimary)
    )

    static let rebrandedDestructive = PrimaryButtonColors(
        standard: Color(designSystemColor: .destructivePrimary),
        pressed: Color(designSystemColor: .destructiveTertiary),
        disabled: Color(designSystemColor: .destructivePrimary),
        text: Color(designSystemColor: .destructiveContentPrimary),
        textDisabled: Color(designSystemColor: .destructiveContentPrimary)
    )
}

// MARK: - Typography helpers

private extension View {
    /// Caps Dynamic Type at `.accessibility3` so button layouts stay readable.
    func ddgButtonDynamicTypeCap() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private func legacyButtonFont() -> Font {
    Font(UIFont.daxButton())
}

private func rebrandedButtonFont(compact: Bool) -> Font {
    .system(compact ? .subheadline : .body).weight(.medium)
}

// MARK: - Body builders

/// `forcePressed` lets debug/preview surfaces render the pressed appearance without a
/// live press gesture. Default to false in production.
@ViewBuilder
private func makeLegacyPrimaryBody(
    configuration: ButtonStyleConfiguration,
    colors: PrimaryButtonColors,
    disabled: Bool,
    compact: Bool,
    fullWidth: Bool,
    forcePressed: Bool = false
) -> some View {
    let backgroundColor = disabled ? colors.disabled : colors.standard
    let foregroundColor = disabled ? colors.textDisabled : colors.text
    let isPressed = configuration.isPressed || forcePressed

    configuration.label
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .font(legacyButtonFont())
        .foregroundColor(foregroundColor)
        .padding(.vertical)
        .padding(.horizontal, fullWidth ? nil : 24)
        .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
        .background(isPressed ? colors.pressed : backgroundColor)
        .cornerRadius(Consts.legacyCornerRadius)
        .ddgButtonDynamicTypeCap()
}

@ViewBuilder
private func makeRebrandedPrimaryBody(
    configuration: ButtonStyleConfiguration,
    colors: PrimaryButtonColors,
    disabled: Bool,
    compact: Bool,
    fullWidth: Bool,
    forcePressed: Bool = false
) -> some View {
    let isPressed = configuration.isPressed || forcePressed
    let backgroundColor = isPressed ? colors.pressed : colors.standard

    configuration.label
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .font(rebrandedButtonFont(compact: compact))
        .foregroundColor(disabled ? colors.textDisabled : colors.text)
        .padding(.vertical)
        .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
        .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
        .background(disabled ? backgroundColor.opacity(Consts.disabledOpacity) : backgroundColor)
        .clipShape(Capsule())
        .ddgButtonDynamicTypeCap()
}

// MARK: - Primary

public struct PrimaryButtonStyleLegacy: ButtonStyle {
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
        makeLegacyPrimaryBody(
            configuration: configuration,
            colors: .primary,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth,
            forcePressed: pressed
        )
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
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

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            makeRebrandedPrimaryBody(
                configuration: configuration,
                colors: .rebrandedPrimary,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth,
                forcePressed: pressed
            )
        } else {
            PrimaryButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }
}

// MARK: - Brand (rebrand-only Mandarin orange; falls back to Primary in legacy mode)

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

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            makeRebrandedPrimaryBody(
                configuration: configuration,
                colors: .rebrandedBrand,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth,
                forcePressed: pressed
            )
        } else {
            // No "Brand" concept pre-rebrand; fall back to the standard primary blue.
            PrimaryButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }
}

// MARK: - Primary Destructive

public struct PrimaryDestructiveButtonStyleLegacy: ButtonStyle {
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
        makeLegacyPrimaryBody(
            configuration: configuration,
            colors: .destructive,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth,
            forcePressed: pressed
        )
    }
}

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

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            makeRebrandedPrimaryBody(
                configuration: configuration,
                colors: .rebrandedDestructive,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth,
                forcePressed: pressed
            )
        } else {
            PrimaryDestructiveButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }
}

// MARK: - Secondary Destructive

public struct SecondaryDestructiveButtonStyleLegacy: ButtonStyle {
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
        let disabledColor = destructiveColor.opacity(0.36)
        let borderColor = disabled ? disabledColor : destructiveColor
        let foregroundColor = disabled ? disabledColor : destructiveColor
        let pressedBackgroundColor = destructiveColor.opacity(0.1)
        let isPressed = configuration.isPressed || pressed

        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(legacyButtonFont())
            .foregroundColor(foregroundColor)
            .padding(.vertical)
            .padding(.horizontal, fullWidth ? nil : 24)
            .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(isPressed ? pressedBackgroundColor : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Consts.legacyCornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(Consts.legacyCornerRadius)
            .contentShape(RoundedRectangle(cornerRadius: Consts.legacyCornerRadius))
            .ddgButtonDynamicTypeCap()
    }
}

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

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            SecondaryDestructiveButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
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
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .padding(.vertical)
            .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
            .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            .background(backgroundColor)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Destructive Ghost (transparent + destructive red text)

public struct DestructiveGhostButtonStyleLegacy: ButtonStyle {
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
        let pressedTextColor = Color(designSystemColor: .buttonsDestructivePrimaryPressed)
        let isPressed = configuration.isPressed || pressed
        let foregroundColor = (isPressed ? pressedTextColor : destructiveColor).opacity(disabled ? Consts.disabledOpacity : 1)
        let pressedBackgroundColor = destructiveColor.opacity(0.1)

        return configuration.label
            .font(legacyButtonFont())
            .foregroundColor(foregroundColor)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(isPressed ? pressedBackgroundColor : .clear)
            .cornerRadius(Consts.legacyCornerRadius)
            .contentShape(Rectangle())
            .ddgButtonDynamicTypeCap()
    }
}

public struct DestructiveGhostButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.pressed = pressed
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            DestructiveGhostButtonStyleLegacy(disabled: disabled, compact: compact, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        let destructiveColor = Color(designSystemColor: .destructivePrimary)
        let pressedTextColor = Color(designSystemColor: .destructiveTertiary)
        let isPressed = configuration.isPressed || pressed

        return configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(isPressed ? pressedTextColor : destructiveColor)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            .background(isPressed ? Color(designSystemColor: .destructiveGlowPrimary) : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(disabled ? Consts.disabledOpacity : 1)
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Secondary (deprecated, prefer SecondaryWireButtonStyle)

public struct SecondaryButtonStyleLegacy: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let compact: Bool
    let pressed: Bool

    public init(compact: Bool = false, pressed: Bool = false) {
        self.compact = compact
        self.pressed = pressed
    }

    private var backgoundColor: Color {
        colorScheme == .light ? Color.white : Color(baseColor: .gray70)
    }

    private var foregroundColor: Color {
        colorScheme == .light ? Color(baseColor: .blue50) : .white
    }

    @ViewBuilder
    func compactPadding(view: some View) -> some View {
        if compact {
            view
        } else {
            view.padding()
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        return compactPadding(view: configuration.label)
            .font(legacyButtonFont())
            .foregroundColor(isPressed ? foregroundColor.opacity(Consts.pressedOpacity) : foregroundColor.opacity(1))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .cornerRadius(Consts.legacyCornerRadius)
            .ddgButtonDynamicTypeCap()
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    let compact: Bool
    let pressed: Bool

    public init(compact: Bool = false, pressed: Bool = false) {
        self.compact = compact
        self.pressed = pressed
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            SecondaryButtonStyleLegacy(compact: compact, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        let accent = Color(designSystemColor: .accentPrimary)
        let isPressed = configuration.isPressed || pressed
        return configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(isPressed ? accent.opacity(Consts.pressedOpacity) : accent)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Secondary Fill

public struct SecondaryFillButtonStyleLegacy: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

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
        let standardBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillDefault)
        let pressedBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillPressed)
        let disabledBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillDisabled)
        let defaultForegroundColor = Color(designSystemColor: .buttonsSecondaryFillText)
        let disabledForegroundColor = Color(designSystemColor: .buttonsSecondaryFillTextDisabled)
        let backgroundColor = disabled ? disabledBackgroundColor : standardBackgroundColor
        let foregroundColor = disabled ? disabledForegroundColor : defaultForegroundColor
        let isPressed = configuration.isPressed || pressed

        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(legacyButtonFont())
            .foregroundColor(isPressed ? defaultForegroundColor : foregroundColor)
            .if(!isFreeform) { view in
                view
                    .padding(.vertical)
                    .padding(.horizontal, fullWidth ? nil : 24)
                    .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            }
            .background(isPressed ? pressedBackgroundColor : backgroundColor)
            .cornerRadius(Consts.legacyCornerRadius)
            .ddgButtonDynamicTypeCap()
    }
}

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

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            SecondaryFillButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth, isFreeform: isFreeform, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
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
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .if(!isFreeform) { view in
                view
                    .padding(.vertical)
                    .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
                    .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            }
            .background(backgroundColor)
            .clipShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Ghost

public struct GhostButtonStyleLegacy: ButtonStyle {

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
        return configuration.label
            .font(legacyButtonFont())
            .foregroundColor(foregroundColor(isPressed))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(backgroundColor(isPressed))
            .cornerRadius(Consts.legacyCornerRadius)
            .contentShape(Rectangle())
            .opacity(disabled ? Consts.disabledOpacity : 1)
            .ddgButtonDynamicTypeCap()
    }

    private func foregroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .buttonsGhostTextPressed) : Color(designSystemColor: .buttonsGhostText)
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .buttonsGhostPressedFill) : .clear
    }
}

public struct GhostButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let pressed: Bool

    public init(disabled: Bool = false, compact: Bool = false, pressed: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.pressed = pressed
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            GhostButtonStyleLegacy(disabled: disabled, compact: compact, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        let foregroundColor = isPressed
            ? Color(designSystemColor: .accentTertiary)
            : Color(designSystemColor: .accentPrimary)
        return configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
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

public struct GhostAltButtonStyleLegacy: ButtonStyle {

    let compact: Bool
    let pressed: Bool

    public init(compact: Bool = false, pressed: Bool = false) {
        self.compact = compact
        self.pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        return configuration.label
            .font(legacyButtonFont())
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(backgroundColor(isPressed))
            .cornerRadius(Consts.legacyCornerRadius)
            .contentShape(Rectangle())
            .ddgButtonDynamicTypeCap()
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ?  Color(UIColor(designSystemColor: .controlsFillPrimary)) : .clear
    }
}

public struct GhostAltButtonStyle: ButtonStyle {
    let compact: Bool
    let pressed: Bool

    public init(compact: Bool = false, pressed: Bool = false) {
        self.compact = compact
        self.pressed = pressed
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            GhostAltButtonStyleLegacy(compact: compact, pressed: pressed)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || pressed
        return configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(Color(singleUseColor: .rebranding(.textSecondary)))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
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

private enum Consts {
    static let legacyCornerRadius: CGFloat = 12
    static let legacyHeight: CGFloat = 50
    static let rebrandedHeightLarge: CGFloat = 50
    static let rebrandedHeightSmall: CGFloat = 40
    static let pressedOpacity: CGFloat = 0.7
    static let disabledOpacity: CGFloat = 0.36
}

// MARK: - Debug galleries

/// Scoped override of `AppRebrand.isAppRebranded` and the design-system palette for the host view's lifetime.
///
/// Captures the previous values at init and restores them on deinit, so it doesn't
/// permanently mutate global state. The palette must be overridden alongside the flag because
/// the rebranded button fills now resolve through `DesignSystemPalette.current`.
///
/// Internal so the galleries (Xcode previews and the runtime debug menu) can reuse it
/// within the module, e.g. `IOSButtonsDebugView.swift`.
final class RebrandPreviewOverride: ObservableObject {
    private let previousIsRebranded: () -> Bool
    private let previousPalette: ColorPalette

    init(isRebranded: Bool) {
        self.previousIsRebranded = AppRebrand.isAppRebranded
        self.previousPalette = DesignSystemPalette.current
        AppRebrand.isAppRebranded = { isRebranded }
        DesignSystemPalette.current = isRebranded ? .rebranded : .default
    }

    deinit {
        AppRebrand.isAppRebranded = previousIsRebranded
        DesignSystemPalette.current = previousPalette
    }
}

public struct ButtonStylesGallery: View {
    let isRebranded: Bool

    @StateObject private var override: RebrandPreviewOverride

    public init(isRebranded: Bool) {
        self.isRebranded = isRebranded
        _override = StateObject(wrappedValue: RebrandPreviewOverride(isRebranded: isRebranded))
    }

    private func applyRebrandOverride() {
        AppRebrand.isAppRebranded = { isRebranded }
        DesignSystemPalette.current = isRebranded ? .rebranded : .default
    }

    public var body: some View {
        applyRebrandOverride()
        return ScrollView {
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
        .background(Color(designSystemColor: .background))
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
#Preview("Buttons Legacy / Light") {
    ButtonStylesGallery(isRebranded: false)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
}

#Preview("Buttons Legacy / Dark") {
    ButtonStylesGallery(isRebranded: false)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
}

#Preview("Buttons Rebranded / Light") {
    ButtonStylesGallery(isRebranded: true)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
}

#Preview("Buttons Rebranded / Dark") {
    ButtonStylesGallery(isRebranded: true)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
}

#endif
