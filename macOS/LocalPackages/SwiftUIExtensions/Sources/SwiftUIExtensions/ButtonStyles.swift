//
//  ButtonStyles.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Common
import DesignResourcesKit
import Foundation
import SwiftUI
import UIComponents

private struct ButtonMetrics {
    let fontSize: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat

    static var current: ButtonMetrics {
        ButtonMetrics(fontSize: 13, topPadding: 2.5, bottomPadding: 3, horizontalPadding: 7.5, cornerRadius: 5)
    }
}

public struct StandardButtonStyle: ButtonStyle {
    public let fontSize: CGFloat
    public let topPadding: CGFloat
    public let bottomPadding: CGFloat
    public let horizontalPadding: CGFloat
    public let labelColor: Color
    public let backgroundColor: Color
    public let backgroundPressedColor: Color
    public let cornerRadius: CGFloat

    /// Applies pill shape to the button **ONLY** when Liquid Glass is supported.
    ///
    /// Setting this to `true` when Liquid Glass is not supported has no effect
    /// and falls back to using provided `cornerRadius`.
    public let pillShape: Bool

    public init(fontSize: CGFloat? = nil, topPadding: CGFloat? = nil, bottomPadding: CGFloat? = nil, horizontalPadding: CGFloat? = nil, backgroundColor: Color? = nil, backgroundPressedColor: Color? = nil, cornerRadius: CGFloat? = nil, pillShape: Bool = false) {
        let metrics = ButtonMetrics.current
        let colors = ButtonStateColors.legacyStandardButtonColors

        self.fontSize = fontSize ?? metrics.fontSize
        self.topPadding = topPadding ?? metrics.topPadding
        self.bottomPadding = bottomPadding ?? metrics.bottomPadding
        self.horizontalPadding = horizontalPadding ?? metrics.horizontalPadding
        self.labelColor = colors.textColor
        self.backgroundColor = backgroundColor ?? colors.backgroundColor
        self.backgroundPressedColor = backgroundPressedColor ?? colors.pressedBackgroundColor
        self.cornerRadius = cornerRadius ?? metrics.cornerRadius
        self.pillShape = pillShape
    }

    public func makeBody(configuration: Self.Configuration) -> some View {
        let backgroundColor = configuration.isPressed ? backgroundPressedColor : backgroundColor

        configuration.label
            .font(.system(size: fontSize))
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .padding(.horizontal, horizontalPadding)
            .background(backgroundColor)
            .foregroundColor(labelColor)
            .if(pillShape) { $0.liquidGlassPillShape(fallbackCornerRadius: cornerRadius) }
            .if(!pillShape) { $0.cornerRadius(cornerRadius) }
    }
}

public struct DefaultActionButtonStyle: ButtonStyle {

    public let enabled: Bool
    public let topPadding: CGFloat
    public let bottomPadding: CGFloat
    public let shouldBeFixedVertical: Bool
    public let stateColors: ButtonStateColors
    public let pillShape: Bool

    public init(enabled: Bool, topPadding: CGFloat = 2.5, bottomPadding: CGFloat = 3, shouldBeFixedVertical: Bool = true, stateColors: ButtonStateColors = .legacyActionButton, pillShape: Bool = false) {
        self.enabled = enabled
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.shouldBeFixedVertical = shouldBeFixedVertical
        self.stateColors = stateColors
        self.pillShape = pillShape
    }

    public func makeBody(configuration: Self.Configuration) -> some View {
        ButtonContent(configuration: configuration, stateColors: stateColors, enabled: enabled, topPadding: topPadding, bottomPadding: bottomPadding, shouldBeFixedVertical: shouldBeFixedVertical, pillShape: pillShape)
    }

    struct ButtonContent: View {
        let configuration: Configuration
        let stateColors: ButtonStateColors
        let enabled: Bool
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let shouldBeFixedVertical: Bool
        let pillShape: Bool
        @State private var isHovered: Bool = false

