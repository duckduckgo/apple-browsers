//
//  AIChatHistoryCleaner.swift
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

import BrowserServicesKit
import Foundation
import Combine
import PixelKit
import PrivacyConfig
import WebKit
import UserScript
import os.log
import AIChat

protocol AIChatHistoryCleaning {
    /// Whether the option to clear Duck.ai chat history should be displayed to the user.
    var shouldDisplayCleanAIChatHistoryOption: Bool { get }

    /// Publisher that emits updates to the `shouldDisplayCleanAIChatHistoryOption` property.
    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> { get }

    /// Deletes all Duck.ai chat history.
    @MainActor func cleanAIChatHistory() async -> Result<Void, Error>
    /// What happened during the most recent clear (retries, timings), or `nil` if none ran.
    @MainActor var lastClearingReport: AIChatClearingReport? { get }

    /// All Duck.ai chats currently stored locally, decoded with their titles.
    /// Returns an empty array if native chat storage isn't available or a chat fails to decode.
    func allChats() -> [DuckAiChat]
}

extension AIChatHistoryCleaning {
    @MainActor var lastClearingReport: AIChatClearingReport? { nil }
}

final class AIChatHistoryCleaner: AIChatHistoryCleaning {

    private let featureFlagger: FeatureFlagger
    private let aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable
    let notificationCenter: NotificationCenter
    private var featureDiscoveryObserver: NSObjectProtocol?
    private let pixelKit: PixelKit?
    private let dataClearingPixelsReporter: DataClearingPixelsReporter
    private var historyCleaner: HistoryCleaning
    private let nativeStorageHandler: DuckAiNativeStorageHandling?

    @Published
    private var aiChatWasUsedBefore: Bool

    @Published
    var shouldDisplayCleanAIChatHistoryOption: Bool = false

    var shouldDisplayCleanAIChatHistoryOptionPublisher: AnyPublisher<Bool, Never> {
        $shouldDisplayCleanAIChatHistoryOption.eraseToAnyPublisher()
    }

    init(featureFlagger: FeatureFlagger,
         aiChatMenuConfiguration: AIChatMenuVisibilityConfigurable,
         featureDiscovery: FeatureDiscovery,
         notificationCenter: NotificationCenter = .default,
         pixelKit: PixelKit? = PixelKit.shared,
         privacyConfig: PrivacyConfigurationManaging,
         nativeStorageHandler: DuckAiNativeStorageHandling? = nil) {
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfiguration = aiChatMenuConfiguration
        self.notificationCenter = notificationCenter
        self.pixelKit = pixelKit
        self.nativeStorageHandler = nativeStorageHandler
        aiChatWasUsedBefore = featureDiscovery.wasUsedBefore(.aiChat)

        self.historyCleaner = HistoryCleaner(featureFlagger: featureFlagger,
                                            privacyConfig: privacyConfig,
                                            nativeStorageHandler: nativeStorageHandler,
                                            featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: featureFlagger),
                                            onBlobCleanup: AIChatLeftoverImagesPixelReporter(pixelFiring: pixelKit).report)
        self.dataClearingPixelsReporter = .init(pixelFiring: self.pixelKit)
        subscribeToChanges()
    }

    deinit {
        if let token = featureDiscoveryObserver {
            notificationCenter.removeObserver(token)
        }
    }

    @MainActor
    var lastClearingReport: AIChatClearingReport? { historyCleaner.lastClearingReport }

    /// Launches a headless web view to clear Duck.ai chat history with a C-S-S feature.
    @MainActor
    func cleanAIChatHistory() async -> Result<Void, Error> {
        let result = await historyCleaner.cleanAIChatHistory()

        switch result {
        case .success:
            pixelKit?.fire(AIChatPixel.aiChatDeleteHistorySuccessful, frequency: .dailyAndCount)
        case .failure(let error):
            Logger.aiChat.debug("Failed to clear Duck.ai chat history: \(error.localizedDescription)")
            pixelKit?.fire(AIChatPixel.aiChatDeleteHistoryFailed, frequency: .dailyAndCount)

            if let userScriptError = error as? UserScriptError {
                userScriptError.fireLoadJSFailedPixelIfNeeded()
            }
        }

        return result
    }

    func allChats() -> [DuckAiChat] {
        guard let nativeStorageHandler, let records = try? nativeStorageHandler.getAllChats() else { return [] }
        return records.compactMap { try? DuckAiChat.decode(from: $0.data).chat }
    }

    private func subscribeToChanges() {
        featureDiscoveryObserver = notificationCenter.addObserver(forName: .featureDiscoverySetWasUsedBefore, object: nil, queue: .main) { [weak self] notification in
            guard let featureRaw = notification.userInfo?["feature"] as? String,
                  featureRaw == WasUsedBeforeFeature.aiChat.rawValue else { return }
            self?.aiChatWasUsedBefore = true
        }

        $aiChatWasUsedBefore.combineLatest(aiChatMenuConfiguration.valuesChangedPublisher.prepend(()))
            .map { [weak self] wasUsed, _ in
                guard let self else { return false }
                return wasUsed && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature
            }
            .prepend(aiChatWasUsedBefore && aiChatMenuConfiguration.shouldDisplayAnyAIChatFeature)
            .removeDuplicates()
            .assign(to: &$shouldDisplayCleanAIChatHistoryOption)
    }
}

/// Reports the one-time removal of Duck.ai images WebKit left on disk, so we know when the cleanup can be dropped.
enum AIChatLeftoverImagesPixel: PixelKit.Event {

    case removed(filesRemoved: Int)
    case removalFailed(Error)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .removed: return "aichat_leftover-images_removed_macos"
        case .removalFailed: return "aichat_leftover-images_removal_failed_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .removed(let filesRemoved): return ["files_removed": Self.bucket(filesRemoved)]
        case .removalFailed: return nil
        }
    }

    var error: NSError? {
        switch self {
        case .removed: return nil
        case .removalFailed(let error): return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    static func bucket(_ count: Int) -> String {
        switch count {
        case 0: return "0"
        case 1...10: return "1-10"
        case 11...50: return "11-50"
        case 51...200: return "51-200"
        default: return "201+"
        }
    }
}

struct AIChatLeftoverImagesPixelReporter {

    let pixelFiring: (any PixelKitFiring)?

    func report(_ cleanup: AIChatBlobCleanupResult) {
        if let error = cleanup.error {
            pixelFiring?.fire(AIChatLeftoverImagesPixel.removalFailed(error), frequency: .dailyAndCount)
        }
        pixelFiring?.fire(AIChatLeftoverImagesPixel.removed(filesRemoved: cleanup.filesRemoved), frequency: .dailyAndCount)
    }
}
