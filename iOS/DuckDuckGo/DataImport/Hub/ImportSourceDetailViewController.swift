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
import BrowserKit
import Persistence
import os.log

final class ImportSourceDetailViewController: UIViewController {

    private let source: ImportPasswordSource
    private let entryPoint: DataImportViewModel.ImportScreen
    private let keyValueStore: ThrowingKeyValueStoring
    private let fileUploadCoordinator: DataImportFileUploadCoordinating
    private let simulatedCompletionPersistor: DataImportHubSimulatedCompletionPersistor
    private let onFinished: (() -> Void)?
    private var didProgressFromDetails = false
    private var didCompleteFlow = false

    init(source: ImportPasswordSource,
         entryPoint: DataImportViewModel.ImportScreen,
         keyValueStore: ThrowingKeyValueStoring,
         fileUploadCoordinator: DataImportFileUploadCoordinating,
         onFinished: (() -> Void)? = nil) {
        self.source = source
        self.entryPoint = entryPoint
        self.keyValueStore = keyValueStore
        self.fileUploadCoordinator = fileUploadCoordinator
        self.simulatedCompletionPersistor = DataImportHubSimulatedCompletionPersistor(keyValueStore: keyValueStore)
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
        Pixel.fire(pixel: .importHubSourceInstructionsDisplayed, withAdditionalParameters: pixelContext.parameters)

        if source == .chrome || source == .passwordsApp {
            simulatedCompletionPersistor.setCredentialExchangeInstructionsShownDate()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard isMovingFromParent else {
            return
        }

        guard !didProgressFromDetails, !didCompleteFlow else {
            return
        }

        Pixel.fire(pixel: .importHubSourceInstructionsCancelled, withAdditionalParameters: pixelContext.parameters)
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
        guard source == .safari else { return }
        didProgressFromDetails = true
        Pixel.fire(pixel: .importHubSourcePrimaryTapped, withAdditionalParameters: entryPoint.importHubEntryPointParameters)
        simulatedCompletionPersistor.setSafariFileFlowStart(entryPoint: entryPoint)
        presentSafariExportInterstitial()
    }

    private func presentSafariExportInterstitial() {
        let interstitialVC = SafariExportInterstitialViewController(entryPoint: entryPoint)
        interstitialVC.onRequestExport = { [weak self] in
            self?.triggerBrowserKitImport()
        }
        present(interstitialVC, animated: true)
    }

    private func triggerBrowserKitImport() {
        if #available(iOS 26.4, *) {
            let pixelParameters = entryPoint.importHubEntryPointParameters
            Pixel.fire(pixel: .importHubBrowserkitRequested, withAdditionalParameters: pixelParameters)

            let scene = view.window?.windowScene
            let manager = BEBrowserDataImportManager(scene: scene)
            let metadata = BEImportMetadata(supportForImportFromFiles: false)
            manager.requestImport(for: metadata) { _, error in
                if let error {
                    Logger.autofill.error("BrowserKit requestImport failed: \(error)")
                    let nsError = error as NSError
                    let isBrowserKitCancellation = nsError.domain == "com.apple.BrowserKit.BrowserDataExchangeError" && nsError.code == 2

                    if isBrowserKitCancellation {
                        Pixel.fire(pixel: .importHubBrowserkitReturnedCancelled, withAdditionalParameters: pixelParameters)
                    } else {
                        Pixel.fire(pixel: .importHubBrowserkitReturnedFailure, error: error,
                                   withAdditionalParameters: pixelParameters)
                    }
                } else {
                    Pixel.fire(pixel: .importHubBrowserkitReturnedSuccess, withAdditionalParameters: pixelParameters)
                }
            }
            return
        } else {
            Logger.autofill.error("BrowserKit requestImport not available on this OS version")
        }
    }

    // MARK: - File Upload

    private func handleUploadFile() {
        didProgressFromDetails = true
        Pixel.fire(pixel: .importHubSourceUploadFileTapped, withAdditionalParameters: entryPoint.importHubEntryPointParameters)

        if let completionParameters = simulatedCompletionPersistor.consumeSafariFileCompletionParametersIfEligible() {
            Pixel.fire(pixel: .importHubSafariFileSimulatedCompletion, withAdditionalParameters: completionParameters)
        }

        fileUploadCoordinator.startUploadFlow(from: self, source: source)
    }

    private var pixelContext: DataImportHubPixelContext {
        DataImportHubPixelContext(entryPoint: entryPoint, source: source.id)
    }
}

// MARK: - DataImportFileUploadFlowOwner

extension ImportSourceDetailViewController: DataImportFileUploadFlowOwner {

    func dataImportUploadDidCompleteSummary() {
        didCompleteFlow = true
        onFinished?()
    }

    func dataImportUploadDidRequestSync(source: String?) {
        let mainViewController = navigationController?.presentingViewController as? MainViewController
        ?? presentingViewController as? MainViewController

        mainViewController?.dismiss(animated: true) {
            mainViewController?.segueToSettingsSync(with: source)
        }
    }

    func dataImportUploadDidRequestContinueToSafariImport() {
        // When the summary is presented from Safari import, dismissing it already returns
        // to this Safari detail screen, so pushing another Safari detail controller is redundant.
        guard source != .safari else { return }

        let safariDetailViewController = ImportSourceDetailViewController(
            source: .safari,
            entryPoint: entryPoint,
            keyValueStore: keyValueStore,
            fileUploadCoordinator: fileUploadCoordinator,
            onFinished: onFinished
        )
        navigationController?.pushViewController(safariDetailViewController, animated: true)
    }

    func dataImportUploadDidCancel() {}
}
