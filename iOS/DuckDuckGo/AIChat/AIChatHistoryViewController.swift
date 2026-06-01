//
//  AIChatHistoryViewController.swift
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

import SwiftUI
import UIKit

/// View controller for the native Duck.ai chat-history sheet.
final class AIChatHistoryViewController: UIViewController {

    private let viewModel: AIChatHistoryViewModel

    init(viewModel: AIChatHistoryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = UserText.actionAIChatHistory
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: UserText.navigationTitleDone,
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )

        embedEmptyState()
    }

    private func embedEmptyState() {
        let host = UIHostingController(rootView: AIChatHistoryEmptyStateView(viewModel: viewModel))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
}
