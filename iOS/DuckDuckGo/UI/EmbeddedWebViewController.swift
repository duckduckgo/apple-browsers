//
//  EmbeddedWebViewController.swift
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
import SwiftUI
import PrivacyConfig

final class EmbeddedWebViewController: UIViewController {
    private let webViewModel: AsyncHeadlessWebViewViewModel
    let url: URL

    init(url: URL, userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
         featureFlagger: FeatureFlagger) {
        self.url = url

        let settings = AsyncHeadlessWebViewSettings(bounces: false,
                                                    userScriptsDependencies: userScriptsDependencies,
                                                    featureFlagger: featureFlagger)

        webViewModel = AsyncHeadlessWebViewViewModel(settings: settings)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
    }

}

// MARK: - Private

private extension EmbeddedWebViewController {

    func setupView() {
        let contentView = makeContentView()
        let hostingController = UIHostingController(rootView: contentView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    func makeContentView() -> some View {
        // Avoid retain cycles due to @autoclouse @StateObject
        let context = (viewModel: webViewModel, url: url)

        return AsyncHeadlessWebView(viewModel: context.viewModel)
            .onAppear {
                context.viewModel.navigationCoordinator.navigateTo(url: context.url)
            }
    }

    @objc
    func dismissModal() {
        presentingViewController?.dismiss(animated: true)
    }

}
