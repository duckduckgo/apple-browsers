//
//  DataImportHubViewController.swift
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
import SwiftUI

final class DataImportHubViewController: UIViewController {

    private let viewModel = DataImportHubViewModel()
    private let onCancelled: (() -> Void)?
    private var didCallOnCancelled = false

    init(onCancelled: (() -> Void)? = nil) {
        self.onCancelled = onCancelled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupView()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        callOnCancelledIfNeeded()
    }

    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
    }

    private func setupView() {
        // First stacked PR: hub rows are intentionally non-navigational placeholders.
        let controller = UIHostingController(rootView: DataImportHubView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }

    private func callOnCancelledIfNeeded() {
        guard !didCallOnCancelled else { return }
        guard isBeingDismissed || navigationController?.isBeingDismissed == true || isMovingFromParent else { return }
        didCallOnCancelled = true
        onCancelled?()
    }
}
