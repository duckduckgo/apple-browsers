//
//  DataBrokerProtectionStageDurationCalculator.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import PixelKit
import SecureStorage

public enum Stage: String {
    case start
    case emailGenerate = "email-generate"
    case captchaParse = "captcha-parse"
    case captchaSend = "captcha-send"
    case captchaSolve = "captcha-solve"
    case submit
    case emailReceive = "email-receive"
    case emailConfirm = "email-confirm"
    case emailConfirmHalted = "email-confirm-halted"
    case emailConfirmDecoupled = "email-confirm-decoupled"
    case validate
    case other
    case fillForm = "fill-form"
    case conditionFound = "condition-found"
    case conditionNotFound = "condition-not-found"
}

public protocol StageDurationCalculator {
    var attemptId: UUID { get }
    var isImmediateOperation: Bool { get }
    var tries: Int { get }

    func durationSinceLastStage() -> Double
    func durationSinceStartTime() -> Double
    func fireOptOutStart()
    func fireOptOutEmailGenerate()
    func fireOptOutCaptchaParse()
    func fireOptOutCaptchaSend()
    func fireOptOutCaptchaSolve()
    func fireOptOutSubmit()
    func fireOptOutFillForm()
    func fireOptOutEmailReceive()
    func fireOptOutEmailConfirm()
    func fireOptOutValidate()
    func fireOptOutSubmitSuccess(tries: Int)
    func fireOptOutFailure(tries: Int)
    func fireOptOutConditionFound()
    func fireOptOutConditionNotFound()
#if os(iOS)
    func fireScanStarted()
#endif
    func fireScanSuccess(matchesFound: Int)
    func fireScanFailed()
    func fireScanError(error: Error)
    func setStage(_ stage: Stage)
    func setEmailPattern(_ emailPattern: String?)
    func setLastActionId(_ actionID: String)
    func resetTries()
    func incrementTries()
}

extension StageDurationCalculator {
    public var isRetrying: Bool {
        tries != 1
    }
}

final class DataBrokerProtectionStageDurationCalculator: StageDurationCalculator {
    let isImmediateOperation: Bool
    let handler: EventMapping<DataBrokerProtectionSharedPixels>
    let attemptId: UUID
    let dataBroker: String
    let dataBrokerVersion: String
    let startTime: Date
    var lastStateTime: Date
    private(set) var actionID: String?
    private(set) var stage: Stage = .other
    private(set) var emailPattern: String?
    private(set) var tries = 1
    let vpnConnectionState: String
    let vpnBypassStatus: String

    init(attemptId: UUID = UUID(),
         startTime: Date = Date(),
         dataBroker: String,
         dataBrokerVersion: String,
         handler: EventMapping<DataBrokerProtectionSharedPixels>,
         isImmediateOperation: Bool = false,
         vpnConnectionState: String,
         vpnBypassStatus: String) {
        self.attemptId = attemptId
        self.startTime = startTime
        self.lastStateTime = startTime
        self.dataBroker = dataBroker
        self.dataBrokerVersion = dataBrokerVersion
        self.handler = handler
        self.isImmediateOperation = isImmediateOperation
        self.vpnConnectionState = vpnConnectionState
        self.vpnBypassStatus = vpnBypassStatus
    }

    /// Returned in milliseconds
    func durationSinceLastStage() -> Double {
        let now = Date()
        let durationSinceLastStage = now.timeIntervalSince(lastStateTime) * 1000
        self.lastStateTime = now

        return durationSinceLastStage.rounded(.towardZero)
    }

    /// Returned in milliseconds
    func durationSinceStartTime() -> Double {
        let now = Date()
        return (now.timeIntervalSince(startTime) * 1000).rounded(.towardZero)
    }

    func fireOptOutStart() {
        setStage(.start)
        handler.fire(.optOutStart(dataBroker: dataBroker, attemptId: attemptId))
    }

    func fireOptOutEmailGenerate() {
        handler.fire(.optOutEmailGenerate(dataBroker: dataBroker,
                                          attemptId: attemptId,
                                          duration: durationSinceLastStage(),
                                          dataBrokerVersion: dataBrokerVersion,
                                          tries: tries,
                                          actionId: actionID ?? ""))
    }

