//
//  AdClickAttributionDetection.swift
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
import Common
import os.log

public protocol AdClickAttributionDetectionDelegate: AnyObject {

    func attributionDetection(_ detection: AdClickAttributionDetection, didDetectVendor vendorHost: String)

}

public class AdClickAttributionDetection {

    enum State {

        case idle // Waiting for detection to start
        case detecting(String?) // Detection is in progress, parameter is vendor obtained from domain detection mechanism

    }

    private let attributionFeature: AdClickAttributing

    private var state = State.idle

    private let tld: TLD
    private let eventReporting: EventMapping<AdClickAttributionEvents>?
    private let errorReporting: EventMapping<AdClickAttributionDebugEvents>?

    public weak var delegate: AdClickAttributionDetectionDelegate?

    public init(feature: AdClickAttributing,
                tld: TLD,
                eventReporting: EventMapping<AdClickAttributionEvents>? = nil,
                errorReporting: EventMapping<AdClickAttributionDebugEvents>? = nil) {
        self.attributionFeature = feature
        self.tld = tld
        self.eventReporting = eventReporting
        self.errorReporting = errorReporting
    }

    // MARK: - Public API

    public func onStartNavigation(url: URL?) {
        guard attributionFeature.isEnabled,
              let url = url, attributionFeature.isMatchingAttributionFormat(url) else { return }

        Logger.contentBlocking.debug("Starting Attribution detection for \(url.host ?? "nil")")

        var vendorDomain: String?
        if attributionFeature.isDomainDetectionEnabled,
           let adDomainParameterName = attributionFeature.attributionDomainParameterName(for: url),
           let domainFromParameter = url.getParameter(named: adDomainParameterName),
           !domainFromParameter.isEmpty {

            if let eTLDp1 = tld.eTLDplus1(domainFromParameter)?.lowercased() {
                vendorDomain = eTLDp1
                delegate?.attributionDetection(self, didDetectVendor: eTLDp1)
            } else {
                errorReporting?.fire(.adAttributionDetectionInvalidDomainInParameter)
            }
        }

        if attributionFeature.isHeuristicDetectionEnabled {
            state = .detecting(vendorDomain)
        } else {
            fireDetectionPixel(serpBasedDomain: vendorDomain, heuristicBasedDomain: nil)
        }
    }

    public func on2XXResponse(url: URL?) {
        guard let host = url?.host else {
            return
        }

        heuristicDetection(forHost: host)
    }

    public func onDidFailNavigation() {
        Logger.contentBlocking.debug("Attribution detection has been cancelled")
        state = .idle
    }

    public func onDidFinishNavigation(url: URL?) {
        guard let host = url?.host else {
            return
        }

        heuristicDetection(forHost: host)
    }

    // MARK: - Private functionality

    private func heuristicDetection(forHost host: String) {
        guard case .detecting(let domainFromParameter) = state else {
            return
        }

        Logger.contentBlocking.debug("Attribution detected for \(host)")
        state = .idle

        let detectedDomain = tld.eTLDplus1(host)?.lowercased()
        if domainFromParameter == nil {
            if let vendorDomain = detectedDomain {
                delegate?.attributionDetection(self, didDetectVendor: vendorDomain)
            } else {
                errorReporting?.fire(.adAttributionDetectionHeuristicsDidNotMatchDomain)
            }
        }

        fireDetectionPixel(serpBasedDomain: domainFromParameter, heuristicBasedDomain: detectedDomain)
    }

    private func fireDetectionPixel(serpBasedDomain: String?, heuristicBasedDomain: String?) {

        let domainDetection: String

        if serpBasedDomain != nil && serpBasedDomain == heuristicBasedDomain {
            domainDetection = "matched"
        } else if serpBasedDomain != nil && !attributionFeature.isHeuristicDetectionEnabled {
            domainDetection = "serp_only"
        } else if serpBasedDomain != nil && serpBasedDomain != heuristicBasedDomain {
            domainDetection = "mismatch"
        } else if serpBasedDomain == nil && heuristicBasedDomain != nil {
            domainDetection = "heuristic_only"
        } else {
            domainDetection = "none"
        }

        let parameters = [AdClickAttributionEvents.Parameters.domainDetection: domainDetection,
                          AdClickAttributionEvents.Parameters.domainDetectionEnabled: attributionFeature.isDomainDetectionEnabled ? "1" : "0",
                          AdClickAttributionEvents.Parameters.heuristicDetectionEnabled: attributionFeature.isHeuristicDetectionEnabled ? "1" : "0"]
        eventReporting?.fire(.adAttributionDetected, parameters: parameters)
    }
}
