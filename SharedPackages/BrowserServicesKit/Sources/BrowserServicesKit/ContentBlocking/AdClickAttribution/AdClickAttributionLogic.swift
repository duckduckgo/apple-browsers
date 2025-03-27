//
//  AdClickAttributionLogic.swift
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
import ContentBlocking
import Common
import os.log

public protocol AdClickAttributionLogicDelegate: AnyObject {

    func attributionLogic(_ logic: AdClickAttributionLogic,
                          didRequestRuleApplication rules: ContentBlockerRulesManager.Rules?,
                          forVendor vendor: String?)
}

public class AdClickAttributionLogic {

    public enum State: CustomDebugStringConvertible {

        case noAttribution
        case preparingAttribution(vendor: String, session: SessionInfo, requestID: UUID, completionBlocks: [(() -> Void)])
        case activeAttribution(vendor: String, session: SessionInfo, rules: ContentBlockerRulesManager.Rules)

        var isActiveAttribution: Bool {
            if case .activeAttribution = self { return true }
            return false
        }

        public var debugDescription: String {
            switch self {
            case .noAttribution:
                return "noAttribution"
            case .preparingAttribution(let vendor, _, let requestID, let completionBlocks):
                return "preparingAttribution(\(vendor), \(requestID), blocks: \(completionBlocks.count))"
            case .activeAttribution(let vendor, _, _):
                return "activeAttribution(\(vendor))"
            }
        }
    }

    public struct SessionInfo {
        // Start of the attribution
        public let attributionStartedAt: Date
        // Present when we leave webpage associated with the attribution
        public let leftAttributionContextAt: Date?

        init(start: Date = Date(), leftContextAt: Date? = nil) {
            attributionStartedAt = start
            leftAttributionContextAt = leftContextAt
        }
    }

    private let featureConfig: AdClickAttributing
    private let rulesProvider: AdClickAttributionRulesProviding
    private let tld: TLD
    private let eventReporting: EventMapping<AdClickAttributionEvents>?
    private let errorReporting: EventMapping<AdClickAttributionDebugEvents>?
    private lazy var counter: AdClickAttributionCounter = AdClickAttributionCounter(onSendRequest: { count in
        self.eventReporting?.fire(.adAttributionPageLoads, parameters: [AdClickAttributionEvents.Parameters.count: String(count)])
    })

    public var debugID: String {
        ObjectIdentifier(self).debugDescription
    }

    public private(set) var state = State.noAttribution {
        willSet {
            Logger.contentBlocking.debug("<\(self.debugID)> will set state from \(self.state.debugDescription) to \(newValue.debugDescription)")
        }
    }

    private var registerFirstActivity = false

    private var attributionTimeout: DispatchWorkItem?

    public weak var delegate: AdClickAttributionLogicDelegate?

    public init(featureConfig: AdClickAttributing,
                rulesProvider: AdClickAttributionRulesProviding,
                tld: TLD,
                eventReporting: EventMapping<AdClickAttributionEvents>? = nil,
                errorReporting: EventMapping<AdClickAttributionDebugEvents>? = nil) {
        self.featureConfig = featureConfig
        self.rulesProvider = rulesProvider
        self.tld = tld
        self.eventReporting = eventReporting
        self.errorReporting = errorReporting
    }

    public func applyInheritedAttribution(state: State?) {
        guard let state = state else { return }

        if case .noAttribution = self.state {} else {
            errorReporting?.fire(.adAttributionLogicUnexpectedStateOnInheritedAttribution)
            assert(NSClassFromString("XCTest") != nil /* allow when running tests */, "unexpected initial attribution state \(self.state)")
        }

        switch state {
        case .noAttribution:
            self.state = state
        case .preparingAttribution(let vendor, let info, _, _):
            requestAttribution(forVendor: vendor,
                               attributionStartedAt: info.attributionStartedAt)
        case .activeAttribution(_, let sessionInfo, _):
            if sessionInfo.leftAttributionContextAt == nil {
                self.state = state
                applyRules()
            }
        }
    }

    public func onRulesChanged(latestRules: [ContentBlockerRulesManager.Rules]) {
        Logger.contentBlocking.debug("<\(self.debugID)> Responding to RulesChanged event")
        switch state {
        case .noAttribution:
            applyRules()
        case .preparingAttribution(let vendor, _, _, let completionBlocks):
            requestAttribution(forVendor: vendor, completionBlocks: completionBlocks)
        case .activeAttribution(let vendor, _, _):
            requestAttribution(forVendor: vendor)
        }
    }

    public func reapplyCurrentRules() {
        applyRules()
    }

