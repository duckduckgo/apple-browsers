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
import SafariServices
import Core
import Common
import DDGSync
import BrowserKit
import os.log

final class ImportSourceDetailViewController: UIViewController {

    private let source: ImportPasswordSource
    private let syncService: DDGSyncing
    private let fileUploadCoordinator: DataImportFileUploadCoordinating
    private let onFinished: (() -> Void)?

    init(source: ImportPasswordSource,
         syncService: DDGSyncing,
         fileUploadCoordinator: DataImportFileUploadCoordinating,
         onFinished: (() -> Void)? = nil) {
        self.source = source
        self.syncService = syncService
        self.fileUploadCoordinator = fileUploadCoordinator
        self.onFinished = onFinished
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
            })
        let hostingController = UIHostingController(rootView: detailView)
        hostingController.view.backgroundColor = .clear
        installChildViewController(hostingController)
    }

    // MARK: - Primary Action

    private func handlePrimaryAction() {
        switch source {
        case .safari:
            presentSafariExportInterstitial()
        case .syncFromDuckDuckGo:
            break
        case .passwordsApp, .chrome:
            break
        }
    }

    private func presentSafariExportInterstitial() {
        let interstitialVC = SafariExportInterstitialViewController()
        interstitialVC.onRequestExport = { [weak self] in
            self?.triggerBrowserKitImport()
        }

        if let sheet = interstitialVC.sheetPresentationController {
            sheet.detents = [.medium()]
        }

        present(interstitialVC, animated: true)
    }

    private func triggerBrowserKitImport() {
        if #available(iOS 26.4, *) {
            let scene = view.window?.windowScene
            let manager = BEBrowserDataImportManager(scene: scene)
            let metadata = BEImportMetadata(supportForImportFromFiles: false)
            manager.requestImport(for: metadata) { _, error in
                if let error {
                    Logger.autofill.error("BrowserKit requestImport failed: \(error)")
                }
            }
            return
        } else {
            Logger.autofill.error("BrowserKit requestImport not available on this OS version")
        }
    }

    // MARK: - File Upload

    private func handleUploadFile() {
        fileUploadCoordinator.startUploadFlow(from: self)
    }

    // MARK: - Sync

    private func openSync() {
        Pixel.fire(pixel: .autofillLoginsImportSync)

        if let settingsVC = navigationController?.children.first as? SettingsHostingController {
            navigationController?.popToRootViewController(animated: true)
            settingsVC.viewModel.presentLegacyView(.sync(nil))
        } else if let mainVC = navigationController?.presentingViewController as? MainViewController ?? presentingViewController as? MainViewController {
            mainVC.dismiss(animated: true) {
                mainVC.segueToSettingsSync(with: nil)
            }
        }
    }
}

// MARK: - DataImportFileUploadFlowOwner

extension ImportSourceDetailViewController: DataImportFileUploadFlowOwner {

    func dataImportUploadDidCompleteSummary() {
        onFinished?()
        navigationController?.popToRootViewController(animated: true)
    }

    func dataImportUploadDidRequestSync(source: String?) {
        let mainViewController = navigationController?.presentingViewController as? MainViewController
        ?? presentingViewController as? MainViewController

        mainViewController?.dismiss(animated: true) {
            mainViewController?.segueToSettingsSync(with: source)
        }
    }

    func dataImportUploadDidCancel() {}
}
