//
//  MockSyncSetupExperimentPixelFiring.swift
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

@testable import DuckDuckGo

final class MockSyncSetupExperimentPixelFiring: SyncSetupExperimentPixelFiring {
    private(set) var firedMetrics: [String] = []

    func fireSignupDirect()  { firedMetrics.append("signup_direct") }
    func fireSignupConnect() { firedMetrics.append("signup_connect") }
    func fireLogin()         { firedMetrics.append("login") }

    func fireSyncDisabled()           { firedMetrics.append("sync_disabled") }
    func fireSyncDisabledAndDeleted() { firedMetrics.append("sync_disabled_and_deleted") }

    func fireBarcodeScreenShown()    { firedMetrics.append("barcode_screen_shown") }
    func fireBarcodeScannerSuccess() { firedMetrics.append("barcode_scanner_success") }
    func fireBarcodeScannerFailed()  { firedMetrics.append("barcode_scanner_failed") }
    func fireBarcodeCodeCopied()     { firedMetrics.append("barcode_code_copied") }

    func fireManualCodeEntryScreenShown() { firedMetrics.append("manual_code_entry_screen_shown") }
    func fireManualCodeEnteredSuccess()   { firedMetrics.append("manual_code_entered_success") }
    func fireManualCodeEnteredFailed()    { firedMetrics.append("manual_code_entered_failed") }

    func fireSetupEndedAbandoned()  { firedMetrics.append("setup_ended_abandoned") }
    func fireSetupEndedSuccessful() { firedMetrics.append("setup_ended_successful") }

    func fireDeepLinkFlowStarted()   { firedMetrics.append("deep_link_flow_started") }
    func fireDeepLinkFlowSuccess()   { firedMetrics.append("deep_link_flow_success") }
    func fireDeepLinkFlowAbandoned() { firedMetrics.append("deep_link_flow_abandoned") }
    func fireDeepLinkTimeout()       { firedMetrics.append("deep_link_timeout") }
}