    public func onBackForwardNavigation(mainFrameURL: URL?) {
        guard case .activeAttribution(let vendor, let session, let rules) = state,
        let host = mainFrameURL?.host,
        let currentETLDp1 = tld.eTLDplus1(host) else {
            return
        }

        if vendor == currentETLDp1 {
            if session.leftAttributionContextAt != nil {
                state = .activeAttribution(vendor: vendor,
                                           session: SessionInfo(start: session.attributionStartedAt),
                                           rules: rules)
            }
        } else if session.leftAttributionContextAt == nil {
            state = .activeAttribution(vendor: vendor,
                                       session: SessionInfo(start: session.attributionStartedAt,
                                                           leftContextAt: Date()),
                                       rules: rules)
        }
    }

    public func onProvisionalNavigation(completion: @escaping () -> Void, currentTime: Date = Date()) {
        switch state {
        case .noAttribution:
            completion()
        case .preparingAttribution(let vendor, let session, let id, var completionBlocks):
            Logger.contentBlocking.debug("<\(self.debugID)> Suspending provisional navigation...")
            completionBlocks.append(completion)
            state = .preparingAttribution(vendor: vendor,
                                          session: session,
                                          requestID: id,
                                          completionBlocks: completionBlocks)
        case .activeAttribution(_, let session, _):
            if currentTime.timeIntervalSince(session.attributionStartedAt) >= featureConfig.totalExpiration {
                Logger.contentBlocking.debug("<\(self.debugID)> Attribution has expired - total expiration")
                disableAttribution()
            } else if let leftAttributionContextAt = session.leftAttributionContextAt,
                      currentTime.timeIntervalSince(leftAttributionContextAt) >= featureConfig.navigationExpiration {
                Logger.contentBlocking.debug("<\(self.debugID)> Attribution has expired - navigational expiration")
                disableAttribution()
            }
            completion()
        }
    }

    @MainActor
    public func onProvisionalNavigation() async {
        await withCheckedContinuation { continuation in
            onProvisionalNavigation {
                continuation.resume()
            }
        }
    }

    public func onDidFinishNavigation(host: String?, currentTime: Date = Date()) {
        guard case .activeAttribution(let vendor, let session, let rules) = state else {
            return
        }

        if tld.eTLDplus1(host) == vendor {
            counter.onAttributionActive()
        }

        if currentTime.timeIntervalSince(session.attributionStartedAt) >= featureConfig.totalExpiration {
            Logger.contentBlocking.debug("<\(self.debugID)> Attribution has expired - total expiration")
            disableAttribution()
            return
        }

        if let leftAttributionContextAt = session.leftAttributionContextAt {
           if currentTime.timeIntervalSince(leftAttributionContextAt) >= featureConfig.navigationExpiration {
               Logger.contentBlocking.debug("<\(self.debugID)> Attribution has expired - navigational expiration")
               disableAttribution()
           } else if tld.eTLDplus1(host) == vendor {
               Logger.contentBlocking.debug("<\(self.debugID)> Refreshing navigational duration for attribution")
               state = .activeAttribution(vendor: vendor,
                                          session: SessionInfo(start: session.attributionStartedAt),
                                          rules: rules)
           }
        } else if tld.eTLDplus1(host) != vendor {
            Logger.contentBlocking.debug("<\(self.debugID)> Leaving attribution context")
            state = .activeAttribution(vendor: vendor,
                                       session: SessionInfo(start: session.attributionStartedAt,
                                                            leftContextAt: Date()),
                                       rules: rules)
        }
    }

    public func onRequestDetected(request: DetectedRequest) {
        guard registerFirstActivity,
            BlockingState.allowed(reason: .adClickAttribution) == request.state else { return }

        eventReporting?.fire(.adAttributionActive)
        registerFirstActivity = false
    }

    private func disableAttribution() {
        assert(state.isActiveAttribution, "unexpected attribution state")
        state = .noAttribution
        applyRules()
    }

    private func onAttributedRulesCompiled(forVendor vendor: String, requestID: UUID, _ rules: ContentBlockerRulesManager.Rules) {
        guard case .preparingAttribution(let expectedVendor, let session, let id, let completionBlocks) = state else {
            Logger.contentBlocking.error("<\(self.debugID)> Attributed Rules received unexpectedly")
            errorReporting?.fire(.adAttributionLogicUnexpectedStateOnRulesCompiled)
            return
        }
        guard id == requestID else {
            Logger.contentBlocking.debug("<\(self.debugID)> Ignoring outdated rules")
            return
        }
        guard expectedVendor == vendor else {
            Logger.contentBlocking.debug("<\(self.debugID)> Attributed Rules received for wrong vendor")
            errorReporting?.fire(.adAttributionLogicWrongVendorOnSuccessfulCompilation)
            return
        }
        state = .activeAttribution(vendor: vendor, session: session, rules: rules)
        applyRules()
        Logger.contentBlocking.debug("<\(self.debugID)> Resuming provisional navigation for \(completionBlocks.count, privacy: .public) requests")
        for completion in completionBlocks {
            completion()
        }
    }

