//
//  GPCRequestFactory.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public struct GPCRequestFactory {

    public init() { }

    public struct Constants {
        public static let secGPCHeader = "Sec-GPC"
    }

    private func gpcHeadersEnabled(config: PrivacyConfiguration) -> [String] {
        let settings = config.settings(for: .gpc)

        guard let enabledSites = settings["gpcHeaderEnabledSites"] as? [String] else {
            return []
        }

        return enabledSites
    }

    public func isGPCEnabled(url: URL,
                             config: PrivacyConfiguration) -> Bool {
        let enabledSites = gpcHeadersEnabled(config: config)

        if enabledSites.contains(where: { gpcHost in url.isPart(ofDomain: gpcHost) }) {
            // Check if url is on exception list
            // Since headers are only enabled for a small numbers of sites
            // perform this check here for efficiency
            return config.isFeature(.gpc, enabledForDomain: url.host)
        }

        return false
    }

    /// Returns the header fields to be applied for GPC.
    /// If no header should be applied, returns an empty dictionary.
    public func headersForGPC(basedOn incomingRequest: URLRequest,
                              config: PrivacyConfiguration,
                              gpcEnabled: Bool) -> [String: String] {
        return computedGPCHeaders(for: incomingRequest, config: config, gpcEnabled: gpcEnabled)
    }

    /// Returns a modified URLRequest with the GPC header added or removed if needed.
    /// Returns nil if no modifications are necessary.
    public func requestForGPC(basedOn incomingRequest: URLRequest,
                              config: PrivacyConfiguration,
                              gpcEnabled: Bool) -> URLRequest? {
        let computedHeaders = computedGPCHeaders(for: incomingRequest, config: config, gpcEnabled: gpcEnabled)
        let currentHeader = incomingRequest.value(forHTTPHeaderField: Constants.secGPCHeader)

        // If computed headers are empty and the header is currently present, remove it.
        if computedHeaders.isEmpty {
            if currentHeader != nil {
                var request = incomingRequest
                request.setValue(nil, forHTTPHeaderField: Constants.secGPCHeader)
                return request
            }
            return nil
        } else {
            // Otherwise, if the header isn't already present, add it.
            if currentHeader == nil {
                var request = incomingRequest
                request.addValue("1", forHTTPHeaderField: Constants.secGPCHeader)
                return request
            }
        }
        return nil
    }

    private func computedGPCHeaders(for incomingRequest: URLRequest,
                                    config: PrivacyConfiguration,
                                    gpcEnabled: Bool) -> [String: String] {
        /*
         For now, the GPC header is only applied to sites known to be honoring GPC (nytimes.com, washingtonpost.com),
         while the DOM signal is available to all websites.
         This is done to avoid an issue with back navigation when adding the header (e.g. with 't.co').
         */
        guard let url = incomingRequest.url, isGPCEnabled(url: url, config: config) else {
            return [:]
        }
        if config.isEnabled(featureKey: .gpc) && gpcEnabled {
            return [Constants.secGPCHeader: "1"]
        }
        return [:]
    }

}
