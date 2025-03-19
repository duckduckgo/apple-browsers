//
//  OriginalOmniBarViewController.swift
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

final class OriginalOmniBarViewController: UIViewController, OmniBarViewController {

    var omniBarView: OmniBarView

    // MARK: - OmniBar conformance
    var omniDelegate: OmniBarDelegate?

    init(dependencies: OmnibarDependencyProvider) {
        omniBarView = OmniBarView.loadFromXib(dependencies: dependencies)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = omniBarView
    }

    // MARK: - OmniBar conformance

    func showSeparator() {

    }

    func hideSeparator() {

    }

    func moveSeparatorToTop() {

    }

    func moveSeparatorToBottom() {

    }

    func startBrowsing() {

    }

    func stopBrowsing() {

    }

    func startLoading() {

    }

    func stopLoading() {

    }

    func cancel() {

    }
}