    func fireOptOutCaptchaParse() {
        handler.fire(.optOutCaptchaParse(dataBroker: dataBroker,
                                         attemptId: attemptId,
                                         duration: durationSinceLastStage(),
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
    }

    func fireOptOutCaptchaSend() {
        handler.fire(.optOutCaptchaSend(dataBroker: dataBroker,
                                        attemptId: attemptId,
                                        duration: durationSinceLastStage(),
                                        dataBrokerVersion: dataBrokerVersion,
                                        tries: tries,
                                        actionId: actionID ?? ""))
    }

    func fireOptOutCaptchaSolve() {
        handler.fire(.optOutCaptchaSolve(dataBroker: dataBroker,
                                         attemptId: attemptId,
                                         duration: durationSinceLastStage(),
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
    }

    func fireOptOutSubmit() {
        setStage(.submit)
        handler.fire(.optOutSubmit(dataBroker: dataBroker,
                                   attemptId: attemptId,
                                   duration: durationSinceLastStage(),
                                   dataBrokerVersion: dataBrokerVersion,
                                   tries: tries,
                                   actionId: actionID ?? ""))
    }

    func fireOptOutEmailReceive() {
        handler.fire(.optOutEmailReceive(dataBroker: dataBroker,
                                         attemptId: attemptId,
                                         duration: durationSinceLastStage(),
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
    }

    func fireOptOutEmailConfirm() {
        handler.fire(.optOutEmailConfirm(dataBroker: dataBroker,
                                         attemptId: attemptId,
                                         duration: durationSinceLastStage(),
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
    }

    func fireOptOutValidate() {
        setStage(.validate)
        handler.fire(.optOutValidate(dataBroker: dataBroker,
                                     attemptId: attemptId,
                                     duration: durationSinceLastStage(),
                                     dataBrokerVersion: dataBrokerVersion,
                                     tries: tries,
                                     actionId: actionID ?? ""))
    }

    func fireOptOutFillForm() {
        handler.fire(.optOutFillForm(dataBroker: dataBroker,
                                     attemptId: attemptId,
                                     duration: durationSinceLastStage(),
                                     dataBrokerVersion: dataBrokerVersion,
                                     tries: tries,
                                     actionId: actionID ?? ""))
    }

    func fireOptOutSubmitSuccess(tries: Int) {
        handler.fire(.optOutSubmitSuccess(dataBroker: dataBroker,
                                          attemptId: attemptId,
                                          duration: durationSinceStartTime(),
                                          tries: tries,
                                          emailPattern: emailPattern,
                                          vpnConnectionState: vpnConnectionState,
                                          vpnBypassStatus: vpnBypassStatus))
    }

    func fireOptOutFailure(tries: Int) {
        handler.fire(.optOutFailure(dataBroker: dataBroker,
                                    dataBrokerVersion: dataBrokerVersion,
                                    attemptId: attemptId,
                                    duration: durationSinceStartTime(),
                                    stage: stage.rawValue,
                                    tries: tries,
                                    emailPattern: emailPattern,
                                    actionID: actionID,
                                    vpnConnectionState: vpnConnectionState,
                                    vpnBypassStatus: vpnBypassStatus))
    }

    func fireOptOutConditionFound() {
        handler.fire(.optOutConditionFound(dataBroker: dataBroker,
                                           attemptId: attemptId,
                                           duration: durationSinceLastStage(),
                                           dataBrokerVersion: dataBrokerVersion,
                                           tries: tries,
                                           actionId: actionID ?? ""))
    }

    func fireOptOutConditionNotFound() {
        handler.fire(.optOutConditionNotFound(dataBroker: dataBroker,
                                              attemptId: attemptId,
                                              duration: durationSinceLastStage(),
                                              dataBrokerVersion: dataBrokerVersion,
                                              tries: tries,
                                              actionId: actionID ?? ""))
    }

#if os(iOS)
    func fireScanStarted() {
        handler.fire(.scanStarted(dataBroker: dataBroker))
    }
#endif

    func fireScanSuccess(matchesFound: Int) {
        handler.fire(.scanSuccess(dataBroker: dataBroker, matchesFound: matchesFound, duration: durationSinceStartTime(), tries: 1, isImmediateOperation: isImmediateOperation, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
    }

    func fireScanFailed() {
        handler.fire(.scanFailed(dataBroker: dataBroker, dataBrokerVersion: dataBrokerVersion, duration: durationSinceStartTime(), tries: 1, isImmediateOperation: isImmediateOperation, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
    }

    func fireScanError(error: Error) {
        var errorCategory: ErrorCategory = .unclassified

        if let dataBrokerProtectionError = error as? DataBrokerProtectionError {
            switch dataBrokerProtectionError {
            case .httpError(let httpCode):
                if httpCode < 500 {
                    if httpCode == 404 {
                        fireScanFailed()
                        return
                    } else {
                        errorCategory = .clientError(httpCode: httpCode)
                    }
                } else {
                    errorCategory = .serverError(httpCode: httpCode)
                }
            default:
                errorCategory = .validationError
            }
        } else if let databaseError = error as? SecureStorageError {
            errorCategory = .databaseError(domain: SecureStorageError.errorDomain, code: databaseError.errorCode)
        } else {
            if let nsError = error as NSError? {
                if nsError.domain == NSURLErrorDomain {
                    errorCategory = .networkError
                }
            }
        }

        handler.fire(
            .scanError(
                dataBroker: dataBroker,
                dataBrokerVersion: dataBrokerVersion,
                duration: durationSinceStartTime(),
                category: errorCategory.toString,
                details: error.localizedDescription,
                isImmediateOperation: isImmediateOperation,
                vpnConnectionState: vpnConnectionState,
                vpnBypassStatus: vpnBypassStatus
            )
        )
    }

    // Helper methods to set the stage that is about to run. This help us
    // identifying the stage so we can know which one was the one that failed.

    func setStage(_ stage: Stage) {
        lastStateTime = Date() // When we set a new stage we need to reset the lastStateTime so we count from there
        self.stage = stage
    }

    func setEmailPattern(_ emailPattern: String?) {
        self.emailPattern = emailPattern
    }

    func setLastActionId(_ actionID: String) {
        self.actionID = actionID
    }

    func resetTries() {
        self.tries = 1
    }

    func incrementTries() {
        self.tries += 1
    }
}
