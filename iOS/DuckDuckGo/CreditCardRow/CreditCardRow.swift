//
//  CreditCardRow.swift
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

struct CreditCardRow: View {
    
    var card: CreditCardRowViewModel
    var showDisclosure: Bool
    
    var body: some View {
        HStack {
            card.icon
                .padding(.trailing, 8)
            
            VStack(alignment: .leading) {
                Text(card.displayTitle)
                    .daxSubheadRegular()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                (Text(verbatim: "••••").font(.system(.footnote, design: .monospaced))
                 + Text(verbatim: " ")
                 + Text(card.lastFourDigits)
                 + Text(card.expirationDate))
                .daxFootnoteRegular()
                .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
            .padding(.vertical, 4)
            
            Spacer()
            
            if showDisclosure {
                Image(systemName: "chevron.forward")
                    .font(Font.system(.footnote).weight(.bold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
    }
}
