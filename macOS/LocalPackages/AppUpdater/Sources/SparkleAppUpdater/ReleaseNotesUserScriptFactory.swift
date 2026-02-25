//
//  ReleaseNotesUserScriptFactory.swift
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

import AppUpdaterShared
import Combine
import Foundation
import Navigation
import Persistence
import PixelKit
import UserScript
import WebKit

public extension SparkleUpdateControlling {
    func makeReleaseNotesNavigationResponder(
        releaseNotesURL: URL,
        scriptsPublisher: some Publisher<any ReleaseNotesUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>
    ) -> any NavigationResponder & AnyObject {
        ReleaseNotesNavigationResponder(
            updateController: self,
            releaseNotesURL: releaseNotesURL,
            scriptsPublisher: scriptsPublisher,
            webViewPublisher: webViewPublisher
        )
    }

    func makeReleaseNotesUserScript(
        pixelFiring: PixelFiring?,
        keyValueStore: ThrowingKeyValueStoring,
        releaseNotesURL: URL
    ) -> Subfeature {
        ReleaseNotesUserScript(
            updateController: self,
            pixelFiring: pixelFiring,
            keyValueStore: keyValueStore,
            releaseNotesURL: releaseNotesURL
        )
    }
}
