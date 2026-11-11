//
//  MainViewController+BookmarksMenu.swift
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

extension MainViewController {

    @objc func menuToggleBookmarks() {
        guard menuCommandAvailability.isEnabled(.showBookmarks) else { return }
        let hide = menuCommandAvailability.state.presentation == .bookmarks
        dismissMenuPresentation { [weak self] in
            guard !hide else { return }
            self?.onBookmarksPressed()
        }
    }

    @objc func menuImportBookmarks() {
        guard menuCommandAvailability.isEnabled(.importBookmarks) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            if #available(iOS 18.2, *) {
                self.launchDataImport(source: .bookmarks, onFinished: {}, onCancelled: {})
            } else {
                self.bookmarksFileFlow.presentDocumentPicker(from: self)
            }
        }
    }

    @objc func menuExportBookmarks() {
        guard menuCommandAvailability.isEnabled(.exportBookmarks) else { return }
        dismissMenuPresentation { [weak self] in
            guard let self else { return }
            let anchor: UIView
            if let button = self.viewCoordinator.omniBar.barView.menuButton, button.window != nil, !button.isHidden {
                anchor = button
            } else {
                anchor = self.view
            }
            self.bookmarksFileFlow.exportHtmlFile(from: self, anchor: anchor)
        }
    }

    @objc func menuOpenBookmark(_ command: UICommand) {
        guard menuCommandAvailability.isEnabled(.openBookmark), let url = BookmarksMenuTree.bookmarkURL(from: command) else { return }
        dismissMenuPresentation { [weak self] in self?.bookmarksDidSelect(url: url) }
    }

}
