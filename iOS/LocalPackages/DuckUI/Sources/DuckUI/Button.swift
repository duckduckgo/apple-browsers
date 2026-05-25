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
}

// MARK: - Typography helpers
//
// All button typography is Dynamic-Type-aware: the font is built from a
// `TextStyle`, the frame uses `minHeight` (not `maxHeight`) so the button
// grows with the label, and `.dynamicTypeSize(...accessibility3)` caps
// runaway growth at the third accessibility step (a common UX cap).

private extension View {
    /// Cap Dynamic Type growth so button layouts don't break at the largest
    /// accessibility sizes. Apply once per ButtonStyle body.
    func ddgButtonDynamicTypeCap() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private func legacyButtonFont() -> Font {
    // Bold subheadline; scales with Dynamic Type via `daxButton()`.
    Font(UIFont.daxButton())
}

private func rebrandedButtonFont(compact: Bool) -> Font {
    // Figma "iOS Buttons" specifies SF Pro Medium 17pt (Large) / 15pt (Small).
    // 17pt = `.body` default at .large Dynamic Type; 15pt = `.subheadline`.
    .system(compact ? .subheadline : .body).weight(.medium)
}

// MARK: - Legacy body builder

@ViewBuilder
private func makeLegacyPrimaryBody(
    configuration: ButtonStyleConfiguration,
    colors: PrimaryButtonColors,
    disabled: Bool,
    compact: Bool,
    fullWidth: Bool
) -> some View {
    let backgroundColor = disabled ? colors.disabled : colors.standard
    let foregroundColor = disabled ? colors.textDisabled : colors.text

    configuration.label
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .font(legacyButtonFont())
        .foregroundColor(foregroundColor)
        .padding(.vertical)
        .padding(.horizontal, fullWidth ? nil : 24)
        .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
        .background(configuration.isPressed ? colors.pressed : backgroundColor)
        .cornerRadius(Consts.legacyCornerRadius)
        .ddgButtonDynamicTypeCap()
}

// MARK: - Rebranded body builder
//
// New design language: pill shape (Capsule), SF Pro Medium typography, larger 17pt label
// for non-compact buttons (15pt for compact). Heights and tokens unchanged.
// See Figma "Mobile - New Design Language" → "iOS Buttons" (node 888:58029).

@ViewBuilder
private func makeRebrandedPrimaryBody(
    configuration: ButtonStyleConfiguration,
    colors: PrimaryButtonColors,
    disabled: Bool,
    compact: Bool,
    fullWidth: Bool
) -> some View {
    let backgroundColor = disabled ? colors.disabled : colors.standard
    let foregroundColor = disabled ? colors.textDisabled : colors.text

    configuration.label
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .font(rebrandedButtonFont(compact: compact))
        .foregroundColor(foregroundColor)
        .padding(.vertical)
        .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
        .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
        .background(configuration.isPressed ? colors.pressed : backgroundColor)
        .clipShape(Capsule())
        .ddgButtonDynamicTypeCap()
}

// MARK: - Primary

public struct PrimaryButtonStyleLegacy: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        makeLegacyPrimaryBody(
            configuration: configuration,
            colors: .primary,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth
        )
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            makeRebrandedPrimaryBody(
                configuration: configuration,
                colors: .primary,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth
            )
        } else {
            makeLegacyPrimaryBody(
                configuration: configuration,
                colors: .primary,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth
            )
        }
    }
}

// MARK: - Primary Destructive

public struct PrimaryDestructiveButtonStyleLegacy: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        makeLegacyPrimaryBody(
            configuration: configuration,
            colors: .destructive,
            disabled: disabled,
            compact: compact,
            fullWidth: fullWidth
        )
    }
}

public struct PrimaryDestructiveButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            makeRebrandedPrimaryBody(
                configuration: configuration,
                colors: .destructive,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth
            )
        } else {
            makeLegacyPrimaryBody(
                configuration: configuration,
                colors: .destructive,
                disabled: disabled,
                compact: compact,
                fullWidth: fullWidth
            )
        }
    }
}

// MARK: - Secondary Destructive
//
// Legacy: red 1pt stroke + transparent background.
// Rebrand: "Destructive Secondary" — filled with the control-primary background token
// and red text. The outline is dropped to match the new pill language.

public struct SecondaryDestructiveButtonStyleLegacy: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        let destructiveColor = Color(designSystemColor: .destructivePrimary)
        let disabledColor = destructiveColor.opacity(0.36)
        let borderColor = disabled ? disabledColor : destructiveColor
        let foregroundColor = disabled ? disabledColor : destructiveColor
        let pressedBackgroundColor = destructiveColor.opacity(0.1)

        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(legacyButtonFont())
            .foregroundColor(foregroundColor)
            .padding(.vertical)
            .padding(.horizontal, fullWidth ? nil : 24)
            .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(configuration.isPressed ? pressedBackgroundColor : Color.clear)
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

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            SecondaryDestructiveButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        let destructiveColor = Color(designSystemColor: .destructivePrimary)
        let foregroundColor = disabled ? destructiveColor.opacity(0.36) : destructiveColor
        let backgroundColor = Color(designSystemColor: .controlsFillSecondary)
        let pressedBackgroundColor = Color(designSystemColor: .controlsFillPrimary)

        return configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(foregroundColor)
            .padding(.vertical)
            .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
            .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            .background(configuration.isPressed ? pressedBackgroundColor : backgroundColor)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(disabled ? 0.36 : 1)
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Secondary (deprecated)

