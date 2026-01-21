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
/// The input is formatted with spaces every 4 digits.
/// The text field also manages the
struct FormattedCreditCardTextField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String = ""

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

        let currentEditor = nsView.textView
        let currentSelectedRange = currentEditor?.selectedRange() ?? NSRange(location: text.count, length: 0)
        nsView.stringValue = text

        // Restore cursor position if possible
        if let currentEditor {
            let newPosition = min(currentSelectedRange.location, text.count)
            currentEditor.setSelectedRange(NSRange(location: newPosition, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {

        var parent: FormattedCreditCardTextField
        private var isUpdatingText = false

        init(_ parent: FormattedCreditCardTextField) {
            self.parent = parent
        }

    }
}

private extension NSTextField {
    var textView: NSTextView? {
        currentEditor() as? NSTextView
    }
}
