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

/// Installs the DuckDuckGo Firefox extension via one of two mechanisms:
/// opening Firefox at the extension's signed install URL on addons.mozilla.org,
/// or downloading the signed XPI locally and opening the local file with Firefox.
/// Both surface Firefox's native "Add extension" confirmation. Feasibility spike — see
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
    private let launch: (_ fileOrURLToOpen: URL, _ firefoxApplicationURL: URL) -> Void
    private let downloadXPI: (_ xpiURL: URL, _ completion: @escaping (URL?) -> Void) -> Void

    init(
        installURL: URL = InstallURL.directXPI,
        firefoxApplicationURL: @escaping () -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: FirefoxExtensionInstaller.firefoxBundleID)
        },
        launch: @escaping (URL, URL) -> Void = { fileOrURLToOpen, firefoxApplicationURL in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileOrURLToOpen],
                                    withApplicationAt: firefoxApplicationURL,
                                    configuration: configuration,
                                    completionHandler: nil)
        },
        downloadXPI: @escaping (URL, @escaping (URL?) -> Void) -> Void = { xpiURL, completion in
            let task = URLSession.shared.downloadTask(with: xpiURL) { location, _, error in
                guard let location else {
                    Logger.general.error("Failed to download Firefox extension XPI: \(String(describing: error), privacy: .public)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("duckduckgo-for-firefox.xpi")
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: location, to: destination)
                    DispatchQueue.main.async { completion(destination) }
                } catch {
                    Logger.general.error("Failed to save downloaded Firefox extension XPI: \(String(describing: error), privacy: .public)")
                    DispatchQueue.main.async { completion(nil) }
                }
            }
            task.resume()
        }
    ) {
        self.installURL = installURL
        self.firefoxApplicationURL = firefoxApplicationURL
        self.launch = launch
        self.downloadXPI = downloadXPI
    }

    /// Whether Firefox is installed and the extension install can be attempted.
    var canInstallDDGExtension: Bool {
        firefoxApplicationURL() != nil
    }

    /// Launches Firefox directly at the DuckDuckGo extension install URL.
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

    /// Downloads the signed XPI to a local temporary file, then opens that local file with Firefox.
    /// - Parameter completion: called on the main queue with `true` if the download succeeded and
    ///   Firefox was launched with the local file, `false` if Firefox is not installed or the
    ///   download failed.
    func installDDGExtensionByDownloadingXPI(completion: ((Bool) -> Void)? = nil) {
        guard let firefoxApplicationURL = firefoxApplicationURL() else {
            Logger.general.error("Cannot install DuckDuckGo Firefox extension: Firefox is not installed")
            completion?(false)
            return
        }
        downloadXPI(installURL) { [launch] localFileURL in
            guard let localFileURL else {
                completion?(false)
                return
            }
            launch(localFileURL, firefoxApplicationURL)
            completion?(true)
        }
    }
}
