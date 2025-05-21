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
    case validate
    case other
    case fillForm = "fill-form"
}

public protocol StageDurationCalculator {
    var attemptId: UUID { get }
    var isImmediateOperation: Bool { get }

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
#if os(iOS)
    func fireScanStarted()
#endif
    func fireScanSuccess(matchesFound: Int)
    func fireScanFailed()
    func fireScanError(error: Error)
    func setStage(_ stage: Stage)
    func setEmailPattern(_ emailPattern: String?)
    func setLastActionId(_ actionID: String)
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
        // This should never ever go to production and only exists for internal testing
        #if os(iOS)
        handler.fire(.optOutStart(dataBroker: dataBroker, attemptId: attemptId, deviceID: DataBrokerProtectionSettings.deviceIdentifier))
        #else
        handler.fire(.optOutStart(dataBroker: dataBroker, attemptId: attemptId))
        #endif
    }

    func fireOptOutEmailGenerate() {
        handler.fire(.optOutEmailGenerate(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutCaptchaParse() {
        handler.fire(.optOutCaptchaParse(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutCaptchaSend() {
        handler.fire(.optOutCaptchaSend(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutCaptchaSolve() {
        handler.fire(.optOutCaptchaSolve(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutSubmit() {
        setStage(.submit)
        handler.fire(.optOutSubmit(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutEmailReceive() {
        handler.fire(.optOutEmailReceive(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutEmailConfirm() {
        handler.fire(.optOutEmailConfirm(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutValidate() {
        setStage(.validate)
        handler.fire(.optOutValidate(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutSubmitSuccess(tries: Int) {
// This should never ever go to production and only exists for internal testing
#if os(iOS)
        handler.fire(.optOutSubmitSuccess(dataBroker: dataBroker,
                                          attemptId: attemptId,
                                          duration: durationSinceStartTime(),
                                          tries: tries,
                                          emailPattern: emailPattern,
                                          vpnConnectionState: vpnConnectionState,
                                          vpnBypassStatus: vpnBypassStatus,
                                          deviceID: DataBrokerProtectionSettings.deviceIdentifier))
#else
        handler.fire(.optOutSubmitSuccess(dataBroker: dataBroker,
                                          attemptId: attemptId,
                                          duration: durationSinceStartTime(),
                                          tries: tries,
                                          emailPattern: emailPattern,
                                          vpnConnectionState: vpnConnectionState,
                                          vpnBypassStatus: vpnBypassStatus))
#endif
    }

    func fireOptOutFillForm() {
        handler.fire(.optOutFillForm(dataBroker: dataBroker, attemptId: attemptId, duration: durationSinceLastStage()))
    }

    func fireOptOutFailure(tries: Int) {
// This should never ever go to production and only exists for internal testing
#if os(iOS)
        handler.fire(.optOutFailure(dataBroker: dataBroker,
                                    dataBrokerVersion: dataBrokerVersion,
                                    attemptId: attemptId,
                                    duration: durationSinceStartTime(),
                                    stage: stage.rawValue,
                                    tries: tries,
                                    emailPattern: emailPattern,
                                    actionID: actionID,
                                    vpnConnectionState: vpnConnectionState,
                                    vpnBypassStatus: vpnBypassStatus,
                                    deviceID: DataBrokerProtectionSettings.deviceIdentifier))
#else
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
#endif
    }

#if os(iOS)
    func fireScanStarted() {
    // This should never ever go to production and only exists for internal testing
        handler.fire(.scanStarted(dataBroker: dataBroker,
                                  deviceID: DataBrokerProtectionSettings.deviceIdentifier))
    }
#endif

    func fireScanSuccess(matchesFound: Int) {
// This should never ever go to production and only exists for internal testing
#if os(iOS)
        handler.fire(.scanSuccess(dataBroker: dataBroker,
                                  matchesFound: matchesFound,
                                  duration: durationSinceStartTime(),
                                  tries: 1,
                                  isImmediateOperation: isImmediateOperation,
                                  vpnConnectionState: vpnConnectionState,
                                  vpnBypassStatus: vpnBypassStatus,
                                  deviceID: DataBrokerProtectionSettings.deviceIdentifier))
#else
        handler.fire(.scanSuccess(dataBroker: dataBroker, matchesFound: matchesFound, duration: durationSinceStartTime(), tries: 1, isImmediateOperation: isImmediateOperation, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
#endif
    }

    func fireScanFailed() {
// This should never ever go to production and only exists for internal testing
#if os(iOS)
        handler.fire(.scanFailed(dataBroker: dataBroker,
                                 dataBrokerVersion: dataBrokerVersion,
                                 duration: durationSinceStartTime(),
                                 tries: 1,
                                 isImmediateOperation: isImmediateOperation,
                                 vpnConnectionState: vpnConnectionState,
                                 vpnBypassStatus: vpnBypassStatus,
                                 deviceID: DataBrokerProtectionSettings.deviceIdentifier))
#else
        handler.fire(.scanFailed(dataBroker: dataBroker, dataBrokerVersion: dataBrokerVersion, duration: durationSinceStartTime(), tries: 1, isImmediateOperation: isImmediateOperation, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
#endif
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

// This should never ever go to production and only exists for internal testing
#if os(iOS)
        handler.fire(
            .scanError(
                dataBroker: dataBroker,
                dataBrokerVersion: dataBrokerVersion,
                duration: durationSinceStartTime(),
                category: errorCategory.toString,
                details: error.localizedDescription,
                isImmediateOperation: isImmediateOperation,
                vpnConnectionState: vpnConnectionState,
                vpnBypassStatus: vpnBypassStatus,
                deviceID: DataBrokerProtectionSettings.deviceIdentifier
            )
        )
#else
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
#endif
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
}
