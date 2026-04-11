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
import DDGSync

final class DataImportHubViewController: UIViewController {

    private let viewModel = DataImportHubViewModel()
    private let syncService: DDGSyncing
    private let onCancelled: (() -> Void)?
    private var didCallOnCancelled = false

    init(syncService: DDGSyncing,
         onCancelled: (() -> Void)? = nil) {
        self.syncService = syncService
        self.onCancelled = onCancelled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupActions()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        callOnCancelledIfNeeded()
    }

    private func setupView() {
        let controller = UIHostingController(rootView: DataImportHubView(viewModel: viewModel))
        controller.view.backgroundColor = .clear
        installChildViewController(controller)
    }

    private func setupActions() {
        viewModel.onAction = { [weak self] action in
            self?.handleAction(action)
        }
    }

    private func handleAction(_ action: DataImportHubViewModel.Action) {
        switch action {
        case .importPasswords:
            navigateToSourceSelection()
        case .importBookmarksFromSafari, .uploadExportedFile:
            // Will be tackled in subsequent PR
            break
        }
    }

    private func navigateToSourceSelection() {
        let sourceSelectionVC = ImportSourceSelectionViewController()
        sourceSelectionVC.onSourceSelected = { [weak self] source in
            self?.navigateToSource(source)
        }
        navigationController?.pushViewController(sourceSelectionVC, animated: true)
    }

    private func navigateToSource(_ source: ImportPasswordSource) {
        if source.hasDetailScreen {
            let detailVC = ImportSourceDetailViewController(source: source)
            navigationController?.pushViewController(detailVC, animated: true)
        } else {
            navigateToImportViaSync()
        }
    }

    private func navigateToImportViaSync() {
        let importController = ImportPasswordsViaSyncViewController(syncService: syncService)
        importController.delegate = self
        navigationController?.pushViewController(importController, animated: true)
    }

    private func callOnCancelledIfNeeded() {
        guard !didCallOnCancelled else { return }
        guard isBeingDismissed || navigationController?.isBeingDismissed == true || isMovingFromParent else { return }
        didCallOnCancelled = true
        onCancelled?()
    }
}

// MARK: - ImportPasswordsViaSyncViewControllerDelegate

extension DataImportHubViewController: ImportPasswordsViaSyncViewControllerDelegate {

    func importPasswordsViaSyncViewControllerDidRequestOpenSync(_ viewController: ImportPasswordsViaSyncViewController) {
        if let settingsVC = navigationController?.children.first as? SettingsHostingController {
            navigationController?.popToRootViewController(animated: true)
            settingsVC.viewModel.presentLegacyView(.sync(nil))
        } else if let mainVC = presentingViewController as? MainViewController {
            dismiss(animated: true) {
                mainVC.segueToSettingsSync(with: nil)
            }
        }
    }
}
