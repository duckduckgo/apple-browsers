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

    /// An item offered on a text selection.
    enum TextSelectionMenuItem: Equatable {
        case askAIChat
        case searchWithDuckDuckGo
    }

    /// Re-evaluated on every menu build, so flag and setting changes take effect immediately.
    var isAskAIChatItemAvailable: (() -> Bool)?
    var isSearchWithDuckDuckGoItemAvailable: (() -> Bool)?

    /// Receives the trimmed selection when the user picks Ask Duck.ai.
    var askAIChatHandler: ((String) -> Void)?

    /// Receives the trimmed selection when the user picks Search with DuckDuckGo.
    var searchWithDuckDuckGoHandler: ((String) -> Void)?

    /// The frame holding the selection.
    var selectionFrameProvider: (() -> SelectionFrame?)?

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

    /// Adds our items to the text-selection menu.
    ///
    /// Overridden on the subclass because `WKWebView` consumes `buildMenu(with:)` rather than propagating it
    /// up the responder chain since iOS 18.2. Anchored after `.standardEdit` so the items sit beside Copy —
    /// appending to the root menu was verified on device to put them in the overflow menu only.
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        let items = selectionMenuItems(forSystem: builder.system)
        guard !items.isEmpty else { return }

        builder.insertSibling(UIMenu(title: "", options: .displayInline, children: items.map(makeAction)),
                              afterMenu: .standardEdit)
    }

    /// The items to offer, in display order. Selection menu only; the main menu system drives the iPad
    /// menu bar, which has no selection to act on.
    func selectionMenuItems(forSystem system: UIMenuSystem) -> [TextSelectionMenuItem] {
        guard system != .main else { return [] }

        var items: [TextSelectionMenuItem] = []
        if isAskAIChatItemAvailable?() == true { items.append(.askAIChat) }
        if isSearchWithDuckDuckGoItemAvailable?() == true { items.append(.searchWithDuckDuckGo) }
        return items
    }

    private func makeAction(for item: TextSelectionMenuItem) -> UIAction {
        switch item {
        case .askAIChat:
            return UIAction(title: UserText.actionAskAIChat,
                            image: DesignSystemImages.Glyphs.Size16.aiChat) { [weak self] _ in
                self?.withCurrentSelection { self?.askAIChatHandler?($0) }
            }
        case .searchWithDuckDuckGo:
            return UIAction(title: UserText.actionSearchWithDuckDuckGo,
                            image: DesignSystemImages.Glyphs.Size16.searchFind) { [weak self] _ in
                self?.withCurrentSelection { self?.searchWithDuckDuckGoHandler?($0) }
            }
        }
    }

    /// The selection trimmed of surrounding whitespace, or nil when nothing usable remains.
    ///
    /// Uncapped, matching macOS: consumers need the real length, so truncation belongs to whoever builds
    /// a payload from it.
    static func normalizedSelection(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The user's selection, trimmed, or nil when nothing usable is selected. Lets an entry point other
    /// than the edit menu pick a selection up. Same content world as `withCurrentSelection`.
    func currentSelection() async -> String? {
        await withCheckedContinuation { continuation in
            readSelection { continuation.resume(returning: $0) }
        }
    }

    /// Reads in the isolated content world so page-world overrides cannot replace the selection reader.
    ///
    /// Returns the snapshot the script took when the selection was made, not a live read: by the time an
    /// action runs, the page has had time to swap the range or rewrite the text inside it.
    ///
    /// Deliberately the completion-handler overload: `evaluateJavaScript`'s `async` twin bridges the result
    /// back as `()` in this content world, so the selection never arrives.
    private func readSelection(_ completion: @escaping (String?) -> Void) {
        guard let frame = selectionFrameProvider?() else {
            completion(nil)
            return
        }

        let handler: (Result<Any, Error>) -> Void = { result in
            guard case .success(let value) = result,
                  let text = frame.selectedText(from: value) else {
                completion(nil)
                return
            }
            completion(Self.normalizedSelection(text))
        }

        frame.evaluateJavaScript(SelectionFrameUserScript.readSelectionScript,
                                 in: self,
                                 contentWorld: .defaultClient,
                                 completionHandler: handler)
    }

    private func withCurrentSelection(_ handler: @escaping (String) -> Void) {
        readSelection { selection in
            guard let selection else { return }
            handler(selection)
        }
    }

    private func reloadContentViewInputViews() {
        guard let content = scrollView.subviews.first(
            where: { String(describing: type(of: $0)).hasPrefix("WKContent") })
        else { return }
        content.reloadInputViews()
    }
}
