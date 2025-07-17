//
//  AutofillEditableMaskedCell.swift
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
import DesignResourcesKitIcons
import SwiftUI

struct AutofillEditableMaskedCell: View {
    @State private var id = UUID()
    let title: String
    let placeholderText: String
    @Binding var unmaskedString: String
    @Binding var maskedString: String
    @Binding var isMasked: Bool
    var autoCapitalizationType: UITextAutocapitalizationType = .none
    var disableAutoCorrection: Bool = true
    var keyboardType: UIKeyboardType = .default
    var characterLimit: Int?
    @Binding var selectedCell: UUID?

    @FocusState private var isFieldFocused: Bool
    @State private var shouldBeMonospaced: Bool
    @State private var closeButtonVisible = false

    init(title: String,
         placeholderText: String,
         unmaskedString: Binding<String>,
         maskedString: Binding<String>,
         isMasked: Binding<Bool>,
         autoCapitalizationType: UITextAutocapitalizationType = .none,
         disableAutoCorrection: Bool = true,
         keyboardType: UIKeyboardType = .default,
         characterLimit: Int? = nil,
         selectedCell: Binding<UUID?>) {

        self.title = title
        self.placeholderText = placeholderText
        self._unmaskedString = unmaskedString
        self._maskedString = maskedString
        self._isMasked = isMasked
        self.autoCapitalizationType = autoCapitalizationType
        self.disableAutoCorrection = disableAutoCorrection
        self.keyboardType = keyboardType
        self.characterLimit = characterLimit
        self._selectedCell = selectedCell

        // Initialize shouldBeMonospaced based on the initial unmaskedString value
        self._shouldBeMonospaced = State(initialValue: unmaskedString.wrappedValue.count > 0)
    }

    var body: some View {
        
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .daxBodyRegular()
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            
            HStack {
                TextField(placeholderText, text: isMasked ? $maskedString : $unmaskedString)
                    .autocapitalization(autoCapitalizationType)
                    .disableAutocorrection(disableAutoCorrection)
                    .keyboardType(keyboardType)
                    .label4Style(design: shouldBeMonospaced ? .monospaced : .default)
                    .onChange(of: unmaskedString) { _ in
                        shouldBeMonospaced = unmaskedString.count > 0
                        if let limit = characterLimit, unmaskedString.count > limit {
                            unmaskedString = String(unmaskedString.prefix(limit))
                        }
                    }
                
                Spacer()
                
                if unmaskedString.count > 0 {
                    if closeButtonVisible {
                        Image(uiImage: DesignSystemImages.Glyphs.Size16.clear)
                            .onTapGesture {
                                self.unmaskedString = ""
                            }
                    }
                }
            }
        }
        .frame(minHeight: 60)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .focused($isFieldFocused)
        .onChange(of: isFieldFocused) { focused in
            closeButtonVisible = focused
            shouldBeMonospaced = unmaskedString.count > 0
            if focused {
                isMasked = false
                selectedCell = id
            } else {
                isMasked = true
            }
        }
    }
}
