//
//  FormattedCreditCardTextField.swift
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

import AppKit
import Foundation
import SwiftUI
import BrowserServicesKit

/// A text field that formats the input as a credit card number.
/// The input is formatted with spaces every 4 digits (or 4-6-5 for Amex).
struct FormattedCreditCardTextField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String = ""
    var onBlur: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.bezelStyle = .roundedBezel
        textField.placeholderString = placeholder
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = placeholder

        guard nsView.stringValue != text else { return }

        context.coordinator.isUpdatingText = true
        nsView.stringValue = text
        context.coordinator.isUpdatingText = false
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {

        var parent: FormattedCreditCardTextField
        var isUpdatingText = false

        init(_ parent: FormattedCreditCardTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField, !isUpdatingText else {
                return
            }

            let currentText = textField.stringValue
            let currentSelectedRange = textField.textView?.selectedRange() ?? NSRange(location: currentText.count, length: 0)

            // Extract digits only and limit to maximum length
            var digitsOnly = CreditCardValidation.extractDigits(from: currentText)
            if digitsOnly.count > CreditCardValidation.maximumCardNumberLength {
                digitsOnly = String(digitsOnly.prefix(CreditCardValidation.maximumCardNumberLength))
            }

            // Format the card number
            let formatted = CreditCardValidation.formattedCardNumber(digitsOnly)

            isUpdatingText = true
            parent.text = formatted
            textField.stringValue = formatted
            isUpdatingText = false

            updateCursorPosition(textField, oldText: currentText, newText: formatted, currentSelection: currentSelectedRange)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onBlur?()
        }

        private func updateCursorPosition(_ textField: NSTextField, oldText: String, newText: String, currentSelection: NSRange) {
            guard let textView = textField.textView else {
                return
            }

            let cursorPosition = currentSelection.location

            // Count spaces before cursor in old and new text
            let oldTextPrefix = String(oldText.prefix(cursorPosition))
            let oldSpacesBeforeCursor = oldTextPrefix.filter { $0 == " " }.count

            let newTextPrefix = String(newText.prefix(min(cursorPosition, newText.count)))
            let newSpacesBeforeCursor = newTextPrefix.filter { $0 == " " }.count

            // Adjust cursor position by the difference in space counts
            var newCursorPosition = cursorPosition + (newSpacesBeforeCursor - oldSpacesBeforeCursor)
            newCursorPosition = min(newCursorPosition, newText.count)

            textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        }
    }
}

private extension NSTextField {
    var textView: NSTextView? {
        currentEditor() as? NSTextView
    }
}
