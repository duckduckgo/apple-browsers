//
//  PastedTextEditorView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import DesignResourcesKit
import SwiftUI
import UIKit

/// View/edit sheet for one pasted-text chip. Cancel and drag-to-dismiss discard edits, as on the FE.
struct PastedTextEditorView: View {

    @State private var text: String
    private let limit: Int
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    init(pastedText: AIChatPastedText, otherContentLength: Int, maxInputCharacters: Int,
         onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: pastedText.content)
        limit = AIChatPastedText.editLimit(ownLength: pastedText.length,
                                           otherContentLength: otherContentLength,
                                           maxInputCharacters: maxInputCharacters)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var count: Int { text.utf16.count }
    private var isOverLimit: Bool { count > limit }
    private var canSave: Bool { !isOverLimit && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(UserText.aiChatPastedTextFormattingNote)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))

                TextEditor(text: $text)
                    .daxBodyRegular()
                    .accessibilityIdentifier("PastedTextEditor.TextView")
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(designSystemColor: .lines)))

                Text(isOverLimit ? UserText.aiChatPastedTextOverLimit(count: count, limit: limit) : UserText.aiChatPastedTextCharacterCount(count))
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: isOverLimit ? .destructivePrimary : .textSecondary))
                    .accessibilityIdentifier("PastedTextEditor.Footer")
            }
            .padding(16)
            .navigationTitle(UserText.aiChatPastedTextLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UserText.actionCancel, action: onCancel)
                        .accessibilityIdentifier("PastedTextEditor.Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UserText.actionSave) { onSave(text) }
                        .disabled(!canSave)
                        .accessibilityIdentifier("PastedTextEditor.Save")
                }
            }
        }
    }
}
