//
//  AutofillEditableCell.swift
//  DuckDuckGo
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

import DesignResourcesKit
import SwiftUI

struct AutofillEditableCell: View {
    let title: String
    @Binding var text: String
    let placeholderText: String
    var secure: Bool = false
    var autoCapitalizationType: UITextAutocapitalizationType = .none
    var disableAutoCorrection: Bool = true
    var keyboardType: UIKeyboardType = .default
    var id: UUID = UUID()
    let inEditMode: Bool
    var characterLimit: Int?
    @Binding var selectedCell: UUID?
    let textFieldAccessibilityIdentifier: String

    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .daxBodyRegular()
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            
            HStack {
                if secure && inEditMode {
                    SecureField(placeholderText, text: $text)
                        .onChange(of: text) { _ in
                            if let limit = characterLimit, text.count > limit {
                                text = String(text.prefix(limit))
                            }
                        }
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color(designSystemColor: .textPrimary))
                } else {
                    ClearTextField(placeholderText: placeholderText,
                                   text: $text,
                                   autoCapitalizationType: autoCapitalizationType,
                                   disableAutoCorrection: disableAutoCorrection,
                                   keyboardType: keyboardType,
                                   secure: secure,
                                   characterLimit: characterLimit)
                }
            }
            .accessibilityIdentifier(textFieldAccessibilityIdentifier)
        }
        .frame(minHeight: 60)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .focused($isFieldFocused)
        .onChange(of: isFieldFocused) { focused in
            if focused {
                selectedCell = id
            }
        }

    }
}
