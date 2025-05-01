//
//  AutofillDeleteButtonCell.swift
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

struct AutofillDeleteButtonCell: View {
    let deleteButtonText: String
    let confirmationTitle: String
    var confirmationMessage: String = ""
    var confirmationButtonTitle: String
    let onDelete: () -> Void
    
    @State private var actionSheetConfirmDeletePresented: Bool = false
    
    var body: some View {
        HStack {
            Button {
                actionSheetConfirmDeletePresented.toggle()
            } label: {
                HStack {
                    Text(deleteButtonText)
                }
                .frame(maxWidth: .infinity)
            }
            .actionSheet(isPresented: $actionSheetConfirmDeletePresented, content: {
                let deleteAction = ActionSheet.Button.destructive(Text(confirmationButtonTitle)) {
                    onDelete()
                }
                return ActionSheet(title: Text(confirmationTitle),
                                  message: Text(confirmationMessage),
                                  buttons: [deleteAction, ActionSheet.Button.cancel()])
            })
            .foregroundColor(Color.red)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }}
