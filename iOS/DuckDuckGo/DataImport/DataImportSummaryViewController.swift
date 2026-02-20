//
//  DataImportSummaryViewController.swift
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

import Foundation
import UIKit
import SwiftUI
import BrowserServicesKit
import Core
import DDGSync

final class DataImportSummaryViewController: UIViewController {

    private var viewModel: DataImportSummaryViewModel
    private let importScreen: DataImportViewModel.ImportScreen
    private let onCompletion: () -> Void
    private let onSegueToSync: (String?) -> Void

    init(summary: DataImportSummary, importScreen: DataImportViewModel.ImportScreen, syncService: DDGSyncing, onSegueToSync: @escaping (String?) -> Void, onCompletion: @escaping () -> Void) {
        self.viewModel = DataImportSummaryViewModel(summary: summary, importScreen: importScreen, syncService: syncService)
        self.importScreen = importScreen

        self.onCompletion = onCompletion
        self.onSegueToSync = onSegueToSync

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        Pixel.fire(pixel: .importResultDisplayed, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue])
    }

    private func setupView() {
        viewModel.delegate = self
        let controller = UIHostingController(rootView: DataImportSummaryView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }

}

// MARK: - DataImportSummaryViewModelDelegate

extension DataImportSummaryViewController: DataImportSummaryViewModelDelegate {

    func dataImportSummaryViewModelComplete(_ viewModel: DataImportSummaryViewModel) {
        if let navigationController = presentingViewController as? UINavigationController, navigationController.children.first is DataImportViewController {
            onCompletion()
        } else {
            dismiss(animated: true) { [weak self] in
                self?.onCompletion()
            }
        }
    }

    func dataImportSummaryViewModelDidRequestLaunchSync(_ viewModel: DataImportSummaryViewModel, source: String?) {
        guard let navigationController = presentingViewController as? UINavigationController else {
            onSegueToSync(source)
            return
        }

        // Try to find a parent controller of the expected types
        let parent = navigationController.topViewController as? (UIViewController & DataImportSyncSegueing)
            ?? navigationController.viewControllers.first(where: { $0 is DataImportSyncSegueing }) as? (UIViewController & DataImportSyncSegueing)
        
        if let parent = parent {
            dismiss(animated: true) {
                parent.segueToSync(source: source)
            }
        } else {
            onSegueToSync(source)
        }
    }
}

private protocol DataImportSyncSegueing {
    func segueToSync(source: String?)
}

extension AutofillLoginListViewController: DataImportSyncSegueing {}
extension BookmarksViewController: DataImportSyncSegueing {}