    private func onAttributedRulesCompilationFailed(forVendor vendor: String, requestID: UUID) {
        guard case .preparingAttribution(let expectedVendor, _, let id, let completionBlocks) = state else {
            Logger.contentBlocking.error("<\(self.debugID)> Attributed Rules compilation failed")
            errorReporting?.fire(.adAttributionLogicUnexpectedStateOnRulesCompilationFailed)
            return
        }
        guard id == requestID else {
            Logger.contentBlocking.debug("<\(self.debugID)> Ignoring outdated rules")
            return
        }
        guard expectedVendor == vendor else {
            errorReporting?.fire(.adAttributionLogicWrongVendorOnFailedCompilation)
            return
        }
        state = .noAttribution

        applyRules()
        Logger.contentBlocking.debug("<\(self.debugID)> Resuming provisional navigation for \(completionBlocks.count, privacy: .public) requests")
        for completion in completionBlocks {
            completion()
        }
    }

    private func applyRules() {
        if case .activeAttribution(let vendor, _, let rules) = state {
            delegate?.attributionLogic(self, didRequestRuleApplication: rules, forVendor: vendor)
        } else {
            delegate?.attributionLogic(self, didRequestRuleApplication: rulesProvider.globalAttributionRules, forVendor: nil)
        }
    }

    /// Request attribution when we detect it is needed
    private func requestAttribution(forVendor vendorHost: String, attributionStartedAt: Date = Date(), completionBlocks: [() -> Void] = []) {
        Logger.contentBlocking.debug("<\(self.debugID)> Requesting attribution and new rules for \(vendorHost)")
        let requestID = UUID()
        state = .preparingAttribution(vendor: vendorHost,
                                      session: SessionInfo(start: attributionStartedAt),
                                      requestID: requestID,
                                      completionBlocks: completionBlocks)

        scheduleTimeout(forVendor: vendorHost, requestID: requestID)
        rulesProvider.requestAttribution(forVendor: vendorHost) { [weak self] rules in
            self?.cancelTimeout()
            if let rules = rules {
                self?.onAttributedRulesCompiled(forVendor: vendorHost, requestID: requestID, rules)
            } else {
                self?.onAttributedRulesCompilationFailed(forVendor: vendorHost, requestID: requestID)
            }
        }
    }

    private func scheduleTimeout(forVendor vendor: String, requestID: UUID) {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.onAttributedRulesCompilationFailed(forVendor: vendor, requestID: requestID)
            self?.attributionTimeout = nil

            self?.errorReporting?.fire(.adAttributionLogicRequestingAttributionTimedOut)
        }
        self.attributionTimeout?.cancel()
        self.attributionTimeout = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0,
                                      execute: timeoutWorkItem)
    }

    private func cancelTimeout() {
        attributionTimeout?.cancel()
        attributionTimeout = nil
    }

    /// Respond to new requests for attribution
    private func onAttributionRequested(forVendor vendorHost: String) {

        switch state {
        case .noAttribution:
            Logger.contentBlocking.debug("<\(self.debugID)> Preparing attribution for \(vendorHost)")
                requestAttribution(forVendor: vendorHost)
        case .preparingAttribution(let expectedVendor, _, _, let completionBlocks):
            if expectedVendor != vendorHost {
                Logger.contentBlocking.debug("<\(self.debugID)> Preparing attributon for \(vendorHost) replacing pending one for \(expectedVendor)")
                requestAttribution(forVendor: vendorHost, completionBlocks: completionBlocks)
            } else {
                Logger.contentBlocking.debug("<\(self.debugID)> Preparing attribution for \(vendorHost) already in progress")
            }
        case .activeAttribution(let expectedVendor, _, _):
            if expectedVendor != vendorHost {
                Logger.contentBlocking.debug("<\(self.debugID)> Preparing attributon for \(vendorHost) replacing \(expectedVendor)")
                requestAttribution(forVendor: vendorHost)
            } else {
                Logger.contentBlocking.debug("<\(self.debugID)> Attribution for \(vendorHost) already active")
            }
        }
    }

}

extension AdClickAttributionLogic: AdClickAttributionDetectionDelegate {

    public func attributionDetection(_ detection: AdClickAttributionDetection,
                                     didDetectVendor vendorHost: String) {
        Logger.contentBlocking.debug("<\(self.debugID)> Detected attribution requests for \(vendorHost)")
        onAttributionRequested(forVendor: vendorHost)
        registerFirstActivity = true
    }

}