        var body: some View {
            let backgroundColor = configuration.isPressed
                ? stateColors.pressedBackgroundColor
                : (isHovered ? stateColors.hoveredBackgroundColor : stateColors.backgroundColor)

            let labelColor = configuration.isPressed ? stateColors.pressedTextColor : stateColors.textColor

            configuration.label
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .if(shouldBeFixedVertical) { view in
                    view.fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 44)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .padding(.horizontal, 7.5)
                .background(backgroundColor)
                .foregroundColor(labelColor)
                .opacity(enabled ? 1 : 0.5)
                .if(pillShape) { $0.liquidGlassPillShape(fallbackCornerRadius: 5) }
                .if(!pillShape) { $0.cornerRadius(5) }
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

public struct TransparentActionButtonStyle: ButtonStyle {

    public let enabled: Bool
    public let topPadding: CGFloat
    public let bottomPadding: CGFloat

    public init(enabled: Bool, topPadding: CGFloat = 2.5, bottomPadding: CGFloat = 3) {
        self.enabled = enabled
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
    }

    public func makeBody(configuration: Self.Configuration) -> some View {

        let enabledForegroundColor = configuration.isPressed ? Color(NSColor.controlAccentColor).opacity(0.5) : Color(NSColor.controlAccentColor)
        let disabledForegroundColor = Color.gray.opacity(0.1)

        configuration.label
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44) // OK buttons will match the width of "Cancel" at least in English
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .padding(.horizontal, 0)
            .background(Color.clear)
            .foregroundColor(enabled ? enabledForegroundColor : disabledForegroundColor)
            .cornerRadius(5)

    }
}

public struct DismissActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered: Bool = false

    public let stateColors: ButtonStateColors
    public let textColor: Color
    public let topPadding: CGFloat
    public let bottomPadding: CGFloat
    public let pillShape: Bool

    public init(textColor: Color? = nil, topPadding: CGFloat = 2.5, bottomPadding: CGFloat = 3, pillShape: Bool = false, stateColors: ButtonStateColors = .legacyDismissButton) {
        self.stateColors = stateColors
        self.textColor = textColor ?? stateColors.textColor
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.pillShape = pillShape
    }

    public func makeBody(configuration: Self.Configuration) -> some View {
        let backgroundColor = configuration.isPressed
            ? stateColors.pressedBackgroundColor
            : (isHovered ? stateColors.hoveredBackgroundColor : stateColors.backgroundColor)
        let outerShadowOpacity = colorScheme == .dark ? 0.8 : 0.0

        configuration.label
            .lineLimit(1)
            .font(.system(size: 13))
            .frame(minWidth: 44) // OK buttons will match the width of "Cancel" at least in English
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .padding(.horizontal, 7.5)
            .background(
                Group {
                    if pillShape && AppVersion.isLiquidGlassSupported {
                        Capsule(style: .continuous)
                            .fill(backgroundColor)
                            .shadow(color: .black.opacity(0.1), radius: 0.1, x: 0, y: 1)
                            .shadow(color: .primary.opacity(outerShadowOpacity), radius: 0.1, x: 0, y: -0.6)
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(backgroundColor)
                            .shadow(color: .black.opacity(0.1), radius: 0.1, x: 0, y: 1)
                            .shadow(color: .primary.opacity(outerShadowOpacity), radius: 0.1, x: 0, y: -0.6)
                    }
                }
            )
            .overlay(
                Group {
                    if pillShape && AppVersion.isLiquidGlassSupported {
                        Capsule()
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    }
                }
            )
            .foregroundColor(textColor)
            .onHover { hovering in
                isHovered = hovering
            }

    }
}

public struct DestructiveActionButtonStyle: ButtonStyle {

    public let enabled: Bool
    public let topPadding: CGFloat
    public let bottomPadding: CGFloat
    public let backgroundColor: Color
    public let backgroundPressedColor: Color

    /// Applies pill shape to the button **ONLY** when Liquid Glass is supported.
    ///
    /// Setting this to `true` when Liquid Glass is not supported has no effect
    /// and falls back to using a `cornerRadius` of 5.
    public let pillShape: Bool

