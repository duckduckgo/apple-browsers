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

    override var inputAccessoryView: UIView? {
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

    private func reloadContentViewInputViews() {
        guard let content = scrollView.subviews.first(
            where: { String(describing: type(of: $0)).hasPrefix("WKContent") })
        else { return }
        content.reloadInputViews()
    }
}
