//
//  MultiTabMentionController.swift
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

@MainActor
protocol TextEntryMentionHandling: AnyObject {
    func textDidChange(in textView: UITextView)
    func selectionDidChange(in textView: UITextView)
    func dismiss()
}

@MainActor
final class MultiTabMentionController: TextEntryMentionHandling {
    struct Environment {
        let isEnabled: () -> Bool
        let tabs: () -> [MultiTabAttachmentCandidate]
        let attachedTabIds: () -> Set<TabUID>
        let toggleAttachment: (MultiTabAttachmentCandidate) -> Bool
    }

    private let environment: Environment
    private let presenter: any MultiTabMentionPresenting
    private weak var textView: UITextView?
    private var activeToken: MultiTabMentionToken?
    private var dismissedToken: MultiTabMentionToken?
    private var isAccepting = false
    private var pendingUpdate: Task<Void, Never>?
    private var allowsPendingPresentation = false

    init(environment: Environment, presenter: any MultiTabMentionPresenting) {
        self.environment = environment
        self.presenter = presenter
    }

    func textDidChange(in textView: UITextView) {
        scheduleUpdate(in: textView, allowsPresentation: true)
    }

    func selectionDidChange(in textView: UITextView) {
        scheduleUpdate(in: textView, allowsPresentation: false)
    }

    func dismiss() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        allowsPendingPresentation = false
        activeToken = nil
        dismissedToken = nil
        textView = nil
        presenter.dismiss()
    }

    private func scheduleUpdate(in textView: UITextView, allowsPresentation: Bool) {
        guard !isAccepting else { return }
        pendingUpdate?.cancel()
        allowsPendingPresentation = allowsPendingPresentation || allowsPresentation
        // Selection callbacks can precede text-change callbacks. Read both after the edit settles.
        pendingUpdate = Task { @MainActor [weak self, weak textView] in
            guard !Task.isCancelled, let self, let textView else { return }
            let allowsPresentation = self.allowsPendingPresentation
            self.allowsPendingPresentation = false
            self.update(in: textView, allowsPresentation: allowsPresentation)
        }
    }

    private func update(in textView: UITextView, allowsPresentation: Bool) {
        guard environment.isEnabled(), textView.isFirstResponder, textView.window != nil,
              textView.markedTextRange == nil,
              let token = MultiTabMentionToken.token(in: textView.text ?? "", selection: textView.selectedRange) else {
            dismiss()
            return
        }
        if let dismissedToken, dismissedToken != token {
            self.dismissedToken = nil
        }
        // Dismissal suppresses the unchanged token; editing its query can open the picker again.
        guard dismissedToken != token else { return }
        // Moving the caret or restoring a draft can update an open picker, but cannot open one.
        guard allowsPresentation || activeToken != nil else { return }
        guard let position = textView.position(from: textView.beginningOfDocument, offset: token.range.location) else { return }
        self.textView = textView
        activeToken = token
        presenter.present(tabs: token.filter(environment.tabs()),
                          attachedTabIds: environment.attachedTabIds(),
                          sourceView: textView,
                          sourceRect: textView.caretRect(for: position),
                          onSelect: { [weak self] in self?.accept($0) },
                          onDismiss: { [weak self] in
            guard let self else { return }
            self.dismissedToken = self.activeToken
            self.activeToken = nil
        })
    }

    private func accept(_ candidate: MultiTabAttachmentCandidate) {
        guard environment.isEnabled(), let textView, textView.isFirstResponder,
              textView.markedTextRange == nil, let activeToken,
              MultiTabMentionToken.token(in: textView.text ?? "", selection: textView.selectedRange) == activeToken,
              let start = textView.position(from: textView.beginningOfDocument, offset: activeToken.range.location),
              let end = textView.position(from: start, offset: activeToken.range.length),
              let range = textView.textRange(from: start, to: end),
              textView.delegate?.textView?(textView, shouldChangeTextIn: activeToken.range, replacementText: "") != false else {
            dismiss()
            return
        }
        isAccepting = true
        defer {
            dismiss()
            isAccepting = false
        }
        // A tab may close or navigate while the menu is visible. Keep the token if attachment fails.
        guard environment.toggleAttachment(candidate) else { return }
        textView.replace(range, withText: "")
        textView.selectedRange = NSRange(location: activeToken.range.location, length: 0)
        textView.delegate?.textViewDidChange?(textView)
    }
}
