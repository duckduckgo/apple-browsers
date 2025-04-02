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
    @Binding var selectedCell: UUID?
    
    @FocusState private var isFieldFocused: Bool
    @State private var closeButtonVisible = false
    
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
                    .label4Style(design: unmaskedString.count > 0 ? .monospaced : .default)
                
                Spacer()
                
                if unmaskedString.count > 0 {
                    if closeButtonVisible {
                        Image("Clear-16")
                            .onTapGesture {
                                self.unmaskedString = ""
                            }
                    }
                }
            }
        }
        .frame(minHeight:60)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .focused($isFieldFocused)
        .onChange(of: isFieldFocused) { focused in
            closeButtonVisible = focused
            if focused {
                isMasked = false
                selectedCell = id
            }
        }
    }
}
