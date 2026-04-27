//
//  DataImportUserActivityHandler.swift
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

import Foundation
import AuthenticationServices
import os.log
import BrowserKit
import BrowserServicesKit
import Core
import Persistence

typealias DataImportResultHandler = (Result<DataImportSummary, Error>) -> Void

private enum DataImportUserActivityHandlerError: Error {
    case credentialImportFailed
}

struct CredentialExchangeImportResult {
    let summary: DataImportSummary
    let source: String
}

protocol DataImportUserActivityHandling {
    @discardableResult
    func handle(_ userActivity: NSUserActivity) -> Bool
}

protocol CredentialExchangeImportHandling {
    func handleImport(token: UUID) async -> CredentialExchangeImportResult?
}

final class DataImportUserActivityHandler: DataImportUserActivityHandling {

    static var browserKitImportActivityType: String {
        if #available(iOS 26.4, *) {
            return BEBrowserDataImportManager.userActivityType
        }
        return "BEBrowserDataExchangeImportActivity"
    }

    private let credentialExchangeImportHandler: CredentialExchangeImportHandling
    private let onImportResult: DataImportResultHandler
    private let simulatedCompletionPersistor: DataImportHubSimulatedCompletionPersistor
    private var lastHandledActivityIdentifier: String?

    init(credentialExchangeImportHandler: CredentialExchangeImportHandling = CredentialExchangeImportHandler(),
         keyValueStore: ThrowingKeyValueStoring,
         onImportResult: @escaping DataImportResultHandler = { _ in }) {
        self.credentialExchangeImportHandler = credentialExchangeImportHandler
        self.simulatedCompletionPersistor = DataImportHubSimulatedCompletionPersistor(keyValueStore: keyValueStore)
        self.onImportResult = onImportResult
    }

    @discardableResult
    func handle(_ userActivity: NSUserActivity) -> Bool {
        if userActivity.activityType == Self.browserKitImportActivityType {
            return handleBrowserKitImport(userActivity)
        }

        if userActivity.activityType == Self.credentialExchangeActivityType {
            return handleCredentialExchange(userActivity)
        }

        return false
    }

    // MARK: - BrowserKit Import

    private func handleBrowserKitImport(_ userActivity: NSUserActivity) -> Bool {
        guard let importToken = Self.browserKitImportToken(from: userActivity) else {
            Logger.general.error("Skipping BrowserKit data import activity without import token")
            return false
        }
        let activityIdentifier = importToken.uuidString

        guard shouldHandleActivity(withIdentifier: activityIdentifier) else {
            Logger.general.debug("Skipping duplicate BrowserKit data import activity")
            return true
        }

        NotificationCenter.default.post(name: .didReceiveBrowserKitDataImportActivity, object: userActivity)
        return true
    }

    // MARK: - ASCredential Exchange

    static var credentialExchangeActivityType: String {
        if #available(iOS 26.0, *) {
            return ASCredentialExchangeActivity
        }
        return "ASCredentialExchangeActivity"
    }

    private func handleCredentialExchange(_ userActivity: NSUserActivity) -> Bool {
        guard let token = userActivity.userInfo?["ASCredentialImportToken"] as? UUID else {
            Logger.general.error("Skipping credential exchange activity without import token")
            Pixel.fire(pixel: .importHubCredentialExchangeTokenMissing, withAdditionalParameters: [PixelParameters.source: DataImportHubPixelConstants.unknownSource])
            return false
        }
        let activityIdentifier = token.uuidString

        guard shouldHandleActivity(withIdentifier: activityIdentifier) else {
            Logger.general.debug("Skipping duplicate credential exchange activity")
            return true
        }

        Task { [weak self] in
            await self?.importCredentials(token: token)
        }
        return true
    }

    private func shouldHandleActivity(withIdentifier identifier: String) -> Bool {
        guard lastHandledActivityIdentifier != identifier else {
            return false
        }

        lastHandledActivityIdentifier = identifier
        return true
    }

    private static func browserKitImportToken(from userActivity: NSUserActivity) -> UUID? {
        if #available(iOS 26.4, *) {
            return userActivity.userInfo?[BEBrowserDataImportManager.importTokenUserInfoKey] as? UUID
        }
        return nil
    }

    private func importCredentials(token: UUID) async {
        if let result = await credentialExchangeImportHandler.handleImport(token: token) {
            let sourceParameters = [PixelParameters.source: result.source]
            Pixel.fire(pixel: .importHubCredentialExchangeActivityReceived, withAdditionalParameters: sourceParameters)
            fireCredentialExchangeSimulatedCompletionIfNeeded(with: sourceParameters)

            if case .success(let passwordSummary)? = result.summary[.passwords] {
                var successParameters = sourceParameters
                successParameters[PixelParameters.savedCredentials] = AutofillPixelReporter.accountsBucketNameFrom(count: passwordSummary.successful)
                Pixel.fire(pixel: .importHubCredentialExchangeSuccess, withAdditionalParameters: successParameters)
            } else {
                Pixel.fire(pixel: .importHubCredentialExchangeSuccess, withAdditionalParameters: sourceParameters)
            }

            await MainActor.run {
                onImportResult(.success(result.summary))
            }
        } else {
            let sourceParameters = [PixelParameters.source: DataImportHubPixelConstants.unknownSource]
            let error = DataImportUserActivityHandlerError.credentialImportFailed

            Pixel.fire(pixel: .importHubCredentialExchangeActivityReceived, withAdditionalParameters: sourceParameters)
            fireCredentialExchangeSimulatedCompletionIfNeeded(with: sourceParameters)
            Pixel.fire(pixel: .importHubCredentialExchangeFailure, error: error, withAdditionalParameters: sourceParameters)

            await MainActor.run {
                onImportResult(.failure(error))
            }
        }
    }

    private func fireCredentialExchangeSimulatedCompletionIfNeeded(with parameters: [String: String]) {
        guard simulatedCompletionPersistor.consumeCredentialExchangeCompletionIfEligible() else {
            return
        }

        Pixel.fire(pixel: .importHubCredentialExchangeSimulatedCompletion, withAdditionalParameters: parameters)
    }
}

extension Notification.Name {
    static let didReceiveBrowserKitDataImportActivity = Notification.Name("didReceiveBrowserKitDataImportActivity")
}

extension CredentialExchangeImportHandler: CredentialExchangeImportHandling {}
