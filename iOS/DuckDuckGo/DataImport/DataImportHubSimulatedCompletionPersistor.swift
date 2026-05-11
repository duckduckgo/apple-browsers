//
//  DataImportHubSimulatedCompletionPersistor.swift
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
import Core
import Persistence

struct DataImportHubSimulatedCompletionPersistor {

    enum Key: String {
        case safariFileExportStartDate = "data-import.hub-safari-file-export-start-date"
        case safariFileExportEntryPoint = "data-import.hub-safari-file-export-entry-point"
        case credentialExchangeInstructionsShownDate = "data-import.hub-credential-exchange-instructions-shown-date"
    }

    private static let completionEligibilityWindow: TimeInterval = 7 * 24 * 60 * 60

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func setSafariFileFlowStart(entryPoint: DataImportViewModel.ImportScreen, now: Date = Date()) {
        guard let entryPointValue = entryPoint.importHubEntryPoint else {
            return
        }

        try? keyValueStore.set(now, forKey: Key.safariFileExportStartDate.rawValue)
        try? keyValueStore.set(entryPointValue, forKey: Key.safariFileExportEntryPoint.rawValue)
    }

    func consumeSafariFileCompletionParametersIfEligible(now: Date = Date()) -> [String: String]? {
        guard let startDate = try? keyValueStore.object(forKey: Key.safariFileExportStartDate.rawValue) as? Date,
              let entryPoint = try? keyValueStore.object(forKey: Key.safariFileExportEntryPoint.rawValue) as? String else {
            return nil
        }

        guard isWithinSimulationWindow(startDate: startDate, now: now) else {
            return nil
        }

        clearSafariFileFlow()
        return [PixelParameters.entryPoint: entryPoint]
    }

    func consumeExpiredSafariFileFailureParameters(now: Date = Date()) -> [String: String]? {
        guard let startDate = try? keyValueStore.object(forKey: Key.safariFileExportStartDate.rawValue) as? Date,
              let entryPoint = try? keyValueStore.object(forKey: Key.safariFileExportEntryPoint.rawValue) as? String else {
            return nil
        }

        guard !isWithinSimulationWindow(startDate: startDate, now: now) else {
            return nil
        }

        clearSafariFileFlow()
        return [PixelParameters.entryPoint: entryPoint]
    }

    func setCredentialExchangeInstructionsShownDate(now: Date = Date()) {
        try? keyValueStore.set(now, forKey: Key.credentialExchangeInstructionsShownDate.rawValue)
    }

    func consumeCredentialExchangeCompletionIfEligible(now: Date = Date()) -> Bool {
        guard let startDate = try? keyValueStore.object(forKey: Key.credentialExchangeInstructionsShownDate.rawValue) as? Date else {
            return false
        }

        guard isWithinSimulationWindow(startDate: startDate, now: now) else {
            return false
        }

        clearCredentialExchangeFlow()
        return true
    }

    func consumeExpiredCredentialExchangeFailure(now: Date = Date()) -> Bool {
        guard let startDate = try? keyValueStore.object(forKey: Key.credentialExchangeInstructionsShownDate.rawValue) as? Date else {
            return false
        }

        guard !isWithinSimulationWindow(startDate: startDate, now: now) else {
            return false
        }

        clearCredentialExchangeFlow()
        return true
    }

    func fireExpiredFailurePixelsIfNeeded(now: Date = Date()) {
        if let parameters = consumeExpiredSafariFileFailureParameters(now: now) {
            Pixel.fire(pixel: .importHubSafariFileSimulatedFailure, withAdditionalParameters: parameters)
        }

        if consumeExpiredCredentialExchangeFailure(now: now) {
            Pixel.fire(pixel: .importHubCredentialExchangeSimulatedFailure,
                       withAdditionalParameters: [PixelParameters.source: DataImportHubPixelConstants.unknownSource])
        }
    }

    private func isWithinSimulationWindow(startDate: Date, now: Date) -> Bool {
        now.timeIntervalSince(startDate) <= Self.completionEligibilityWindow
    }

    private func clearSafariFileFlow() {
        try? keyValueStore.removeObject(forKey: Key.safariFileExportStartDate.rawValue)
        try? keyValueStore.removeObject(forKey: Key.safariFileExportEntryPoint.rawValue)
    }

    private func clearCredentialExchangeFlow() {
        try? keyValueStore.removeObject(forKey: Key.credentialExchangeInstructionsShownDate.rawValue)
    }
}
