//
//  TabViewControllerViewportInsetsTests.swift
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

import FeatureFlags_iOS
import XCTest

@testable import DuckDuckGo

@available(iOS 16.0, *)
@MainActor
final class TabViewControllerViewportInsetsTests: XCTestCase {

    private let hidden = UIEdgeInsets(top: 62, left: 0, bottom: 0, right: 0)
    private let shown = UIEdgeInsets(top: 62, left: 0, bottom: 106, right: 0)

    func testWhenFlagIsEnabledThenViewportInsetsFollowTheChrome() {
        let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.floatingUIViewportUnits]))
        defer { tab.prepareForDataClearing() }

        tab.setWebViewViewportInsets(minimum: hidden, maximum: shown)

        XCTAssertEqual(tab.webView.minimumViewportInset, hidden)
        XCTAssertEqual(tab.webView.maximumViewportInset, shown)
    }

    func testWhenFlagIsDisabledThenViewportInsetsStayZero() {
        let tab = TabViewController.fake(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []))
        defer { tab.prepareForDataClearing() }

        tab.setWebViewViewportInsets(minimum: hidden, maximum: shown)

        XCTAssertEqual(tab.webView.minimumViewportInset, .zero)
        XCTAssertEqual(tab.webView.maximumViewportInset, .zero)
    }

    func testWhenFlagIsDisabledWhileRunningThenViewportInsetsAreReset() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.floatingUIViewportUnits])
        let tab = TabViewController.fake(featureFlagger: flagger)
        defer { tab.prepareForDataClearing() }
        tab.setWebViewViewportInsets(minimum: hidden, maximum: shown)

        flagger.enabledFeatureFlags = []
        tab.setWebViewViewportInsets(minimum: hidden, maximum: shown)

        XCTAssertEqual(tab.webView.minimumViewportInset, .zero)
        XCTAssertEqual(tab.webView.maximumViewportInset, .zero)
    }
}
