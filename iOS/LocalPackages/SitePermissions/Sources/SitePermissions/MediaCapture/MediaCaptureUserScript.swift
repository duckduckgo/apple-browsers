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

    func mediaCaptureUserScript(_ userScript: MediaCaptureUserScript,
                                requestPermissionFor permissionTypes: Set<SitePermissionType>,
                                requestID: String,
                                in frame: WKFrameInfo,
                                webView: WKWebView) async -> MediaCaptureBridgeDecision
}

public final class MediaCaptureUserScript: NSObject, UserScript {

    private static let messageName = "sitePermissionsMediaCapture"
    static let capabilityToken = UUID().uuidString + UUID().uuidString

    public static var bundle: Bundle { .module }

    public lazy var source: String = {
        do {
            return try Self.loadJS("mediaCapture",
                                   from: Self.bundle,
                                   withReplacements: ["${CAPABILITY_TOKEN}": Self.capabilityToken])
        } catch {
            fatalError("Failed to load JS for MediaCaptureUserScript: \(error.localizedDescription)")
        }
    }()

    public let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public let forMainFrameOnly = false
    public let messageNames = [MediaCaptureUserScript.messageName]
    public var requiresRunInPageContentWorld: Bool { true }

    @MainActor public weak var delegate: MediaCaptureUserScriptDelegate?

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        // This script uses the reply-handler overload on every supported iOS version.
    }

    @MainActor
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              body["capability"] as? String == Self.capabilityToken,
              let requestID = body["requestID"] as? String,
              Self.isValidRequestID(requestID),
              let requestsVideo = body["video"] as? Bool,
              let requestsAudio = body["audio"] as? Bool,
              requestsVideo || requestsAudio,
              let webView = message.webView,
              !message.frameInfo.securityOrigin.host.isEmpty else {
            return (["decision": MediaCaptureBridgeDecision.deny.rawValue], nil)
        }

        var permissionTypes = Set<SitePermissionType>()
        if requestsVideo {
            permissionTypes.insert(.camera)
        }
        if requestsAudio {
            permissionTypes.insert(.microphone)
        }

        let decision = await delegate?.mediaCaptureUserScript(self,
                                                               requestPermissionFor: permissionTypes,
                                                               requestID: requestID,
                                                               in: message.frameInfo,
                                                               webView: webView) ?? .deny
        return (["decision": decision.rawValue], nil)
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

extension MediaCaptureUserScript: WKScriptMessageHandlerWithReply {}
