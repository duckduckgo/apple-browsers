//
//  MediaCaptureUserScript.swift
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
import UserScript
import WebKit

public enum MediaCaptureBridgeDecision: String, Equatable, Sendable {
    case allow
    case deny
    case bypass
}

@MainActor
public protocol MediaCaptureUserScriptDelegate: AnyObject {

    var isMediaCapturePermissionHandlingEnabled: Bool { get }

    func mediaCaptureUserScript(_ userScript: MediaCaptureUserScript,
                                requestPermissionFor permissionTypes: Set<SitePermissionType>,
                                requestID: String,
                                in frame: WKFrameInfo,
                                webView: WKWebView) async -> MediaCaptureBridgeDecision
}

/// Answers permission requests from the `sitePermissionsMediaCapture` content-scope feature, which delays
/// `getUserMedia` until the app has asked for site permission. Register it with the page-world
/// `ContentScopeUserScript` and inject `featureSettings` into that script's configuration.
public final class MediaCaptureUserScript: NSObject, Subfeature {

    /// The page-world content-scope feature this subfeature serves.
    public static let featureNameValue = "sitePermissionsMediaCapture"

    enum MessageKind: String {
        case requestPermission
    }

    static let capabilityToken = UUID().uuidString + UUID().uuidString

    public let featureName = MediaCaptureUserScript.featureNameValue
    public let messageOriginPolicy: MessageOriginPolicy = .all
    public weak var broker: UserScriptMessageBroker?

    /// Settings for the page-world feature. Without them the feature leaves `getUserMedia` untouched.
    public var featureSettings: [String: Any] {
        ["capability": Self.capabilityToken]
    }

    @MainActor public weak var delegate: MediaCaptureUserScriptDelegate?

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard MessageKind(rawValue: methodName) == .requestPermission else { return nil }
        return { [weak self] params, message in
            guard let self else { return nil }
            let body = params as? [String: Any] ?? [:]
            return await SitePermissionsBridgeReply(["decision": self.decision(for: body, message: message).rawValue])
        }
    }

    @MainActor
    func decision(for body: [String: Any], message: WKScriptMessage) async -> MediaCaptureBridgeDecision {
        guard body["capability"] as? String == Self.capabilityToken,
              let delegate else {
            return .deny
        }

        // A retained document must return to WebKit's behavior on rollback, including contexts
        // the custom flow does not support. Check the flag before applying its eligibility rules.
        guard delegate.isMediaCapturePermissionHandlingEnabled else {
            return .bypass
        }

        guard body["isEligible"] as? Bool == true,
              let requestID = body["requestID"] as? String,
              Self.isValidRequestID(requestID),
              let requestsVideo = body["video"] as? Bool,
              let requestsAudio = body["audio"] as? Bool,
              requestsVideo || requestsAudio,
              let webView = message.webView,
              !message.frameInfo.securityOrigin.host.isEmpty else {
            return .deny
        }

        var permissionTypes = Set<SitePermissionType>()
        if requestsVideo {
            permissionTypes.insert(.camera)
        }
        if requestsAudio {
            permissionTypes.insert(.microphone)
        }

        return await delegate.mediaCaptureUserScript(self,
                                                     requestPermissionFor: permissionTypes,
                                                     requestID: requestID,
                                                     in: message.frameInfo,
                                                     webView: webView)
    }

    static func isValidRequestID(_ requestID: String) -> Bool {
        let components = requestID.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0].utf8.count == 32,
              components[0].allSatisfy({ $0.isHexDigit }),
              let sequence = UInt64(components[1]),
              sequence > 0 else {
            return false
        }
        return true
    }
}
