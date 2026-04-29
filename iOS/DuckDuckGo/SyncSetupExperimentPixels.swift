//
//  SyncSetupExperimentPixels.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Foundation
import PixelExperimentKit
import PixelKit
import PrivacyConfig

/// Instrumentation facade for the iOS Sync Setup Simplification A/B experiment.
///
protocol SyncSetupExperimentPixelFiring {

    // Primary metrics
    func fireSignupDirect()
    func fireSignupConnect()
    func fireLogin()

    // Guardrail / secondary metrics
    func fireSyncDisabled()
    func fireSyncDisabledAndDeleted()

    func fireBarcodeScreenShown()
    func fireBarcodeScannerSuccess()
    func fireBarcodeScannerFailed()
    func fireBarcodeCodeCopied()

    func fireManualCodeEntryScreenShown()
    func fireManualCodeEnteredSuccess()
    func fireManualCodeEnteredFailed()

    func fireSetupEndedAbandoned()
    func fireSetupEndedSuccessful()

    func fireDeepLinkFlowStarted()
    func fireDeepLinkFlowSuccess()
    func fireDeepLinkFlowAbandoned()
    func fireDeepLinkTimeout()
}

final class SyncSetupExperimentPixelReporter: SyncSetupExperimentPixelFiring {

    private let subfeatureID: SubfeatureID = SyncSubfeature.simplifiedSyncSetupExperiment.rawValue

    private enum Metric {
        static let signupDirect = "signup_direct"
        static let signupConnect = "signup_connect"
        static let login = "login"

        static let syncDisabled = "sync_disabled"
        static let syncDisabledAndDeleted = "sync_disabled_and_deleted"

        static let barcodeScreenShown = "barcode_screen_shown"
        static let barcodeScannerSuccess = "barcode_scanner_success"
        static let barcodeScannerFailed = "barcode_scanner_failed"
        static let barcodeCodeCopied = "barcode_code_copied"

        static let manualCodeEntryScreenShown = "manual_code_entry_screen_shown"
        static let manualCodeEnteredSuccess = "manual_code_entered_success"
        static let manualCodeEnteredFailed = "manual_code_entered_failed"

        static let setupEndedAbandoned = "setup_ended_abandoned"
        static let setupEndedSuccessful = "setup_ended_successful"

        static let deepLinkFlowStarted = "deep_link_flow_started"
        static let deepLinkFlowSuccess = "deep_link_flow_success"
        static let deepLinkFlowAbandoned = "deep_link_flow_abandoned"
        static let deepLinkTimeout = "deep_link_timeout"
    }

    private let window: ConversionWindow = 0...6

    private func fire(_ metric: String) {
        PixelKit.fireExperimentPixel(
            for: subfeatureID,
            metric: metric,
            conversionWindowDays: window,
            value: "1"
        )
    }

    // MARK: Primary
    func fireSignupDirect()  { fire(Metric.signupDirect) }
    func fireSignupConnect() { fire(Metric.signupConnect) }
    func fireLogin()         { fire(Metric.login) }

    // MARK: Guardrail
    func fireSyncDisabled()           { fire(Metric.syncDisabled) }
    func fireSyncDisabledAndDeleted() { fire(Metric.syncDisabledAndDeleted) }

    func fireBarcodeScreenShown()    { fire(Metric.barcodeScreenShown) }
    func fireBarcodeScannerSuccess() { fire(Metric.barcodeScannerSuccess) }
    func fireBarcodeScannerFailed()  { fire(Metric.barcodeScannerFailed) }
    func fireBarcodeCodeCopied()     { fire(Metric.barcodeCodeCopied) }

    func fireManualCodeEntryScreenShown() { fire(Metric.manualCodeEntryScreenShown) }
    func fireManualCodeEnteredSuccess()   { fire(Metric.manualCodeEnteredSuccess) }
    func fireManualCodeEnteredFailed()    { fire(Metric.manualCodeEnteredFailed) }

    func fireSetupEndedAbandoned()  { fire(Metric.setupEndedAbandoned) }
    func fireSetupEndedSuccessful() { fire(Metric.setupEndedSuccessful) }

    func fireDeepLinkFlowStarted()   { fire(Metric.deepLinkFlowStarted) }
    func fireDeepLinkFlowSuccess()   { fire(Metric.deepLinkFlowSuccess) }
    func fireDeepLinkFlowAbandoned() { fire(Metric.deepLinkFlowAbandoned) }
    func fireDeepLinkTimeout()       { fire(Metric.deepLinkTimeout) }
}
