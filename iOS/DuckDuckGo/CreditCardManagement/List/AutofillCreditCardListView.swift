//
//  AutofillCreditCardListView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit
import DuckUI

struct AutofillCreditCardListView: View {
    
    @ObservedObject var viewModel: AutofillCreditCardListViewModel

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .authLocked, .noAuthAvailable:
                LockScreenView()
            case .empty:
                EmptyStateView(viewModel: viewModel)
            case .showItems:
                List {
                    Section {
                        ForEach(viewModel.cards, id: \.self) { card in
                            Button {
                                viewModel.cardSelected(card)
                            } label: {
                                CreditCardRow(card: card, showDisclosure: true)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteCard(card.creditCard)
                                } label: {
                                    Label(UserText.autofillCreditCardDetailsDeleteButton, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                }
                .applyInsetGroupedListStyle()
            }
        }
    }
}

private struct EmptyStateView: View {
    var viewModel: AutofillCreditCardListViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            Image(.creditCardsAdd96)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
            
            Group {
                Text(UserText.autofillCreditCardEmptyViewTitle)
                    .daxTitle3()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .padding(.top, 16)
                
                Text(UserText.autofillCreditCardEmptyViewSubtitle)
                    .daxBodyRegular()
                    .foregroundStyle(Color.init(designSystemColor: .textSecondary))
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            .lineLimit(nil)
            
            Button {
                viewModel.addCard()
            } label: {
                HStack {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.add)
                    Text(UserText.autofillCreditCardDetailsNewTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            .padding(.top, 24)
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            Rectangle().ignoresSafeArea().foregroundColor(Color(designSystemColor: .background))
        )
    }
}

#Preview {
    AutofillCreditCardListView(viewModel: AutofillCreditCardListViewModel(source: .settings))
}
