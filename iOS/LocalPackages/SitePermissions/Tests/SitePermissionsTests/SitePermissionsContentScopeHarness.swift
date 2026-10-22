//
//  SitePermissionsContentScopeHarness.swift
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

import BrowserServicesKit
import Foundation
import PrivacyConfigTestsUtils
import UserScript
import WebKit
@testable import SitePermissions

/// Builds the bundled content-scope scripts with the site permission features configured the way the app does.
@MainActor
struct SitePermissionsContentScope {

    /// JavaScript that is true once the geolocation shim has installed in the evaluated frame.
    static let geolocationShimInstalled = "typeof navigator.duckduckgo?.messageHandlers?.geolocationWatchResult === \"function\""

    private struct BaseConfiguration: CustomisedPrivacyConfigurationJSONGenerating {
        let privacyConfiguration: Data? = #"{"version":1,"features":{},"unprotectedTemporary":[]}"#.data(using: .utf8)
    }

    let pageScript: ContentScopeUserScript
    let isolatedScript: ContentScopeUserScript

    /// - Parameter includesGeolocationPolicy: Whether the isolated world receives the policy feature's settings.
    init(geolocation: GeolocationUserScript? = nil,
         mediaCapture: MediaCaptureUserScript? = nil,
         includesGeolocationPolicy: Bool = true) throws {
        var pageFeatures = [String: [String: Any]]()
        var isolatedFeatures = [String: [String: Any]]()
        if let geolocation {
            pageFeatures[GeolocationUserScript.featureNameValue] = geolocation.featureSettings
            if includesGeolocationPolicy {
                isolatedFeatures[GeolocationUserScript.policyFeatureName] = GeolocationUserScript.policyFeatureSettings
            }
        }
        if let mediaCapture {
            pageFeatures[MediaCaptureUserScript.featureNameValue] = mediaCapture.featureSettings
        }

        let manager = MockPrivacyConfigurationManager()
        let properties = ContentScopeProperties(gpcEnabled: false,
                                                sessionKey: "site-permissions-tests",
                                                messageSecret: "site-permissions-tests",
                                                featureToggles: .allTogglesOn)
        pageScript = try ContentScopeUserScript(manager,
                                                properties: properties,
                                                scriptContext: .contentScope(),
                                                allowedNonisolatedFeatures: [GeolocationUserScript.featureNameValue,
                                                                             MediaCaptureUserScript.featureNameValue],
                                                privacyConfigurationJSONGenerator: ContentScopeNativeFeaturesConfigurationJSONGenerator(
                                                    base: BaseConfiguration(),
                                                    features: pageFeatures))
        isolatedScript = try ContentScopeUserScript(manager,
                                                    properties: properties,
                                                    scriptContext: .contentScopeIsolated,
                                                    privacyConfigurationJSONGenerator: ContentScopeNativeFeaturesConfigurationJSONGenerator(
                                                        base: BaseConfiguration(),
                                                        features: isolatedFeatures))
        geolocation.map { pageScript.registerSubfeature(delegate: $0) }
        mediaCapture.map { pageScript.registerSubfeature(delegate: $0) }
    }

    /// Adds both scripts after any scripts already in `userContentController`.
    ///
    /// - Parameter pageMessageHandler: Replaces the page-world content-scope handler, for tests that fake native replies.
    func install(in userContentController: WKUserContentController,
                 pageMessageHandler: (any WKScriptMessageHandlerWithReply)? = nil) {
        userContentController.addUserScript(WKUserScript(source: isolatedScript.source,
                                                         injectionTime: .atDocumentStart,
                                                         forMainFrameOnly: false,
                                                         in: .defaultClient))
        userContentController.addUserScript(WKUserScript(source: pageScript.source,
                                                         injectionTime: .atDocumentStart,
                                                         forMainFrameOnly: false,
                                                         in: .page))
        userContentController.addScriptMessageHandler(pageMessageHandler ?? pageScript,
                                                      contentWorld: .page,
                                                      name: pageScript.messageNames[0])
        userContentController.addScriptMessageHandler(isolatedScript,
                                                      contentWorld: .defaultClient,
                                                      name: isolatedScript.messageNames[0])
    }

    /// Wraps `result` in the response envelope the content-scope messaging layer expects for `request`.
    static func response(to request: [String: Any], result: [String: Any]) -> String? {
        let response: [String: Any] = [
            "context": request["context"] ?? "",
            "featureName": request["featureName"] ?? "",
            "id": request["id"] ?? "",
            "result": result
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension GeolocationUserScript {

    /// Sends a page message through the subfeature handler, as the content-scope broker does.
    ///
    /// The message body names the operation in `kind`; the reply is decoded from the encoded result.
    @MainActor
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let kind = body["kind"] as? String,
              let handler = handler(forMethodNamed: kind) else {
            return (nil, "Unknown geolocation method")
        }
        return await SitePermissionsBridgeReply.decodedReply(from: handler, params: body, message: message)
    }
}

extension MediaCaptureUserScript {

    /// Sends a page message through the subfeature handler, as the content-scope broker does.
    @MainActor
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let handler = handler(forMethodNamed: "requestPermission") else {
            return (nil, "Unknown media capture method")
        }
        return await SitePermissionsBridgeReply.decodedReply(from: handler, params: message.body, message: message)
    }
}

extension SitePermissionsBridgeReply {

    @MainActor
    static func decodedReply(from handler: Subfeature.Handler, params: Any, message: WKScriptMessage) async -> (Any?, String?) {
        do {
            guard let reply = try await handler(params, message) else { return (nil, "No reply") }
            let data = try JSONEncoder().encode(AnyEncodable(reply))
            return (try JSONSerialization.jsonObject(with: data), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private struct AnyEncodable: Encodable {
        let value: Encodable

        init(_ value: Encodable) {
            self.value = value
        }

        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }
}