// This style seems to be deprecated - you probably want to use SecondaryWireButtonStyle.
// Reach out to designers.
public struct SecondaryButtonStyleLegacy: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
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
        compactPadding(view: configuration.label)
            .font(legacyButtonFont())
            .foregroundColor(configuration.isPressed ? foregroundColor.opacity(Consts.pressedOpacity) : foregroundColor.opacity(1))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .cornerRadius(Consts.legacyCornerRadius)
            .ddgButtonDynamicTypeCap()
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            SecondaryButtonStyleLegacy(compact: compact)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        // Rebranded behaviour aligns with the design's "Ghost" treatment:
        // transparent background, accent-primary label, pill hit area.
        let accent = Color(designSystemColor: .accent)
        return configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(configuration.isPressed ? accent.opacity(Consts.pressedOpacity) : accent)
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

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, isFreeform: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.isFreeform = isFreeform
    }

    public func makeBody(configuration: Configuration) -> some View {
        let standardBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillDefault)
        let pressedBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillPressed)
        let disabledBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillDisabled)
        let defaultForegroundColor = Color(designSystemColor: .buttonsSecondaryFillText)
        let disabledForegroundColor = Color(designSystemColor: .buttonsSecondaryFillTextDisabled)
        let backgroundColor = disabled ? disabledBackgroundColor : standardBackgroundColor
        let foregroundColor = disabled ? disabledForegroundColor : defaultForegroundColor

        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(legacyButtonFont())
            .foregroundColor(configuration.isPressed ? defaultForegroundColor : foregroundColor)
            .if(!isFreeform) { view in
                view
                    .padding(.vertical)
                    .padding(.horizontal, fullWidth ? nil : 24)
                    .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            }
            .background(configuration.isPressed ? pressedBackgroundColor : backgroundColor)
            .cornerRadius(Consts.legacyCornerRadius)
            .ddgButtonDynamicTypeCap()
    }
}

public struct SecondaryFillButtonStyle: ButtonStyle {
    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool
    let isFreeform: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true, isFreeform: Bool = false) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
        self.isFreeform = isFreeform
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            SecondaryFillButtonStyleLegacy(disabled: disabled, compact: compact, fullWidth: fullWidth, isFreeform: isFreeform)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        let standardBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillDefault)
        let pressedBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillPressed)
        let disabledBackgroundColor = Color(designSystemColor: .buttonsSecondaryFillDisabled)
        let defaultForegroundColor = Color(designSystemColor: .buttonsSecondaryFillText)
        let disabledForegroundColor = Color(designSystemColor: .buttonsSecondaryFillTextDisabled)
        let backgroundColor = disabled ? disabledBackgroundColor : standardBackgroundColor
        let foregroundColor = disabled ? disabledForegroundColor : defaultForegroundColor

        return configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(configuration.isPressed ? defaultForegroundColor : foregroundColor)
            .if(!isFreeform) { view in
                view
                    .padding(.vertical)
                    .padding(.horizontal, fullWidth ? nil : (compact ? 16 : 24))
                    .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            }
            .background(configuration.isPressed ? pressedBackgroundColor : backgroundColor)
            .clipShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }
}

// MARK: - Ghost

public struct GhostButtonStyleLegacy: ButtonStyle {

    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(legacyButtonFont())
            .foregroundColor(foregroundColor(configuration.isPressed))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(backgroundColor(configuration.isPressed))
            .cornerRadius(Consts.legacyCornerRadius)
            .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
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
    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            GhostButtonStyleLegacy(compact: compact)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(foregroundColor(configuration.isPressed))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            .background(backgroundColor(configuration.isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }

    private func foregroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .buttonsGhostTextPressed) : Color(designSystemColor: .buttonsGhostText)
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .buttonsGhostPressedFill) : .clear
    }
}

// MARK: - Ghost Alt

public struct GhostAltButtonStyleLegacy: ButtonStyle {

    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(legacyButtonFont())
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.legacyHeight - 10 : Consts.legacyHeight)
            .background(backgroundColor(configuration.isPressed))
            .cornerRadius(Consts.legacyCornerRadius)
            .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
            .ddgButtonDynamicTypeCap()
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ?  Color(UIColor(designSystemColor: .controlsFillPrimary)) : .clear
    }
}

