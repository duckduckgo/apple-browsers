//
//  FirefoxExtensionInstaller.swift
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

import AppKit
import Foundation
import os.log

/// Installs the DuckDuckGo Firefox extension by launching Firefox at the
/// extension's signed install URL on addons.mozilla.org, where Firefox presents
/// its native "Add extension" confirmation. The user's single confirmation click
/// completes the install. Feasibility spike — see
/// docs/superpowers/specs/2026-08-13-firefox-extension-install-spike-design.md
final class FirefoxExtensionInstaller: ThirdPartyBrowserExtensionInstalling {

    enum InstallURL {
        /// Direct signed XPI download; aims to trigger the install doorhanger directly.
        static let directXPI = URL(string: "https://addons.mozilla.org/firefox/downloads/latest/duckduckgo-for-firefox/latest.xpi")!
        /// AMO listing-page fallback; the user taps "Add to Firefox" on the page first.
        static let listingPage = URL(string: "https://addons.mozilla.org/en-US/firefox/addon/duckduckgo-for-firefox/")!
    }

    private static let firefoxBundleID = "org.mozilla.firefox"

    private let installURL: URL
    private let firefoxApplicationURL: () -> URL?
    private let launch: (_ extensionURL: URL, _ firefoxApplicationURL: URL) -> Void

    init(
        installURL: URL = InstallURL.directXPI,
        firefoxApplicationURL: @escaping () -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: FirefoxExtensionInstaller.firefoxBundleID)
        },
        launch: @escaping (URL, URL) -> Void = { extensionURL, firefoxApplicationURL in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([extensionURL],
                                    withApplicationAt: firefoxApplicationURL,
                                    configuration: configuration,
                                    completionHandler: nil)
        }
    ) {
        self.installURL = installURL
        self.firefoxApplicationURL = firefoxApplicationURL
        self.launch = launch
    }

    /// Whether Firefox is installed and the extension install can be attempted.
    var canInstallDDGExtension: Bool {
        firefoxApplicationURL() != nil
    }

    /// Launches Firefox at the DuckDuckGo extension install URL.
    /// - Returns: `true` if Firefox was launched, `false` if Firefox is not installed.
    @discardableResult
    func installDDGExtension() -> Bool {
        guard let firefoxApplicationURL = firefoxApplicationURL() else {
            Logger.general.error("Cannot install DuckDuckGo Firefox extension: Firefox is not installed")
            return false
        }
        launch(installURL, firefoxApplicationURL)
        return true
    }
}
