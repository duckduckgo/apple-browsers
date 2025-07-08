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

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let disabled: Bool
    let compact: Bool
    let fullWidth: Bool

    public init(disabled: Bool = false, compact: Bool = false, fullWidth: Bool = true) {
        self.disabled = disabled
        self.compact = compact
        self.fullWidth = fullWidth
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        let standardBackgroundColor = Color(designSystemColor: .buttonsPrimaryDefault)
        let pressedBackgroundColor = Color(designSystemColor: .buttonsPrimaryPressed)
        let disabledBackgroundColor = Color(designSystemColor: .buttonsPrimaryDisabled)
        let standardForegroundColor = Color(designSystemColor: .buttonsPrimaryText)
        let disabledForegroundColor = Color(designSystemColor: .buttonsPrimaryTextDisabled)
        let backgroundColor = disabled ? disabledBackgroundColor : standardBackgroundColor
        let foregroundColor = disabled ? disabledForegroundColor : standardForegroundColor

        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .font(Font(UIFont.boldAppFont(ofSize: Consts.fontSize)))
            .foregroundColor(foregroundColor)
            .padding(.vertical)
            .padding(.horizontal, fullWidth ? nil : 24)
            .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, maxHeight: compact ? Consts.height - 10 : Consts.height)
            .background(configuration.isPressed ? pressedBackgroundColor : backgroundColor)
            .cornerRadius(Consts.cornerRadius)
    }
}

// This style seems to be deprecated - you probably want to use SecondaryWireButtonStyle.
// Reach out to designers.
public struct SecondaryButtonStyle: ButtonStyle {
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
            .font(Font(UIFont.boldAppFont(ofSize: Consts.fontSize)))
            .foregroundColor(configuration.isPressed ? foregroundColor.opacity(Consts.pressedOpacity) : foregroundColor.opacity(1))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: compact ? Consts.height - 10 : Consts.height)
            .cornerRadius(Consts.cornerRadius)
    }
}

public struct SecondaryFillButtonStyle: ButtonStyle {
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
            .font(Font(UIFont.boldAppFont(ofSize: Consts.fontSize)))
            .foregroundColor(configuration.isPressed ? defaultForegroundColor : foregroundColor)
            .if(!isFreeform) { view in
                view
                    .padding(.vertical)
                    .padding(.horizontal, fullWidth ? nil : 24)
                    .frame(minWidth: 0, maxWidth: fullWidth ? .infinity : nil, maxHeight: compact ? Consts.height - 10 : Consts.height)
            }
            .background(configuration.isPressed ? pressedBackgroundColor : backgroundColor)
            .cornerRadius(Consts.cornerRadius)
    }
}

public struct GhostButtonStyle: ButtonStyle {

    let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font(UIFont.boldAppFont(ofSize: Consts.fontSize)))
            .foregroundColor(foregroundColor(configuration.isPressed))
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: compact ? Consts.height - 10 : Consts.height)
            .background(backgroundColor(configuration.isPressed))
            .cornerRadius(Consts.cornerRadius)
            .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
    }
    
    private func foregroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .buttonsGhostTextPressed) : Color(designSystemColor: .buttonsGhostText)
    }
    
    private func backgroundColor(_ isPressed: Bool) -> Color {
        isPressed ? Color(designSystemColor: .buttonsGhostPressedFill) : .clear
    }
}

private enum Consts {
    static let cornerRadius: CGFloat = 12
    static let height: CGFloat = 50
    static let fontSize: CGFloat = 15
    static let pressedOpacity: CGFloat = 0.7
}
