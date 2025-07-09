//
//  NewTabPageOmnibarActionHandler.swift
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

import NewTabPage
import AppKit

final class NewTabPageOmnibarActionHandler: NewTabPageOmnibarActionHandling {

    func openSearch(term: String, target: NewTabPage.NewTabPageDataModel.OpenTarget) {
        guard let mainWindowController = NSApp.delegateTyped.windowControllersManager.lastKeyMainWindowController,
              let searchURL = URL.makeSearchUrl(from: term) else {
            assertionFailure("Failed to open search")
            return
        }

        NewTabPageLinkOpener.open(
            searchURL,
            source: .ui,
            sender: .userScript,
            target: target.linkOpenTarget,
            sourceWindow: mainWindowController.window
        )
    }

}

extension NewTabPageDataModel.OpenTarget {

    var linkOpenTarget: LinkOpenTarget {
        switch self {
        case .sameTab:
            return .current
        case .newTab:
            return .newTab
        case .newWindow:
            return .newWindow
        }
    }

}
