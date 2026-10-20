//
//  PastedTextSheet.swift
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

enum PastedTextSheetMode: Equatable {
    case editable(limit: Int)
    /// A paste from a sent prompt: the web app matches returned pastes by content, so it can be read, not changed.
    case viewOnly
}

enum PastedTextSheetOutcome: Equatable {
    case saved(AIChatPastedText)
    case unchanged
}

struct PastedTextSheetRules: Equatable {
    let original: AIChatPastedText
    let mode: PastedTextSheetMode

    func count(of text: String) -> Int { text.utf16.count }

    func isOverLimit(_ text: String) -> Bool {
        guard case .editable(let limit) = mode else { return false }
        return count(of: text) > limit
    }

    func canSave(_ text: String) -> Bool {
        guard case .editable = mode else { return false }
        return !AIChatPromptLimits.isBlank(text) && !isOverLimit(text)
    }

    var opensWithKeyboard: Bool { mode != .viewOnly }

    func outcome(savingText text: String) -> PastedTextSheetOutcome {
        text == original.content ? .unchanged : .saved(AIChatPastedText(content: text))
    }
}

struct PastedTextSheetView: View {

    @State private var text: String
    @FocusState private var isTextFocused: Bool
    private let rules: PastedTextSheetRules
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    init(pastedText: AIChatPastedText, mode: PastedTextSheetMode, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: pastedText.content)
        rules = PastedTextSheetRules(original: pastedText, mode: mode)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isViewOnly: Bool { rules.mode == .viewOnly }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(UserText.aiChatPastedTextFormattingNote)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))

                Group {
                    if isViewOnly {
                        PastedTextReadOnlyView(text: text)
                    } else {
                        TextEditor(text: $text)
                            .daxBodyRegular()
                            .focused($isTextFocused)
                    }
                }
                .accessibilityIdentifier("PastedTextSheet.TextView")
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(designSystemColor: .lines)))

                Text(countLine)
                    .daxFootnoteRegular()
                    .accessibilityIdentifier("PastedTextSheet.Count")
            }
            .padding(16)
            .onAppear { isTextFocused = rules.opensWithKeyboard }
            .navigationTitle(UserText.aiChatPastedTextSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isViewOnly ? UserText.navigationTitleDone : UserText.actionCancel, action: onCancel)
                        .accessibilityIdentifier("PastedTextSheet.Cancel")
                }
                if !isViewOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(UserText.actionSave) { onSave(text) }
                            .disabled(!rules.canSave(text))
                            .accessibilityIdentifier("PastedTextSheet.Save")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var countLine: AttributedString {
        let count = rules.count(of: text)
        let secondary = Color(designSystemColor: .textSecondary)
        guard case .editable(let limit) = rules.mode, rules.isOverLimit(text) else {
            var line = AttributedString(UserText.aiChatPastedTextCharacterCount(count))
            line.foregroundColor = secondary
            return line
        }
        var line = AttributedString(UserText.aiChatPastedTextOverLimitCount(count: count, limit: limit))
        line.foregroundColor = secondary
        if let range = line.range(of: String(count)) {
            line[range].foregroundColor = Color(designSystemColor: .destructivePrimary)
        }
        return line
    }
}

/// A disabled `TextEditor` cannot scroll, so the view-only sheet shows its text in a `UITextView` that scrolls and selects but never edits.
private struct PastedTextReadOnlyView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .daxBodyRegular()
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }
}

@MainActor
enum PastedTextSheetPresenter {

    static func present(_ pastedText: AIChatPastedText,
                        mode: PastedTextSheetMode,
                        from host: UIViewController,
                        completion: @escaping (PastedTextSheetOutcome) -> Void) {
        let rules = PastedTextSheetRules(original: pastedText, mode: mode)
        weak var weakController: PastedTextSheetHostingController?
        let view = PastedTextSheetView(
            pastedText: pastedText,
            mode: mode,
            onSave: { text in
                weakController?.finish(rules.outcome(savingText: text))
                weakController?.dismiss(animated: true)
            },
            onCancel: {
                weakController?.dismiss(animated: true)
            }
        )
        let controller = PastedTextSheetHostingController(rootView: view, completion: completion)
        controller.modalPresentationStyle = .formSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        weakController = controller
        topmost(from: host).present(controller, animated: true)
    }

    static func topmost(from host: UIViewController) -> UIViewController {
        var top = host
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

final class PastedTextSheetHostingController: UIHostingController<PastedTextSheetView> {

    private var completion: ((PastedTextSheetOutcome) -> Void)?

    init(rootView: PastedTextSheetView, completion: @escaping (PastedTextSheetOutcome) -> Void) {
        self.completion = completion
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func finish(_ outcome: PastedTextSheetOutcome) {
        guard let completion else { return }
        self.completion = nil
        completion(outcome)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        finish(.unchanged)
    }
}
