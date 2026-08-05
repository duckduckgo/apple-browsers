//
//  WebView.swift
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
import WebKit
import DesignResourcesKitIcons
import os.log

final class WebView: WKWebView {
    private var customAccesoryView: UIView?
    private(set) var inputAccessoryViewHidden = false

    /// Evaluated synchronously each time the edit menu is built, so feature-flag and user-setting changes take effect immediately.
    var isAskAIChatMenuAvailable: (() -> Bool)?

    /// Called with the picked action and the trimmed selection when the user taps one of the Duck.ai
    /// edit-menu items. The selection is passed at full length; truncation for the wire payload belongs
    /// to whoever builds it, since the untruncated length and word count are part of that payload.
    var askAIChatHandler: ((AIChatTextSelectionAction, String) -> Void)?

    // Remembers the last find-in-page query so the system find navigator can be prepopulated per tab.
    var lastFindInPageQuery: String?

    private var findInPageQueryObserver: NSObjectProtocol?

    /// Tracks the system find navigator's query so the last term is remembered per tab, even when dismissed via the
    /// system Done button (which bypasses our own dismissal path). The navigator's search field posts
    /// `textDidChangeNotification` as the user types, so we snapshot the query while the navigator is visible.
    @available(iOS 16.0, *)
    func beginTrackingFindInPageQuery() {
        guard findInPageQueryObserver == nil else { return }
        findInPageQueryObserver = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification,
                                                                         object: nil,
                                                                         queue: .main) { [weak self] _ in
            guard let self, let interaction = self.findInteraction, interaction.isFindNavigatorVisible else { return }
            // Persist the current query as-is (including when cleared to nil) so clearing the field is remembered.
            self.lastFindInPageQuery = interaction.searchText
        }
    }

    deinit {
        if let findInPageQueryObserver {
            NotificationCenter.default.removeObserver(findInPageQueryObserver)
        }
    }

    override var inputAccessoryView: UIView? {
        if inputAccessoryViewHidden {
            return nil
        }

        guard customAccesoryView != nil else {
            return super.inputAccessoryView
        }

        return customAccesoryView
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    func setAccessoryContentView(_ contentView: UIView) {
        customAccesoryView = contentView
        reloadContentViewInputViews()
    }

    func removeAccessoryContentViewIfNecessary() {
        guard customAccesoryView != nil else { return }

        customAccesoryView = nil
        reloadContentViewInputViews()
    }

    func setInputAccessoryViewHidden(_ hidden: Bool) {
        guard inputAccessoryViewHidden != hidden else { return }
        inputAccessoryViewHidden = hidden
        reloadContentViewInputViews()
    }

    /// Since iOS 18.2 `WKWebView` consumes `buildMenu(with:)` rather than propagating it up the responder chain,
    /// so the selection edit menu can only be extended from the web view subclass itself.
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard #available(iOS 16.0, *) else { return }
        guard shouldInsertAskAIChatMenu(forSystem: builder.system) else { return }

        // Exactly one item, and deliberately so. "Summarize" and "Translate" read as system actions —
        // iOS has its own Translate — so a user could tap one expecting the OS and instead send the
        // selected text to Duck.ai. When the selection might be bank details, a surprise like that is
        // not recoverable. Only an explicitly Duck.ai-labelled item is offered; summarize and translate
        // are reachable from the sheet, after the user has chosen to involve Duck.ai at all.
        let askAction = UIAction(title: UserText.actionAskAIChat,
                                 image: DesignSystemImages.Glyphs.Size16.aiChat) { [weak self] _ in
            self?.requestAskAIChatWithSelectedText(action: .ask)
        }

        builder.insertSibling(UIMenu(title: "", options: .displayInline, children: [askAction]),
                              afterMenu: .standardEdit)
    }

    /// The items belong to the selection edit menu only; the main menu system drives the iPad menu bar, which
    /// has no selection context to act on.
    func shouldInsertAskAIChatMenu(forSystem system: UIMenuSystem) -> Bool {
        guard system != .main else { return false }
        return isAskAIChatMenuAvailable?() == true
    }

    /// Returns the selection trimmed of surrounding whitespace, or nil when nothing usable remains.
    ///
    /// Deliberately does not cap the length: the payload's `fullContentLength` and `wordCount` describe
    /// the untruncated selection, so capping here would silently under-report both. This matches macOS,
    /// which passes the selection through uncapped and truncates only when building the payload.
    static func normalizedAskAIChatSelection(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The page's current selection, trimmed, or nil when there is nothing usable selected.
    ///
    /// Lets an entry point other than the edit menu — opening the Duck.ai sheet from the omnibar while
    /// text happens to be selected — pick the selection up and treat it as an "Ask Duck.ai".
    func currentAskAIChatSelection() async -> String? {
        let result = try? await evaluateJavaScript("window.getSelection().toString()")
        guard let text = result as? String else { return nil }
        return Self.normalizedAskAIChatSelection(text)
    }

    private func requestAskAIChatWithSelectedText(action: AIChatTextSelectionAction) {
        evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let self, let handler = self.askAIChatHandler else { return }
            guard let text = result as? String,
                  let selection = Self.normalizedAskAIChatSelection(text) else { return }
            handler(action, selection)
        }
    }

    private func reloadContentViewInputViews() {
        guard let content = scrollView.subviews.first(
            where: { String(describing: type(of: $0)).hasPrefix("WKContent") })
        else { return }
        content.reloadInputViews()
    }
}
