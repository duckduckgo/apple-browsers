//
//  ChromeWebStoreUserScript.swift
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

import AppKitExtensions
import Combine
import Common
import UserScript
import WebExtensions
import WebKit

/// The isolated-world C-S-S "chromeWebstorePatching" messaging contract.
@available(macOS 15.4, *)
final class ChromeWebStoreUserScript: NSObject, Subfeature {
    static let featureNameValue = "chromeWebstorePatching"
    let featureName = featureNameValue
    let messageOriginPolicy: MessageOriginPolicy = .only(rules: [.exact(hostname: ChromeWebStoreURL.host)])
    weak var broker: UserScriptMessageBroker?
    private let isEnabled: Bool
    private let serviceProvider: @MainActor () -> ChromeWebStoreManaging?

    private let notificationCenter: NotificationCenter
    private var changeCancellable: AnyCancellable?
    @MainActor private weak var webView: WKWebView?

    init(serviceProvider: @escaping @MainActor () -> ChromeWebStoreManaging?,
         notificationCenter: NotificationCenter = .default,
         buildType: ApplicationBuildType = StandardApplicationBuildType()) {
        self.isEnabled = buildType.isSparkleBuild
        self.serviceProvider = serviceProvider
        self.notificationCenter = notificationCenter
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
        guard isEnabled else { return }
        changeCancellable = notificationCenter.publisher(for: .chromeWebStoreExtensionChanged)
            .sink { [weak self] notification in
                guard let extensionId = notification.userInfo?["extensionId"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.extensionChanged(extensionId)
                }
            }
    }

    @MainActor
    private func extensionChanged(_ extensionId: String) {
        // A tab may have navigated away since its last validated store request.
        guard isEnabled, ChromeWebStoreURL.isValidExtensionID(extensionId),
              let webView, let url = webView.url,
              url.scheme == "https", url.host == ChromeWebStoreURL.host,
              url.port == nil || url.port == 443 else { return }
        broker?.push(method: Method.extensionChanged.rawValue, params: ["extensionId": extensionId], for: self, into: webView)
    }

    struct ExtensionRequest: Decodable {
        let extensionId: String
    }

    struct InstallRequest: Decodable {
        let extensionId: String
        let crxUrl: URL

        /// Replaces the placeholder `prodversion=9999.0.0.0` version provided by the user script
        /// with the version defined by the app.
        private(set) lazy var versionedCrxUrl: URL = crxUrl.addingOrReplacing(ChromeWebStoreURL.prodversionQueryItem)
    }

    struct InitialSetupResponse: Encodable {
        let enabled: Bool
    }

    struct StatusResponse: Encodable {
        let status: ChromeWebStoreStatus
    }

    struct OperationResponse: Encodable {
        let success: Bool
    }

    enum Method: String {
        case initialSetup, getExtensionStatus, installExtension, removeExtension, extensionChanged
    }

    func handler(forMethodNamed methodName: String) -> Handler? {
        guard let method = Method(rawValue: methodName) else { return nil }
        return { [weak self] params, message in
            guard let self else { throw ChromeWebStoreError.unavailable }
            return try await self.handle(method, params: params, message: message)
        }
    }

    @MainActor
    private func handle(_ method: Method, params: Any, message: WKScriptMessage) async throws -> Encodable? {
        // The broker's hostname rule alone does not exclude HTTP, subframes, or stale documents.
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == ChromeWebStoreURL.host,
              origin.port == 0 || origin.port == 443,
              let pageURL = message.webView?.url,
              pageURL.scheme == "https", pageURL.host == ChromeWebStoreURL.host,
              pageURL.port == nil || pageURL.port == 443 else { throw ChromeWebStoreError.invalidRequest }

        // Setup is build-level and does not require an extension ID or a service.
        if method == .initialSetup {
            return InitialSetupResponse(enabled: isEnabled)
        }

        guard isEnabled else { throw ChromeWebStoreError.unavailable }

        guard let request: ExtensionRequest = DecodableHelper.decode(from: params),
              ChromeWebStoreURL.isValidExtensionID(request.extensionId) else { throw ChromeWebStoreError.invalidRequest }

        // Retain only a weak reference, and only after validating the main frame.
        webView = message.webView
        let service = serviceProvider()
        switch method {
        case .getExtensionStatus:
            return StatusResponse(status: service?.status(for: request.extensionId) ?? .unknown)
        case .installExtension:
            guard var request: InstallRequest = DecodableHelper.decode(from: params),
                  ChromeWebStoreURL.isValidDownloadURL(request.versionedCrxUrl, for: request.extensionId) else {
                throw ChromeWebStoreError.invalidRequest
            }
            let success = await service?.install(identifier: request.extensionId, downloadURL: request.versionedCrxUrl) ?? false
            return OperationResponse(success: success)
        case .removeExtension:
            let success = await service?.remove(identifier: request.extensionId) ?? false
            return OperationResponse(success: success)
        case .initialSetup, .extensionChanged:
            return nil
        }
    }
}
