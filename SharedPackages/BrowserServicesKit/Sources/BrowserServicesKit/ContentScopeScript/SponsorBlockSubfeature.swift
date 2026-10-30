//
//  SponsorBlockSubfeature.swift
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
import os.log
import UserScript
import WebKit

/// Subfeature that handles messages from the content-scope-scripts `sponsorBlock` feature.
///
/// Register it with the isolated `ContentScopeUserScript`, since `sponsorBlock` runs in the isolated world.
public final class SponsorBlockSubfeature: NSObject, Subfeature {

    /// The feature name used for message routing. Must match the JavaScript feature name.
    public static let featureNameValue = "sponsorBlock"

    public let messageOriginPolicy: MessageOriginPolicy = .only(rules: [
        .exact(hostname: "youtube.com"),
        .exact(hostname: "www.youtube.com"),
        .exact(hostname: "m.youtube.com"),
        // Duck Player embeds the video in a youtube-nocookie.com iframe.
        .exact(hostname: "youtube-nocookie.com"),
        .exact(hostname: "www.youtube-nocookie.com")
    ])

    public let featureName: String = SponsorBlockSubfeature.featureNameValue

    public weak var broker: UserScriptMessageBroker?

    private let segmentsProvider: SponsorBlockSegmentsProvider

    public init(segmentsProvider: SponsorBlockSegmentsProvider = .shared) {
        self.segmentsProvider = segmentsProvider
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    /// Message names that this subfeature handles.
    enum MessageNames: String, CaseIterable {
        case log
        case getSegments
    }

    struct GetSegmentsResponse: Encodable {
        let segments: [SponsorBlockSegmentsProvider.Segment]
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .log:
            return { [weak self] in try await self?.handleLog(params: $0, original: $1) }
        case .getSegments:
            return { [weak self] in try await self?.handleGetSegments(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func handleLog(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let message = (params as? [String: Any])?["message"] as? String ?? String(describing: params)
        Logger.sponsorBlock.debug("[\(original.frameInfo.securityOrigin.host)] \(message)")
        return nil
    }

    private func handleGetSegments(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        do {
            let query = try SponsorBlockSegmentsProvider.Query(params: params)
            let segments = try await segmentsProvider.segments(for: query)
            return GetSegmentsResponse(segments: segments)
        } catch {
            Logger.sponsorBlock.error("getSegments failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
