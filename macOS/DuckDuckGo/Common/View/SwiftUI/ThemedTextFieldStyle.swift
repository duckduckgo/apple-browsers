//
//  ThemedTextFieldStyle.swift
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

import Foundation
import SwiftUI

extension TextFieldStyle where Self == ThemedTextFieldStyle {
    static var themed: ThemedTextFieldStyle {
        ThemedTextFieldStyle()
    }
}

struct ThemedTextFieldStyle: TextFieldStyle {
    var backgroundColor = Color(designSystemColor: .toneShadePrimary)
    let focusBorderColor = Color(designSystemColor: .accentPrimary)

    // swiftlint:disable identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        if #available(macOS 12.0, *) {
            FocusableThemedTextFieldStyle(configuration: configuration, backgroundColor: backgroundColor, focusBorderColor: focusBorderColor)
        } else {
            LegacyThemedTextFieldStyle(configuration: configuration, backgroundColor: backgroundColor)
        }
    }
    // swiftlint:enable identifier_name
}

@available(macOS 12.0, *)
struct FocusableThemedTextFieldStyle<Label: View>: View {
    @FocusState private var isFocused: Bool
    let configuration: TextField<Label>
    let backgroundColor: Color
    let focusBorderColor: Color

    var body: some View {
        configuration
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding([.top, .bottom], 5)
            .padding([.leading, .trailing], 6)
            .background(backgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(focusBorderColor, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
    }
}

struct LegacyThemedTextFieldStyle<Label: View>: View {
    let configuration: TextField<Label>
    let backgroundColor: Color

    var body: some View {
        configuration
            .textFieldStyle(.plain)
            .padding([.top, .bottom], 5)
            .padding([.leading, .trailing], 6)
            .background(backgroundColor)
            .cornerRadius(4)
    }
}
