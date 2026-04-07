//
//  ImportSourceDetailViewController.swift
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

final class ImportSourceDetailViewController: UIViewController {

    private let source: ImportPasswordSource

    init(source: ImportPasswordSource) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = source.detailTitle
        setupView()
    }

    private func setupView() {
        let detailView = ImportSourceDetailView(
            source: source,
            onPrimaryAction: { [weak self] in
                self?.handlePrimaryAction()
            },
            onUploadFile: { [weak self] in
                self?.handleUploadFile()
            },
            onGetDesktopBrowser: { [weak self] in
                self?.handleGetDesktopBrowser()
            })
        let hostingController = UIHostingController(rootView: detailView)
        hostingController.view.backgroundColor = .clear
        installChildViewController(hostingController)
    }

    private func handlePrimaryAction() {
        // Wired up in future PR
    }

    private func handleUploadFile() {
        // Wired up in future PR
    }

    private func handleGetDesktopBrowser() {
        // Wired up in future PR
    }
}
