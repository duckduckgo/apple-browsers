//
//  ReferrerTrimming.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import WebKit
import TrackerRadarKit
import Common

public class ReferrerTrimming {

    struct Constants {
        static let headerName = "Referer"
        static let policyName = "Referrer-Policy"
    }

    public enum TrimmingState {
        case idle
        case navigating(destination: URL)
    }

    private let privacyManager: PrivacyConfigurationManaging
    private var privacyConfig: PrivacyConfiguration { privacyManager.privacyConfig }

    private let contentBlockingManager: CompiledRuleListsSource

    private var state: TrimmingState = .idle

    private var tld: TLD

    public init(privacyManager: PrivacyConfigurationManaging,
                contentBlockingManager: CompiledRuleListsSource,
                tld: TLD) {
        self.privacyManager = privacyManager
        self.contentBlockingManager = contentBlockingManager
        self.tld = tld
    }

    public func onBeginNavigation(to destination: URL?) {
        guard let destination = destination else {
            return
        }

        state = .navigating(destination: destination)
    }

    public func onFinishNavigation() {
        state = .idle
    }

    public func onFailedNavigation() {
        state = .idle
    }

    func getTrimmedReferrer(originUrl: URL, destUrl: URL, referrerUrl: URL?, trackerData: TrackerData) -> String? {
        func isSameEntity(a: Entity?, b: Entity?) -> Bool {
            if a == nil && b == nil {
                return !originUrl.isThirdParty(to: destUrl, tld: tld)
            }

            return a?.displayName == b?.displayName
        }

        guard let originHost = originUrl.host else {
            return nil
        }
        guard let destHost = destUrl.host else {
            return nil
        }

        guard privacyConfig.isFeature(.referrer, enabledForDomain: originHost),
              privacyConfig.isFeature(.referrer, enabledForDomain: destHost) else {
            return nil
        }
        guard let referrerUrl = referrerUrl,
              let referrerScheme = referrerUrl.scheme,
              let referrerHost = referrerUrl.host else {
            return nil
        }

        let referEntity = trackerData.findEntity(forHost: originHost)
        let destEntity = trackerData.findEntity(forHost: destHost)

        var newReferrer: String?
        if !isSameEntity(a: referEntity, b: destEntity) {
            newReferrer = "\(referrerScheme)://\(referrerHost)/"
        }

        if let tracker = trackerData.findTracker(forUrl: destUrl.absoluteString),
           tracker.defaultAction == .block,
           !isSameEntity(a: referEntity, b: destEntity) {
            newReferrer = "\(referrerScheme)://\(referrerHost)/"
        }

        if newReferrer == referrerUrl.absoluteString {
            return nil
        }

        return newReferrer
    }

    public func trimReferrer(forNavigation navigationAction: WKNavigationAction, originUrl: URL?) -> URLRequest? {
        return trimReferrer(for: navigationAction.request, originUrl: originUrl)
    }

    public func trimReferrer(for request: URLRequest, originUrl: URL?) -> URLRequest? {
        guard let originUrl = originUrl else {
            return nil
        }
        guard let destUrl = request.url else {
            return nil
        }
        switch state {
        case let .navigating(trimmingUrl):
            if trimmingUrl != destUrl {
                // If mainFrameUrl is set and is different from destinationURL we will assume this is a redirect
                // We do not rewrite redirects due to breakage concerns
                return nil
            }
        case .idle:
            onBeginNavigation(to: destUrl)
        }

        guard let trackerData = contentBlockingManager.currentMainRules?.trackerData else {
            return nil
        }

        guard let referrerHeader = request.value(forHTTPHeaderField: Constants.headerName) else {
            return nil
        }

        if let newReferrer = getTrimmedReferrer(originUrl: originUrl,
                                                destUrl: destUrl,
                                                referrerUrl: URL(string: referrerHeader) ?? nil,
                                                trackerData: trackerData) {
            var request = request
            request.setValue(newReferrer, forHTTPHeaderField: Constants.headerName)
            return request
        }

        return nil
    }
}
