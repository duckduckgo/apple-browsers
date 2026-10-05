//
//  BitwardenExtensionInstaller.swift
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
import os.log
import WebKit
import ZIPFoundation

/// Errors thrown while downloading Bitwarden.
public enum BitwardenExtensionInstallerError: Error {
    case downloadFailed(statusCode: Int)
}

/// Installs the latest Bitwarden from the Chrome Web Store, replacing any copy already installed.
///
/// Debug tooling: it downloads the CRX, strips its header and installs the unpacked folder, so the
/// background page patcher and the manifest key restore run (zip installs skip them).
@available(macOS 15.4, iOS 18.4, *)
public struct BitwardenExtensionInstaller {

    /// The Chrome Web Store identifier of Bitwarden.
    public static let chromeExtensionIdentifier = "nngceckbapebfimnlniiiahkandclblb"

    /// The Chrome version the download asks for. The Web Store returns nothing without one, and serves
    /// the latest release that supports it, so it only needs to be a version the extension supports.
    private static let chromeVersion = "140.0"

    /// The Web Store update endpoint, which redirects to the versioned `.crx`.
    public static var downloadURL: URL {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx2,crx3"),
            URLQueryItem(name: "x", value: "id%3D\(chromeExtensionIdentifier)%26uc")
        ]
        return components.url!
    }

    /// Downloads the data at a URL, following redirects.
    public static func urlSessionDownload(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
            throw BitwardenExtensionInstallerError.downloadFailed(statusCode: statusCode)
        }
        return data
    }

    private let webExtensionManager: WebExtensionManaging
    private let download: (URL) async throws -> Data
    private let installedIdentifiers: () -> [String]
    private let fileManager: FileManager

    /// - Parameters:
    ///   - installedIdentifiers: Returns the identifiers of installed Bitwarden copies. Defaults to the
    ///     loaded extensions whose manifest `key` derives to Bitwarden's Chrome identifier.
    public init(webExtensionManager: WebExtensionManaging,
                download: @escaping (URL) async throws -> Data = BitwardenExtensionInstaller.urlSessionDownload,
                installedIdentifiers: (() -> [String])? = nil,
                fileManager: FileManager = .default) {
        self.webExtensionManager = webExtensionManager
        self.download = download
        self.installedIdentifiers = installedIdentifiers ?? {
            webExtensionManager.loadedExtensions
                .filter { $0.webExtension.chromeExtensionIdentifier == Self.chromeExtensionIdentifier }
                .map(\.uniqueIdentifier)
        }
        self.fileManager = fileManager
    }

    /// Downloads and installs Bitwarden, uninstalling a previously installed copy first.
    public func install() async throws {
        let crx = try await download(Self.downloadURL)
        let zip = try CRXArchive.zipData(from: crx)

        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent("bitwarden-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: workDirectory) }

        let zipURL = workDirectory.appendingPathComponent("bitwarden.zip")
        let extensionDirectory = workDirectory.appendingPathComponent("extension", isDirectory: true)
        try fileManager.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try zip.write(to: zipURL)
        try fileManager.unzipItem(at: zipURL, to: extensionDirectory)
        try restorePublicKey(from: crx, in: extensionDirectory)

        // The old copy is removed only once the new one unpacked, so a bad download never removes a working install.
        for identifier in installedIdentifiers() {
            try await MainActor.run {
                try webExtensionManager.uninstallExtension(identifier: identifier)
            }
        }

        try await webExtensionManager.installExtension(from: extensionDirectory)
        Logger.webExtensions.info("Installed Bitwarden from the Chrome Web Store")
    }

    /// The `.crx` carries the developer's public key in its header, not in `manifest.json`, so once the
    /// header is stripped the installed copy would have no Chrome identifier, and a later install could
    /// not find it to replace it. Writing the header's key back into the manifest gives it the
    /// identifier Chrome derives. A manifest that already has a `key` is left alone.
    private func restorePublicKey(from crx: Data, in extensionDirectory: URL) throws {
        let manifestURL = extensionDirectory.appendingPathComponent("manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any],
              (manifest["key"] as? String)?.isEmpty != false,
              let publicKey = CRXArchive.publicKey(from: crx) else {
            return
        }

        manifest["key"] = publicKey.base64EncodedString()
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
    }
}
