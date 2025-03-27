//
//  LinkProtection.swift
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

import WebKit
import Common

public struct LinkProtection {

    private let linkCleaner: LinkCleaner
    private let ampExtractor: AMPCanonicalExtractor

    private var mainFrameUrl: URL?

    public init(privacyManager: PrivacyConfigurationManaging,
                contentBlockingManager: CompiledRuleListsSource,
                errorReporting: EventMapping<AMPProtectionDebugEvents>) {
        linkCleaner = LinkCleaner(privacyManager: privacyManager)
        ampExtractor = AMPCanonicalExtractor(linkCleaner: linkCleaner,
                                             privacyManager: privacyManager,
                                             contentBlockingManager: contentBlockingManager,
                                             errorReporting: errorReporting)
    }

    private func makeNewRequest(changingUrl url: URL, inRequest request: URLRequest) -> URLRequest {
        var newRequest = request
        newRequest.url = url
        return newRequest
    }

    public mutating func setMainFrameUrl(_ url: URL?) {
        mainFrameUrl = url
    }

    public func getCleanURLRequest(from urlRequest: URLRequest,
                                   onStartExtracting: () -> Void,
                                   onFinishExtracting: @escaping () -> Void,
                                   completion: @escaping (URLRequest) -> Void) {
        getCleanURL(from: urlRequest.url!, onStartExtracting: onStartExtracting, onFinishExtracting: onFinishExtracting) { newUrl in
            let newRequest = makeNewRequest(changingUrl: newUrl, inRequest: urlRequest)
            completion(newRequest)
        }
    }

    public func getCleanURL(from url: URL,
                            onStartExtracting: () -> Void,
                            onFinishExtracting: @escaping () -> Void,
                            completion: @escaping (URL) -> Void) {
        var urlToLoad = url
        if let cleanURL = linkCleaner.cleanTrackingParameters(initiator: nil, url: urlToLoad) {
            urlToLoad = cleanURL
        }

        if let cleanURL = linkCleaner.extractCanonicalFromAMPLink(initiator: nil, destination: urlToLoad) {
            completion(cleanURL)
        } else if ampExtractor.urlContainsAMPKeyword(urlToLoad) {
            onStartExtracting()
            ampExtractor.getCanonicalURL(initiator: nil, url: urlToLoad) { canonical in
                onFinishExtracting()
                if let canonical = canonical {
                    completion(canonical)
                } else {
                    completion(urlToLoad)
                }
            }
        } else {
            completion(urlToLoad)
        }
    }

    @MainActor
    public func getCleanURL(from url: URL, onStartExtracting: () -> Void, onFinishExtracting: @escaping () -> Void) async -> URL {
        await withCheckedContinuation { continuation in
            getCleanURL(from: url, onStartExtracting: onStartExtracting, onFinishExtracting: onFinishExtracting) { url in
                continuation.resume(returning: url)
            }
        }
    }

    public func requestTrackingLinkRewrite(initiatingURL: URL?,
                                           destinationRequest: URLRequest,
                                           onStartExtracting: () -> Void,
                                           onFinishExtracting: @escaping () -> Void,
                                           onLinkRewrite: @escaping (URLRequest) -> Void,
                                           policyDecisionHandler: @escaping (Bool) -> Void) -> Bool {
        let destinationURL = destinationRequest.url
        if let mainFrameUrl = mainFrameUrl, destinationURL != mainFrameUrl {
            // If mainFrameUrl is set and is different from destinationURL we will assume this is a redirect
            // We do not rewrite redirects due to breakage concerns
            return false
        }

        var didRewriteLink = false
        if let newURL = linkCleaner.extractCanonicalFromAMPLink(initiator: initiatingURL, destination: destinationURL) {
            policyDecisionHandler(false)
            onLinkRewrite(makeNewRequest(changingUrl: newURL, inRequest: destinationRequest))
            didRewriteLink = true
        } else if ampExtractor.urlContainsAMPKeyword(destinationURL) {
            onStartExtracting()
            ampExtractor.getCanonicalURL(initiator: initiatingURL, url: destinationURL) { canonical in
                onFinishExtracting()
                guard let canonical = canonical, canonical != destinationURL else {
                    policyDecisionHandler(true)
                    return
                }

                policyDecisionHandler(false)
                onLinkRewrite(makeNewRequest(changingUrl: canonical, inRequest: destinationRequest))
            }
            didRewriteLink = true
        } else if let newURL = linkCleaner.cleanTrackingParameters(initiator: initiatingURL, url: destinationURL) {
            if newURL != destinationURL {
                policyDecisionHandler(false)
                onLinkRewrite(makeNewRequest(changingUrl: newURL, inRequest: destinationRequest))
                didRewriteLink = true
            }
        }

        return didRewriteLink
    }

    public func requestTrackingLinkRewrite(initiatingURL: URL?,
                                           navigationAction: WKNavigationAction,
                                           onStartExtracting: () -> Void,
                                           onFinishExtracting: @escaping () -> Void,
                                           onLinkRewrite: @escaping (URLRequest, WKNavigationAction) -> Void,
                                           policyDecisionHandler: @escaping (WKNavigationActionPolicy) -> Void) -> Bool {
        requestTrackingLinkRewrite(initiatingURL: initiatingURL,
                                   destinationRequest: navigationAction.request,
                                   onStartExtracting: onStartExtracting,
                                   onFinishExtracting: onFinishExtracting,
                                   onLinkRewrite: { onLinkRewrite($0, navigationAction) },
                                   policyDecisionHandler: { policyDecisionHandler($0 ? .allow : .cancel) })
    }

    @MainActor
    public func requestTrackingLinkRewrite(initiatingURL: URL?,
                                           destinationRequest: URLRequest,
                                           onStartExtracting: () -> Void,
                                           onFinishExtracting: @escaping () -> Void,
                                           onLinkRewrite: @escaping (URLRequest) -> Void) async -> Bool? {
        await withCheckedContinuation { continuation in
            let didRewriteLink = requestTrackingLinkRewrite(initiatingURL: initiatingURL,
                                                            destinationRequest: destinationRequest,
                                                            onStartExtracting: onStartExtracting,
                                                            onFinishExtracting: onFinishExtracting,
                                                            onLinkRewrite: onLinkRewrite) { navigationActionPolicy in
                continuation.resume(returning: navigationActionPolicy)
            }

            if !didRewriteLink {
                continuation.resume(returning: nil)
            }
        }
    }

    public func cancelOngoingExtraction() { ampExtractor.cancelOngoingExtraction() }

    public var lastAMPURLString: String? { linkCleaner.lastAMPURLString }
    public var urlParametersRemoved: Bool { linkCleaner.urlParametersRemoved }

}
