//
//  WKWebViewPrivateMethodsAvailabilityTests.swift
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

import Navigation
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class WKWebViewPrivateMethodsAvailabilityTests: XCTestCase {

    func testWebViewRespondsTo_printOperationWithPrintInfo() {
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_printOperationWithPrintInfo:forFrame:")))
    }

    func testWebViewRespondsTo_fullScreenPlaceholderView() {
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_fullScreenPlaceholderView")))
    }

    func testWebViewRespondsTo_loadAlternateHTMLString() {
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_loadAlternateHTMLString:baseURL:forUnreachableURL:")))
    }

    func testWebViewRespondsTo_immediateActionAnimationControllerForHitTestResult() {
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_immediateActionAnimationControllerForHitTestResult:withType:userData:")))
    }

    func testWKBackForwardListRespondsTo_removeAllItems() {
        XCTAssertTrue(WKBackForwardList.instancesRespond(to: WKBackForwardList.Selector.removeAllItems))
    }

    func testWKBackForwardListRespondsTo_clear() {
        XCTAssertTrue(WKBackForwardList.instancesRespond(to: WKBackForwardList.Selector.clear))
    }

    func testWebViewRespondsTo_pageMutedState() {
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_setPageMuted:")))
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_mediaMutedState")))
    }

    func testWKWebpagePreferencesCustomHeaderFieldsSupported() {
        XCTAssertTrue(NavigationPreferences.customHeadersSupported)
        let testHeaders = ["X-CUSTOM-HEADER": "TEST"]
        let customHeaderFields = CustomHeaderFields(fields: testHeaders, thirdPartyDomains: [URL.duckDuckGo.host!])
        XCTAssertNotNil(customHeaderFields as? NSObject)
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.customHeaderFields = customHeaderFields.map { [$0] }
        XCTAssertEqual(pagePrefs.customHeaderFields, customHeaderFields.map { [$0] })
    }

    func testWKPDFHUDViewClassAvailable() {
        XCTAssertNotNil(WKPDFHUDViewWrapper.WKPDFHUDViewClass)
        XCTAssertTrue(WKPDFHUDViewWrapper.WKPDFHUDViewClass?.instancesRespond(to: WKPDFHUDViewWrapper.performActionForControlSelector) ==  true)
        XCTAssertTrue(WKPDFHUDViewWrapper.WKPDFHUDViewClass?.instancesRespond(to: WKPDFHUDViewWrapper.setVisibleSelector) ==  true)
    }

    func testWebViewRespondsTo_isPlayingAudio() {
        XCTAssertTrue(WKWebView.instancesRespond(to: NSSelectorFromString("_isPlayingAudio")))
    }

    func testWebViewConfigurationRespondsTo_processName() {
        XCTAssertTrue(WKWebViewConfiguration.instancesRespond(to: WKWebViewConfiguration.ProcessNameSelector.processName))
        XCTAssertTrue(WKWebViewConfiguration.instancesRespond(to: WKWebViewConfiguration.ProcessNameSelector.setProcessName))
    }

    @MainActor
    func testApplyStandardConfigurationDoesModifyProcessNameWhenPrivateProcessNameIsEnabled() {
        let configuration = WKWebViewConfiguration()

        configuration.applyStandardConfiguration(contentBlocking: MockContentBlocking(), burnerMode: .regular, privateProcessName: true)
        XCTAssertEqual(configuration.systemProcessName, "DuckDuckGo Web Content")
    }

    @MainActor
    func testApplyStandardConfigurationDoesNotModifyProcessNameWhenPrivateProcessNameIsDisabled() {
        let configuration = WKWebViewConfiguration()

        configuration.applyStandardConfiguration(contentBlocking: MockContentBlocking(), burnerMode: .regular, privateProcessName: false)
        XCTAssertEqual(configuration.systemProcessName, "")
    }
}
