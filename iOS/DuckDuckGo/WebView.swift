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
import os.log

final class WebView: WKWebView {
    private var customAccesoryView: UIView?
    private(set) var inputAccessoryViewHidden = false

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

    private func reloadContentViewInputViews() {
        guard let content = scrollView.subviews.first(
            where: { String(describing: type(of: $0)).hasPrefix("WKContent") })
        else { return }
        content.reloadInputViews()
    }
}
