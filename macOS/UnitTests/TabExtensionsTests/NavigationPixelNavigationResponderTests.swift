//
//  NavigationPixelNavigationResponderTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class NavigationPixelNavigationResponderTests: XCTestCase {

    /// Regression test for APPLE-MACOS-BDE.
    ///
    /// A navigation that fails provisionally before it ever starts has an empty `navigationActions`
    /// array. `Navigation.navigationAction` force-unwraps `navigationActions.last`, so reading it in
    /// `navigation(_:didFailWith:)` used to trap (EXC_BREAKPOINT). Since `siteLoadingStartTime` is only
    /// set in `didStart` (after a navigation action exists), the responder must short-circuit on it
    /// *before* touching `navigationAction`.
    @MainActor
    func testWhenNavigationFailsWithNoNavigationActions_thenItDoesNotCrashAndNoPixelIsFired() {
        let pixelMock = PixelKitMock(expecting: [])
        let responder = NavigationPixelNavigationResponder(pixelFiring: pixelMock, featureFlagger: MockFeatureFlagger())

        // A navigation that never received a navigation action (empty `navigationActions`),
        // e.g. a provisional load that failed before `didStart`.
        let navigation = Navigation(identity: NavigationIdentity(nil),
                                    responders: ResponderChain(responderRefs: []),
                                    state: .expected(nil),
                                    redirectHistory: nil,
                                    isCurrent: false)

        // Previously trapped on `navigationActions.last!` while evaluating the guard.
        responder.navigation(navigation, didFailWith: WKError(.webContentProcessTerminated))

        // No pixel should be fired for a navigation that never started loading.
        pixelMock.verifyExpectations(file: #file, line: #line)
    }
}
