//
//  SwitchBarTextField.swift
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

import UIKit

/// Single-line UITextField used in place of `SwitchBarTextView` when Duck.ai is off or toggle is disabled.
final class SwitchBarTextField: UITextField {

    var textLeftInset: CGFloat = 0
    var textRightInset: CGFloat = 0

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: UIEdgeInsets(top: 0, left: textLeftInset, bottom: 0, right: textRightInset))
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: UIEdgeInsets(top: 0, left: textLeftInset, bottom: 0, right: textRightInset))
    }

    override var canBecomeFirstResponder: Bool {
        !hasHiddenAncestor && super.canBecomeFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        guard !hasHiddenAncestor else { return false }
        return super.becomeFirstResponder()
    }
}
