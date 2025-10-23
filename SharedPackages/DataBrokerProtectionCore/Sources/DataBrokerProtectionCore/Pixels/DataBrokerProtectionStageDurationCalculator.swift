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
    func fireScanNoResults()
    func fireScanError(error: Error)
    func setStage(_ stage: Stage)
    func setEmailPattern(_ emailPattern: String?)
    func setLastAction(_ action: Action)
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
    let dataBrokerURL: String
    let dataBrokerVersion: String
    let startTime: Date
    var lastStateTime: Date
    private(set) var actionID: String?
    private(set) var actionType: String?
    private(set) var stage: Stage = .other
    private(set) var emailPattern: String?
    private(set) var tries = 1
    let vpnConnectionState: String
    let vpnBypassStatus: String
    weak var wideEventRecorder: OptOutSubmissionWideEventRecording?

    init(attemptId: UUID = UUID(),
         startTime: Date = Date(),
         dataBrokerURL: String,
         dataBrokerVersion: String,
         handler: EventMapping<DataBrokerProtectionSharedPixels>,
         isImmediateOperation: Bool = false,
         vpnConnectionState: String,
         vpnBypassStatus: String) {
        self.attemptId = attemptId
        self.startTime = startTime
        self.lastStateTime = startTime
        self.dataBrokerURL = dataBrokerURL
        self.dataBrokerVersion = dataBrokerVersion
        self.handler = handler
        self.isImmediateOperation = isImmediateOperation
        self.vpnConnectionState = vpnConnectionState
        self.vpnBypassStatus = vpnBypassStatus
    }

    func attachWideEventRecorder(_ recorder: OptOutSubmissionWideEventRecording?) {
        self.wideEventRecorder = recorder
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
        handler.fire(.optOutStart(dataBroker: dataBrokerURL, attemptId: attemptId))
        wideEventRecorder?.recordStage(.start,
                                       duration: nil,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutEmailGenerate() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutEmailGenerate(dataBroker: dataBrokerURL,
                                          attemptId: attemptId,
                                          duration: duration,
                                          dataBrokerVersion: dataBrokerVersion,
                                          tries: tries,
                                          actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.emailGenerate,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutCaptchaParse() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutCaptchaParse(dataBroker: dataBrokerURL,
                                         attemptId: attemptId,
                                         duration: duration,
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.captchaParse,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutCaptchaSend() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutCaptchaSend(dataBroker: dataBrokerURL,
                                        attemptId: attemptId,
                                        duration: duration,
                                        dataBrokerVersion: dataBrokerVersion,
                                        tries: tries,
                                        actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.captchaSend,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutCaptchaSolve() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutCaptchaSolve(dataBroker: dataBrokerURL,
                                         attemptId: attemptId,
                                         duration: duration,
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.captchaSolve,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutSubmit() {
        setStage(.submit)
        let duration = durationSinceLastStage()
        handler.fire(.optOutSubmit(dataBroker: dataBrokerURL,
                                   attemptId: attemptId,
                                   duration: duration,
                                   dataBrokerVersion: dataBrokerVersion,
                                   tries: tries,
                                   actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.submit,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutEmailReceive() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutEmailReceive(dataBroker: dataBrokerURL,
                                         attemptId: attemptId,
                                         duration: duration,
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.emailReceive,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutEmailConfirm() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutEmailConfirm(dataBroker: dataBrokerURL,
                                         attemptId: attemptId,
                                         duration: duration,
                                         dataBrokerVersion: dataBrokerVersion,
                                         tries: tries,
                                         actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.emailConfirm,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutValidate() {
        setStage(.validate)
        let duration = durationSinceLastStage()
        handler.fire(.optOutValidate(dataBroker: dataBrokerURL,
                                     attemptId: attemptId,
                                     duration: duration,
                                     dataBrokerVersion: dataBrokerVersion,
                                     tries: tries,
                                     actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.validate,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutFillForm() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutFillForm(dataBroker: dataBrokerURL,
                                     attemptId: attemptId,
                                     duration: duration,
                                     dataBrokerVersion: dataBrokerVersion,
                                     tries: tries,
                                     actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.fillForm,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutSubmitSuccess(tries: Int) {
        let now = Date()
        let totalDuration = durationSinceStartTime()
        handler.fire(.optOutSubmitSuccess(dataBroker: dataBrokerURL,
                                          attemptId: attemptId,
                                          duration: totalDuration,
                                          tries: tries,
                                          emailPattern: emailPattern,
                                          vpnConnectionState: vpnConnectionState,
                                          vpnBypassStatus: vpnBypassStatus))
        wideEventRecorder?.markSubmissionCompleted(at: now,
                                                   tries: tries,
                                                   actionID: actionID)
        wideEventRecorder?.complete(status: .success)
    }

    func fireOptOutFailure(tries: Int) {
        handler.fire(.optOutFailure(dataBroker: dataBrokerURL,
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
        let duration = durationSinceLastStage()
        handler.fire(.optOutConditionFound(dataBroker: dataBrokerURL,
                                           attemptId: attemptId,
                                           duration: duration,
                                           dataBrokerVersion: dataBrokerVersion,
                                           tries: tries,
                                           actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.conditionFound,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

    func fireOptOutConditionNotFound() {
        let duration = durationSinceLastStage()
        handler.fire(.optOutConditionNotFound(dataBroker: dataBrokerURL,
                                              attemptId: attemptId,
                                              duration: duration,
                                              dataBrokerVersion: dataBrokerVersion,
                                              tries: tries,
                                              actionId: actionID ?? ""))
        wideEventRecorder?.recordStage(.conditionNotFound,
                                       duration: duration,
                                       tries: tries,
                                       actionID: actionID)
    }

#if os(iOS)
    func fireScanStarted() {
        handler.fire(.scanStarted(dataBroker: dataBrokerURL))
    }
#endif

    func fireScanSuccess(matchesFound: Int) {
        handler.fire(.scanSuccess(dataBroker: dataBrokerURL, matchesFound: matchesFound, duration: durationSinceStartTime(), tries: 1, isImmediateOperation: isImmediateOperation, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
    }

    func fireScanNoResults() {
        handler.fire(.scanNoResults(dataBroker: dataBrokerURL, dataBrokerVersion: dataBrokerVersion, duration: durationSinceStartTime(), tries: 1, isImmediateOperation: isImmediateOperation, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
    }

    func fireScanError(error: Error) {
        var errorCategory: ErrorCategory = .unclassified

        if let dataBrokerProtectionError = error as? DataBrokerProtectionError {
            switch dataBrokerProtectionError {
            case .httpError(let httpCode):
                if httpCode < 500 {
                    if httpCode == 404 {
                        fireScanNoResults()
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
                dataBroker: dataBrokerURL,
                dataBrokerVersion: dataBrokerVersion,
                duration: durationSinceStartTime(),
                category: errorCategory.toString,
                details: error.localizedDescription,
                isImmediateOperation: isImmediateOperation,
                vpnConnectionState: vpnConnectionState,
                vpnBypassStatus: vpnBypassStatus,
                actionId: actionID ?? "unknown",
                actionType: actionType ?? "unknown"
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

    func setLastAction(_ action: Action) {
        self.actionID = action.id
        self.actionType = action.actionType.rawValue
    }

    func resetTries() {
        self.tries = 1
    }

    func incrementTries() {
        self.tries += 1
    }
}
