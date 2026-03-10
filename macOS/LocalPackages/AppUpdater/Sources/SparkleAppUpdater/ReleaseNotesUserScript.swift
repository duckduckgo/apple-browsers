//
//  ReleaseNotesUserScript.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppUpdaterShared
import Combine
import Common
import Foundation
import Persistence
import PixelKit
import UserScript
import WebKit

/// Sparkle-specific implementation of release notes user script.
///
/// Handles communication between the release notes web page and the update controller,
/// providing update status, progress, and triggering update actions.
public final class ReleaseNotesUserScript: NSObject, Subfeature {

    private let updateController: any SparkleUpdateControlling
    private let pixelFiring: PixelFiring?
    private let keyValueStore: ThrowingKeyValueStoring
    private let releaseNotesURL: URL

    public var messageOriginPolicy: MessageOriginPolicy = .only(rules: [.exact(hostname: "release-notes")])
    public let featureName: String = "release-notes"
    public weak var broker: UserScriptMessageBroker?
    weak var webView: WKWebView? {
        didSet {
            onUpdate()
        }
    }
    private var cancellables = Set<AnyCancellable>()
    private var emptyNotesPixelWorkItem: DispatchWorkItem?

    // MARK: - MessageNames
    enum MessageNames: String, CaseIterable {
        case initialSetup
        case reportPageException
        case reportInitException
        case browserRestart
        case retryUpdate
        case retryFetchReleaseNotes
    }

    public init(updateController: any SparkleUpdateControlling,
                pixelFiring: PixelFiring?,
                keyValueStore: ThrowingKeyValueStoring,
                releaseNotesURL: URL) {
        self.updateController = updateController
        self.pixelFiring = pixelFiring
        self.keyValueStore = keyValueStore
        self.releaseNotesURL = releaseNotesURL
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    private lazy var methodHandlers: [MessageNames: Handler] = [
        .initialSetup: initialSetup,
        .reportPageException: reportPageException,
        .reportInitException: reportInitException,
        .browserRestart: browserRestart,
        .retryUpdate: retryUpdate,
        .retryFetchReleaseNotes: retryFetchReleaseNotes,
    ]

    @MainActor
    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard let messageName = MessageNames(rawValue: methodName) else { return nil }
        return methodHandlers[messageName]
    }

    deinit {
        emptyNotesPixelWorkItem?.cancel()
    }

    public func onUpdate() {
        guard AppVersion.runType != .uiTests else { return }

        emptyNotesPixelWorkItem?.cancel()
        emptyNotesPixelWorkItem = nil

        guard let webView, webView.url == releaseNotesURL else { return }

        let values = ReleaseNotesValues(from: updateController, keyValueStore: keyValueStore)
        broker?.push(method: "onUpdate", params: values, for: self, into: webView)

        if values.status == ReleaseNotesValues.Status.loadingError.rawValue {
            let workItem = DispatchWorkItem { [weak self] in
                self?.pixelFiring?.fire(UpdateFlowPixels.releaseNotesLoadingError, frequency: .dailyAndCount)
            }
            emptyNotesPixelWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

}

extension ReleaseNotesUserScript {

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        // Initialize the page right after sending the initial setup result
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.onUpdate()
        }

#if DEBUG
        let env = "development"
#else
        let env = "production"
#endif

        return InitialSetupResult(env: env, locale: Locale.current.languageCode ?? "en")
    }

    @MainActor
    private func retryUpdate(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        DispatchQueue.main.async { [weak self] in
            self?.updateController.checkForUpdateSkippingRollout()
        }
        return nil
    }

    @MainActor
    private func retryFetchReleaseNotes(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        DispatchQueue.main.async { [weak self] in
            self?.updateController.checkForUpdateSkippingRollout()
        }
        return nil
    }

    struct InitialSetupResult: Encodable {
        let env: String
        let locale: String
    }

    @MainActor
    private func reportPageException(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return nil
    }

    @MainActor
    private func reportInitException(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return nil
    }

    private func browserRestart(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        DispatchQueue.main.async { [weak self] in
            self?.updateController.runUpdate()
        }
        return nil
    }

    struct Result: Encodable {}

}
