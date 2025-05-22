//
//  BrowserToggleInputView.swift
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
import UIKit

struct BrowserToggleInputView: View {
    @ObservedObject var viewModel: AIChatInputBoxViewModel

    private let lineHeight: CGFloat = 25
    private let maxLines: Int = 7
    private let minLines: Int = 3
    let submitButtonPressed: () -> Void

    enum Position {
        case top
        case bottom
    }

    var body: some View {
        inputTextView
            .animation(.easeInOut, value: viewModel.inputMode)
    }

    private var inputTextView: some View {
        VStack (spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if viewModel.inputMode == .search {
                    SearchTextField(text: $viewModel.inputText, placeholder: placeHolderText, onSubmit: submitButtonPressed)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                } else {
                    ChatTextEditor(text: $viewModel.inputText)
                }
                VStack {
                    if !viewModel.inputText.isEmpty {
                        Button {
                            viewModel.clearText()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: calculatedHeight)
            .padding(.horizontal)
            .padding(.top)
            .animation(.easeInOut, value: calculatedHeight)

            ActionButtonsView(
                mode: viewModel.inputMode,
                onDuckAssistTapped: { },
                onVoiceTapped: { },
                onWebAnswerTapped: { },
                onSendTapped: submitButtonPressed,
                isSendEnabled: !viewModel.inputText.isEmpty
            )
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
        }
    }

    var placeHolderText: String {
        switch viewModel.inputMode {
        case .search:
            return "Search..."
        case .chat:
            return "Type your message..."
        }
    }

    private var calculatedHeight: CGFloat {
        switch viewModel.inputMode {
        case .search:
            return lineHeight
        case .chat:
            var numberOfLines = min(viewModel.inputText.numberOfLines(), maxLines)
            numberOfLines = max(minLines, numberOfLines)
            return max(lineHeight, CGFloat(numberOfLines) * lineHeight)
        }
    }
}

struct SearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.returnKeyType = .search
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            if textField.text != text {
                DispatchQueue.main.async {
                    self.text = textField.text ?? ""
                }
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let text = textField.text, !text.isEmpty {
                DispatchQueue.main.async {
                    self.text = text
                    self.onSubmit()
                }
            }
            textField.resignFirstResponder()
            return true
        }
    }
}

struct ChatTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

extension String {
    func numberOfLines() -> Int {
        let lines = self.components(separatedBy: "\n")
        return lines.count
    }
}

#Preview {
    BrowserToggleInputView(viewModel: AIChatInputBoxViewModel(), submitButtonPressed: {})
}
