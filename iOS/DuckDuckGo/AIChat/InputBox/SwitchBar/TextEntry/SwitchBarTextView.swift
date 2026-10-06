//
//  SwitchBarTextView.swift
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


import UIKit
import SwiftUI
import Combine
import DesignResourcesKitIcons

final class SwitchBarTextView: UITextView {

    var onTouchesBeganHandler: (() -> Void)?

    /// When set, a native image/file paste is routed into the attachment strip; `nil` keeps default paste.
    weak var attachmentPasteHandler: AttachmentPasteHandling?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), AttachmentPasteRouting.canPaste(with: attachmentPasteHandler) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        guard AttachmentPasteRouting.routePaste(with: attachmentPasteHandler) else {
            super.paste(sender)
            return
        }
        if let text = UIPasteboard.general.string, !text.isEmpty {
            insertText(text)
        }
    }

    /// You'd think a gesture would be useful here, but it stops the menu from appearing, even if you tell it not to cancel touches, or if you tell it to delay touch begin/end.
    ///   So this is a little work around that does the job.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        onTouchesBeganHandler?()
    }

    override var canBecomeFirstResponder: Bool {
        !hasHiddenAncestor && super.canBecomeFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        guard !hasHiddenAncestor else { return false }
        return super.becomeFirstResponder()
    }

}

extension UIView {
    var hasHiddenAncestor: Bool {
        var view: UIView? = self
        while let current = view {
            if current.isHidden { return true }
            view = current.superview
        }
        return false
    }
}
