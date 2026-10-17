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

/// View/edit sheet for one pasted-text chip. Cancel and swipe-down discard edits, as on the FE.
struct PastedTextEditorView: View {

    @State private var text: String
    private let limit: Int
    private let isReadOnly: Bool
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    init(pastedText: AIChatPastedText, otherContentLength: Int, maxInputCharacters: Int, isReadOnly: Bool = false,
         onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: pastedText.content)
        limit = AIChatPastedText.editLimit(ownLength: pastedText.length,
                                           otherContentLength: otherContentLength,
                                           maxInputCharacters: maxInputCharacters)
        self.isReadOnly = isReadOnly
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var count: Int { text.utf16.count }
    private var isOverLimit: Bool { count > limit }
    private var canSave: Bool { !isOverLimit && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var footer: Text {
        let secondary = Color(designSystemColor: .textSecondary)
        guard isOverLimit else {
            return Text(UserText.aiChatPastedTextCharacterCount(count)).foregroundColor(secondary)
        }
        return Text(UserText.aiChatPastedTextTooLong + " ").foregroundColor(secondary)
            + Text(String(count)).foregroundColor(Color(designSystemColor: .destructivePrimary))
            + Text(" / " + String(limit)).foregroundColor(secondary)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(UserText.aiChatPastedTextFormattingNote)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))

                // Cancel/Save live in the navigation bar, and the count sits in the keyboard-avoiding
                // safe area, so neither is hidden by the keyboard while editing.
                TextEditor(text: $text)
                    .daxBodyRegular()
                    .disabled(isReadOnly)
                    .accessibilityIdentifier("PastedTextEditor.TextView")
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(designSystemColor: .lines)))

                footer
                    .daxFootnoteRegular()
                    .accessibilityIdentifier("PastedTextEditor.Footer")
            }
            .padding(16)
            .navigationTitle(UserText.aiChatPastedTextSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? UserText.navigationTitleDone : UserText.actionCancel, action: onCancel)
                        .accessibilityIdentifier("PastedTextEditor.Cancel")
                }
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(UserText.actionSave) { onSave(text) }
                            .disabled(!canSave)
                            .accessibilityIdentifier("PastedTextEditor.Save")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// The one presentation of the editor, shared by the iPhone input and the iPad address bar.
///
/// A form sheet is a large-detent sheet at compact width (iPhone, iPad Slide Over and narrow split
/// view) and a centred card at regular width, so one style covers every size class. `onDismiss`
/// runs once however the sheet goes away (Save, Cancel or a swipe), so the caller can give focus
/// back to its input.
@MainActor
enum PastedTextEditorPresenter {

    static func present(_ pastedText: AIChatPastedText,
                        otherContentLength: Int,
                        maxInputCharacters: Int,
                        isReadOnly: Bool = false,
                        from presenter: UIViewController,
                        onSave: @escaping (String) -> Void,
                        onDismiss: @escaping () -> Void) {
        weak var weakController: UIViewController?
        let editor = PastedTextEditorView(
            pastedText: pastedText,
            otherContentLength: otherContentLength,
            maxInputCharacters: maxInputCharacters,
            isReadOnly: isReadOnly,
            onSave: { content in
                onSave(content)
                weakController?.dismiss(animated: true)
            },
            onCancel: {
                weakController?.dismiss(animated: true)
            }
        )
        let controller = PastedTextEditorHostingController(rootView: editor, onDismiss: onDismiss)
        controller.modalPresentationStyle = .formSheet
        if let sheet = controller.sheetPresentationController {
            // Large only: at 4,000+ characters a medium detent plus the keyboard leaves almost no text visible.
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        weakController = controller
        topmost(from: presenter).present(controller, animated: true)
    }

    /// Presents over whatever the host already shows, such as the contextual sheet, rather than failing.
    private static func topmost(from presenter: UIViewController) -> UIViewController {
        var top = presenter
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

private final class PastedTextEditorHostingController: UIHostingController<PastedTextEditorView> {

    private var onDismiss: (() -> Void)?

    init(rootView: PastedTextEditorView, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        let onDismiss = self.onDismiss
        self.onDismiss = nil
        onDismiss?()
    }
}
