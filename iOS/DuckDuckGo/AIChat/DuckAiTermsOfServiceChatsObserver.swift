//
//  DuckAiTermsOfServiceChatsObserver.swift
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

import AIChat
import Combine
import Foundation
import os.log
import PixelKit

/// Chats on the device, or the web app's own record, mean the user accepted Duck.ai's Terms of Service
/// before, so once either shows it neither the native disclaimer nor the web app's card asks again.
final class DuckAiTermsOfServiceChatsObserver {

    private let storageHandler: DuckAiNativeObservableStorage
    private let store: DuckAiTermsOfServiceStore
    private let queue: DispatchQueue
    private let pixelFiring: (any PixelKitFiring)?
    private var cancellable: AnyCancellable?

    init?(storageHandler: DuckAiNativeStorageHandling?,
          feature: DuckAiNativeTermsOfServiceFeatureProviding,
          store: DuckAiTermsOfServiceStore = DuckAiTermsOfServiceStore(),
          queue: DispatchQueue = DispatchQueue(label: "com.duckduckgo.duckai.terms-of-service.chats", qos: .utility),
          pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        guard feature.isAvailable, let storageHandler = storageHandler as? DuckAiNativeObservableStorage else { return nil }
        self.storageHandler = storageHandler
        self.store = store
        self.queue = queue
        self.pixelFiring = pixelFiring
    }

    /// Off the main thread: the chats database opens in the background and its first read waits for it.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.adoptWebAcceptance()
            guard !(self.store.hasAccepted && self.isWebAcceptanceRecorded) else { return }
            self.cancellable = self.storageHandler.chatsPublisher()
                .first { !$0.isEmpty }
                .sink(receiveCompletion: { completion in
                    guard case .failure(let error) = completion else { return }
                    Logger.aiChat.error("[TermsOfService] Couldn't observe chats: \(error.localizedDescription, privacy: .public)")
                }, receiveValue: { [weak self] _ in
                    self?.recordAcceptance()
                })
        }
    }

    /// The web moves its records into native storage the first time Duck.ai loads, which can happen after launch.
    func refreshWebAcceptance() {
        queue.async { [weak self] in
            self?.adoptWebAcceptance()
        }
    }

    /// Acceptances made on the web before the app kept its own record exist only on the web's side.
    private func adoptWebAcceptance() {
        guard isWebAcceptanceRecorded, store.recordAcceptedOnWeb() else { return }
        Logger.aiChat.debug("[TermsOfService] Web acceptance adopted by the app")
        pixelFiring?.fire(DuckAiTermsOfServicePixel.acceptedFromWeb, frequency: .standard)
    }

    private func recordAcceptance() {
        store.recordAcceptedFromExistingChats()
        guard !isWebAcceptanceRecorded else { return }
        do {
            // The web app's own encoding: `JSON.stringify(true)`.
            try storageHandler.putEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey, value: "true")
            Logger.aiChat.debug("[TermsOfService] Chats exist: acceptance recorded for native and web")
        } catch {
            Logger.aiChat.error("[TermsOfService] Couldn't record web acceptance: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var isWebAcceptanceRecorded: Bool {
        let value = try? storageHandler.getEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey)
        return DuckAiNativeStorageConsent.isTermsOfServiceAccepted(value)
    }
}
