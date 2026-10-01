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
        let canAttach: (TabUID) -> Bool
        let toggleAttachment: (MultiTabAttachmentCandidate) -> Bool
    }

    struct Suggestion: Equatable {
        let candidate: MultiTabAttachmentCandidate
        let isSelected: Bool
        let isEnabled: Bool
    }

    var onSuggestionsChanged: (([Suggestion]?) -> Void)?
    private let environment: Environment
    private weak var textView: UITextView?
    private var activeToken: MultiTabMentionToken?
    private var isAccepting = false
    private var pendingUpdate: Task<Void, Never>?

    init(environment: Environment) {
        self.environment = environment
    }

    func textDidChange(in textView: UITextView) {
        scheduleUpdate(in: textView)
    }

    func selectionDidChange(in textView: UITextView) {
        scheduleUpdate(in: textView)
    }

    func dismiss() {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        activeToken = nil
        textView = nil
        onSuggestionsChanged?(nil)
    }

    private func scheduleUpdate(in textView: UITextView) {
        guard !isAccepting else { return }
        guard environment.isEnabled() else {
            dismiss()
            return
        }
        pendingUpdate?.cancel()
        // Selection callbacks can precede text-change callbacks. Read both after the edit settles.
        pendingUpdate = Task { @MainActor [weak self, weak textView] in
            guard !Task.isCancelled, let self, let textView else { return }
            self.update(in: textView)
        }
    }

    private func update(in textView: UITextView) {
        guard environment.isEnabled(), textView.isFirstResponder, textView.window != nil,
              textView.markedTextRange == nil,
              let token = MultiTabMentionToken.token(in: textView.text ?? "", selection: textView.selectedRange) else {
            dismiss()
            return
        }
        let candidates = MultiTabAttachmentCandidateFilter.filter(environment.tabs(), query: token.query)
        if candidates.isEmpty, token.query.rangeOfCharacter(from: .whitespaces) != nil {
            dismiss()
            return
        }
        self.textView = textView
        activeToken = token
        let selectedIDs = environment.attachedTabIds()
        onSuggestionsChanged?(candidates.map {
            let isSelected = selectedIDs.contains($0.tabId)
            return Suggestion(candidate: $0, isSelected: isSelected,
                              isEnabled: isSelected || environment.canAttach($0.tabId))
        })
    }

    /// Metadata or attachment changes refresh only an already visible suggestion list.
    func refresh() {
        guard !isAccepting, activeToken != nil, let textView else { return }
        update(in: textView)
    }

    func accept(_ candidate: MultiTabAttachmentCandidate) {
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
        // A tab may close or navigate while suggestions are visible. Keep the token if attachment fails.
        guard environment.toggleAttachment(candidate) else { return }
        textView.replace(range, withText: "")
        textView.selectedRange = NSRange(location: activeToken.range.location, length: 0)
        textView.delegate?.textViewDidChange?(textView)
    }
}
