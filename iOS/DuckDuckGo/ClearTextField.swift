//
//  ClearTextField.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

struct ClearTextField: View {
    var placeholderText: String
    @Binding var text: String
    var autoCapitalizationType: UITextAutocapitalizationType = .none
    var disableAutoCorrection = true
    var keyboardType: UIKeyboardType = .default
    var secure = false
    var characterLimit: Int?

    @FocusState private var isFieldFocused: Bool
    @State private var shouldBeMonospaced: Bool = false
    @State private var closeButtonVisible = false

    var body: some View {
        HStack {
            TextField(placeholderText, text: $text)
                .autocapitalization(autoCapitalizationType)
                .disableAutocorrection(disableAutoCorrection)
                .keyboardType(keyboardType)
                .label4Style(design: shouldBeMonospaced ? .monospaced : .default)
                .focused($isFieldFocused)
                .onChange(of: isFieldFocused) { focused in
                    shouldBeMonospaced = secure && text.count > 0
                    closeButtonVisible = focused
                }
                .onChange(of: text) { _ in
                    shouldBeMonospaced = secure && text.count > 0
                    if let limit = characterLimit, text.count > limit {
                        text = String(text.prefix(limit))
                    }
                }

            Spacer()
            Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                .opacity(closeButtonOpacity)
                .onTapGesture { self.text = "" }
        }
    }

    private var closeButtonOpacity: Double {
        if text == "" || !closeButtonVisible {
            return 0
        }
        return 1
    }
}
