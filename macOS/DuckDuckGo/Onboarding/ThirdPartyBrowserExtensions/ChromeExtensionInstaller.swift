//
//  ChromeExtensionInstaller.swift
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

import Foundation
import PixelKit
import PrivacyConfig
import os.log

enum ChromeExtensionInstallerPixelEvent: PixelKitEvent {
    case detectionFailed
    case installFailed

    var name: String {
        switch self {
        case .detectionFailed:
            return "onboarding_chrome-extension-install_detection-failed"
        case .installFailed:
            return "onboarding_chrome-extension-install_install-failed"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        nil
    }
}

final class ChromeExtensionInstaller: ThirdPartyBrowserExtensionInstalling {

    private enum Constants {
        static let externalExtensionUpdateURL = "https://clients2.google.com/service/update2/crx"
        static let externalExtensionsPath = "External Extensions"
        static let profileExtensionsPath = "Extensions"
    }

    private let buildType: ApplicationBuildType
    private let isChromeInstalled: () -> Bool
    private let applicationSupportURL: URL
    private let fileManager: FileManager
    private let pixelFiring: PixelFiring?

    init(
        buildType: ApplicationBuildType,
        isChromeInstalled: @escaping () -> Bool,
        applicationSupportURL: URL,
        fileManager: FileManager,
        pixelFiring: PixelFiring?
    ) {
        self.buildType = buildType
        self.isChromeInstalled = isChromeInstalled
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
        self.pixelFiring = pixelFiring
    }

    private var installedChannelRoots: [URL] {
        ThirdPartyBrowser.chrome.profilesDirectories(applicationSupportURL: applicationSupportURL)
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Whether the Chrome extension can be staged for the user.
    ///
    /// Returns `true` only when all of the following hold:
    /// - The app is a Sparkle (DMG) build
    /// - Chrome is installed and has been launched before
    /// - None of the DDG extension variants are already installed in any Chrome channel or profile
    ///
    /// On filesystem errors during detection, the implementation logs, fires a debug pixel, and returns `false`.
    var canInstallDDGExtension: Bool {
        let channelRoots = installedChannelRoots

        guard buildType.isSparkleBuild,
              isChromeInstalled(),
              !channelRoots.isEmpty else {
            return false
        }

        do {
            return try DDGChromeExtension.allCases.allSatisfy { chromeExtension in
                try isInstalled(extensionID: chromeExtension.extensionID, in: channelRoots) == false
            }
        } catch {
            Logger.general.error("Failed to detect third-party browser extension install state: \(String(describing: error), privacy: .public)")
            pixelFiring?.fire(DebugEvent(ChromeExtensionInstallerPixelEvent.detectionFailed, error: error), frequency: .dailyAndStandard)
            return false
        }
    }

    /// Stages the Chrome search extension by writing External Extensions JSON for each installed Chrome channel.
    ///
    /// - Returns: `true` if all writes succeed or `false` if the user is ineligible, or if any write fails.
    @discardableResult
    func installDDGExtension() -> Bool {
        guard canInstallDDGExtension else {
            return false
        }

        let extensionID = DDGChromeExtension.search.extensionID
        var writeSucceededForAllChannels = true
        for channelRoot in installedChannelRoots {
            let directory = externalExtensionsDirectoryURL(channelRoot: channelRoot)
            let file = externalExtensionFileURL(channelRoot: channelRoot, extensionID: extensionID)
            let fileContents = #"{"external_update_url":"\#(Constants.externalExtensionUpdateURL)"}"#

            do {
                guard let fileData = fileContents.data(using: .utf8) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileData.write(to: file, options: [.atomic])
            } catch {
                writeSucceededForAllChannels = false
                Logger.general.error("Failed to write third-party browser extension install file: \(String(describing: error), privacy: .public)")
                pixelFiring?.fire(DebugEvent(ChromeExtensionInstallerPixelEvent.installFailed, error: error), frequency: .dailyAndStandard)
            }
        }

        return writeSucceededForAllChannels
    }

    private func isInstalled(extensionID: String, in channelRoots: [URL]) throws -> Bool {
        // Check if the extension is installed in any channel's external staging directory.
        for channelRoot in channelRoots {
            let file = externalExtensionFileURL(channelRoot: channelRoot, extensionID: extensionID)
            if fileManager.fileExists(atPath: file.path) {
                return true
            }
        }

        // Check if the extension is installed in any profile.
        let browserProfiles = ThirdPartyBrowser.chrome.browserProfiles(applicationSupportURL: applicationSupportURL)
        for profile in browserProfiles.profiles {
            let extensionsDirectory = profile.profileURL.appendingPathComponent(Constants.profileExtensionsPath, isDirectory: true)
            guard fileManager.fileExists(atPath: extensionsDirectory.path) else {
                continue
            }

            let extensionDirectories = try fileManager.contentsOfDirectory(
                at: extensionsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            if extensionDirectories.contains(where: { $0.hasDirectoryPath && $0.lastPathComponent == extensionID }) {
                return true
            }
        }

        return false
    }

    private func externalExtensionsDirectoryURL(channelRoot: URL) -> URL {
        channelRoot.appendingPathComponent(Constants.externalExtensionsPath, isDirectory: true)
    }

    private func externalExtensionFileURL(channelRoot: URL, extensionID: String) -> URL {
        externalExtensionsDirectoryURL(channelRoot: channelRoot)
            .appendingPathComponent("\(extensionID).json", isDirectory: false)
    }
}
