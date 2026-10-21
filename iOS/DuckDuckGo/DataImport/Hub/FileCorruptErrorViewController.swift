//
//  FileCorruptErrorViewController.swift
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

final class FileCorruptErrorViewController: UIViewController {

    private let fileError: DataImportFileError
    var onDismissed: (() -> Void)?

    init(error: DataImportFileError) {
        self.fileError = error
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        let errorView = FileCorruptErrorView(
            title: fileError.title,
            message: fileError.message,
            onGotIt: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.onDismissed?()
                }
            })
        let hostingController = UIHostingController(rootView: errorView)
        hostingController.view.backgroundColor = .clear
        installChildViewController(hostingController)
    }
}
