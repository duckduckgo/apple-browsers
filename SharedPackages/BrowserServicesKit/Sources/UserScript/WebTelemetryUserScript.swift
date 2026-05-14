//
//  WebTelemetryUserScript.swift
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

import Common
import Foundation
import WebKit

public protocol WebTelemetryUserScriptDelegate: AnyObject {
    @MainActor
    func webTelemetryUserScript(_ webTelemetryUserScript: WebTelemetryUserScript,
                                didDetectVideoPlayback payload: WebTelemetryUserScript.VideoPlaybackPayload,
                                in webView: WKWebView?)
}

public final class WebTelemetryUserScript: NSObject, Subfeature {

    public struct VideoPlaybackPayload: Codable, Equatable {
        public let userInteraction: Bool

        public init(userInteraction: Bool) {
            self.userInteraction = userInteraction
        }
    }

    public let messageOriginPolicy: MessageOriginPolicy = .all

    static public let featureName: String = "webTelemetry"
    public var featureName: String {
        Self.featureName
    }

    public weak var broker: UserScriptMessageBroker?
    public weak var delegate: WebTelemetryUserScriptDelegate?

    public override init() {
        super.init()
    }

    public enum MessageNames: String, CaseIterable {
        case videoPlayback = "video-playback"
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .videoPlayback:
            return { [weak self] in
                try await self?.videoPlayback(params: $0, original: $1)
            }
        default:
            return nil
        }
    }

    @MainActor
    private func videoPlayback(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload: VideoPlaybackPayload = DecodableHelper.decode(from: params) else {
            return nil
        }

        delegate?.webTelemetryUserScript(self, didDetectVideoPlayback: payload, in: original.webView)
        return nil
    }
}