public struct GhostAltButtonStyle: ButtonStyle {
    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if AppRebrand.isAppRebranded() {
            rebrandedBody(configuration: configuration)
        } else {
            GhostAltButtonStyleLegacy(compact: compact)
                .makeBody(configuration: configuration)
        }
    }

    private func rebrandedBody(configuration: Configuration) -> some View {
        configuration.label
            .font(rebrandedButtonFont(compact: compact))
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: compact ? Consts.rebrandedHeightSmall : Consts.rebrandedHeightLarge)
            .background(backgroundColor(configuration.isPressed))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .ddgButtonDynamicTypeCap()
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(UIColor(designSystemColor: .controlsFillPrimary)) : .clear
    }
}

// MARK: - Constants

private enum Consts {
    // Legacy
    static let legacyCornerRadius: CGFloat = 12
    static let legacyHeight: CGFloat = 50
    static let legacyFontSize: CGFloat = 15

    // Rebranded (Figma "New Design Language" iOS Buttons)
    static let rebrandedHeightLarge: CGFloat = 50
    static let rebrandedHeightSmall: CGFloat = 40
    static let rebrandedFontSizeLarge: CGFloat = 17
    static let rebrandedFontSizeSmall: CGFloat = 15

    // Shared
    static let pressedOpacity: CGFloat = 0.7
    static let ghostPressedBackgroundOpacity: CGFloat = 0.09
}

// MARK: - Previews

#if DEBUG

private struct ButtonStylesGallery: View {
    let isRebranded: Bool

    init(isRebranded: Bool) {
        self.isRebranded = isRebranded
        // Set before `body` evaluates so the ButtonStyles' `makeBody`
        // reads the correct value on the first render. `.onAppear` fires
        // too late — the buttons would already have rendered with the
        // previous singleton value.
        AppRebrand.isAppRebranded = { isRebranded }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("PrimaryButtonStyle") {
                    Button("Default") {}.buttonStyle(PrimaryButtonStyle())
                    Button("Disabled") {}.buttonStyle(PrimaryButtonStyle(disabled: true))
                    Button("Compact") {}.buttonStyle(PrimaryButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }

                section("PrimaryDestructiveButtonStyle") {
                    Button("Default") {}.buttonStyle(PrimaryDestructiveButtonStyle())
                    Button("Disabled") {}.buttonStyle(PrimaryDestructiveButtonStyle(disabled: true))
                    Button("Compact") {}.buttonStyle(PrimaryDestructiveButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(PrimaryDestructiveButtonStyle(fullWidth: false))
                }

                section("SecondaryDestructiveButtonStyle") {
                    Button("Default") {}.buttonStyle(SecondaryDestructiveButtonStyle())
                    Button("Disabled") {}.buttonStyle(SecondaryDestructiveButtonStyle(disabled: true))
                    Button("Compact") {}.buttonStyle(SecondaryDestructiveButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(SecondaryDestructiveButtonStyle(fullWidth: false))
                }

                section("SecondaryButtonStyle (deprecated)") {
                    Button("Default") {}.buttonStyle(SecondaryButtonStyle())
                    Button("Compact") {}.buttonStyle(SecondaryButtonStyle(compact: true))
                }

                section("SecondaryFillButtonStyle") {
                    Button("Default") {}.buttonStyle(SecondaryFillButtonStyle())
                    Button("Disabled") {}.buttonStyle(SecondaryFillButtonStyle(disabled: true))
                    Button("Compact") {}.buttonStyle(SecondaryFillButtonStyle(compact: true))
                    Button("Hug content") {}.buttonStyle(SecondaryFillButtonStyle(fullWidth: false))
                }

                section("GhostButtonStyle") {
                    Button("Default") {}.buttonStyle(GhostButtonStyle())
                    Button("Compact") {}.buttonStyle(GhostButtonStyle(compact: true))
                }

                section("GhostAltButtonStyle") {
                    Button("Default") {}.buttonStyle(GhostAltButtonStyle())
                    Button("Compact") {}.buttonStyle(GhostAltButtonStyle(compact: true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color(designSystemColor: .background))
        .onAppear { AppRebrand.isAppRebranded = { isRebranded } }
        .onDisappear { AppRebrand.isAppRebranded = { false } }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(designSystemColor: .textSecondary))
            content()
        }
    }
}

#Preview("Buttons Legacy / Light") {
    ButtonStylesGallery(isRebranded: false)
        .preferredColorScheme(.light)
}

#Preview("Buttons Legacy / Dark") {
    ButtonStylesGallery(isRebranded: false)
        .preferredColorScheme(.dark)
}

#Preview("Buttons Rebranded / Light") {
    ButtonStylesGallery(isRebranded: true)
        .preferredColorScheme(.light)
}

#Preview("Buttons Rebranded / Dark") {
    ButtonStylesGallery(isRebranded: true)
        .preferredColorScheme(.dark)
}

#endif