    public init(enabled: Bool, topPadding: CGFloat = 2.5, bottomPadding: CGFloat = 3, backgroundColor: Color? = nil, backgroundPressedColor: Color? = nil, pillShape: Bool = false) {
        self.enabled = enabled
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.backgroundColor = backgroundColor ?? Color(.destructiveActionButtonBackground)
        self.backgroundPressedColor = backgroundPressedColor ?? Color(.destructiveActionButtonBackgroundPressed)
        self.pillShape = pillShape
    }

    public func makeBody(configuration: Self.Configuration) -> some View {
        let enabledBackgroundColor = configuration.isPressed ? backgroundPressedColor : backgroundColor
        let disabledBackgroundColor = Color.gray.opacity(0.1)
        let labelColor = enabled ? Color.white : Color.primary.opacity(0.3)

        configuration.label
            .lineLimit(1)
            .font(.system(size: 13))
            .frame(minWidth: 44) // OK buttons will match the width of "Cancel" at least in English
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .padding(.horizontal, 7.5)
            .background(enabled ? enabledBackgroundColor : disabledBackgroundColor)
            .foregroundColor(labelColor)
            .if(pillShape) { $0.liquidGlassPillShape(fallbackCornerRadius: 5) }
            .if(!pillShape) { $0.cornerRadius(5) }

    }
}

public struct ButtonStateColors {
    let backgroundColor: Color
    let textColor: Color
    let hoveredBackgroundColor: Color
    let pressedBackgroundColor: Color
    let pressedTextColor: Color

    public init(backgroundColor: Color, textColor: Color, hoveredBackgroundColor: Color, pressedBackgroundColor: Color, pressedTextColor: Color) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.hoveredBackgroundColor = hoveredBackgroundColor
        self.pressedBackgroundColor = pressedBackgroundColor
        self.pressedTextColor = pressedTextColor
    }

    public static var themedActionButton: ButtonStateColors {
        .init(backgroundColor: Color(designSystemColor: .accentPrimary),
              textColor: Color(designSystemColor: .accentContentPrimary),
              hoveredBackgroundColor: Color(designSystemColor: .accentSecondary),
              pressedBackgroundColor: Color(designSystemColor: .accentTertiary),
              pressedTextColor: Color(designSystemColor: .accentContentTertiary))
    }

    public static var legacyActionButton: ButtonStateColors {
        .init(backgroundColor: Color("PrimaryButtonRest", bundle: Bundle.module),
              textColor: .white,
              hoveredBackgroundColor: Color("PrimaryButtonHover", bundle: Bundle.module),
              pressedBackgroundColor: Color("PrimaryButtonPressed", bundle: Bundle.module),
              pressedTextColor: Color.white.opacity(0.8))
    }

    public static var legacyStandardButtonColors: ButtonStateColors {
        .init(backgroundColor: Color(.pwmButtonBackground),
              textColor: Color(.pwmButtonLabel),
              hoveredBackgroundColor: Color(.pwmButtonBackground),
              pressedBackgroundColor: Color(.pwmButtonBackgroundPressed),
              pressedTextColor: Color(.pwmButtonLabel))
    }

    public static var themedDismissButton: ButtonStateColors {
        .init(backgroundColor: Color(designSystemColor: .controlsFillPrimary),
              textColor: Color(designSystemColor: .textPrimary),
              hoveredBackgroundColor: Color(designSystemColor: .controlsFillSecondary),
              pressedBackgroundColor: Color(designSystemColor: .controlsFillTertiary),
              pressedTextColor: Color(designSystemColor: .textSecondary))
    }

    public static var legacyDismissButton: ButtonStateColors {
        .init(backgroundColor: Color(.controlColor),
              textColor: .primary,
              hoveredBackgroundColor: Color(.controlColor),
              pressedBackgroundColor: Color(.windowBackgroundColor),
              pressedTextColor: .primary)
    }
}

public struct TouchDownButtonStyle: PrimitiveButtonStyle {

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.onTouchDownGesture(callback: configuration.trigger)
    }
}

private struct OnTouchDownGestureModifier: ViewModifier {
    @State private var tapped = false
    let callback: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            callback()
        })
    }
}

extension View {
    func onTouchDownGesture(callback: @escaping () -> Void) -> some View {
        modifier(OnTouchDownGestureModifier(callback: callback))
    }
}
