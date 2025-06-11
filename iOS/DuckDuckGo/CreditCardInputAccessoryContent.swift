//
//  CreditCardInputAccessoryContent.swift
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

import SwiftUI
import DesignResourcesKitIcons

struct CreditCardInputAccessoryContent: View {
    let creditCards: [CreditCardRowViewModel]
    let onSuggestionSelected: (CreditCardRowViewModel?) -> Void
    
    @State private var showManageButton = true
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            
            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    
                    HStack(spacing: 16) {
                        ForEach(creditCards) { creditCard in
                            Button(action: {
                                onSuggestionSelected(creditCard)
                            }) {
                                VStack(alignment: .leading) {
                                    Text(creditCard.displayTitle)
                                        .foregroundColor(Color(designSystemColor: .textPrimary))
                                    (Text(verbatim: "••••").font(.system(.footnote, design: .monospaced))
                                     + Text(verbatim: " ")
                                     + Text(creditCard.lastFourDigits))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                
            }
            .padding(.vertical, 0)
            
            Button {
                
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.creditCard)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button {
                onSuggestionSelected(nil)
            } label: {
                Text(UserText.navigationTitleDone)
                    .foregroundStyle(Color(designSystemColor: .accent))
            }
            .padding(.trailing, 8)
            
        }
        .background(Color(designSystemColor: .background))
        .frame(height: 54)
    }
}
