//
//  NativeMessagingHostManifest.swift
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
import WebExtensions

/// A native messaging host manifest, as Chrome and Firefox define it.
///
/// The companion app writes one file per browser. Bitwarden's reads:
/// ```
/// { "name": "com.8bit.bitwarden",
///   "path": "/Applications/Bitwarden.app/Contents/MacOS/desktop_proxy",
///   "type": "stdio", … }
/// ```
struct NativeMessagingHostManifest: Decodable {

    enum HostType: String, Decodable {
        case stdio
    }

    let name: String
    let path: String
    let type: HostType

    /// Chrome lists the extensions it trusts as `chrome-extension://<id>/` origins.
    let allowedOrigins: [String]?

    /// Firefox lists them by extension identifier.
    let allowedExtensions: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case type
        case allowedOrigins = "allowed_origins"
        case allowedExtensions = "allowed_extensions"
    }

    /// The executable, which the manifest may name by a relative path.
    func executableURL(relativeTo manifestURL: URL) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : manifestURL.deletingLastPathComponent().appendingPathComponent(path)
    }
}

/// Finds the manifest of a native messaging host on disk.
enum NativeMessagingHostManifestLocator {

    enum LocatorError: Error {
        case notFound(name: String)
        case executableMissing(path: String)
    }

    /// Directories that hold host manifests, in search order.
    ///
    /// Our own directory comes first. The others follow because a companion app writes one
    /// file per browser it knows, and no app writes a DuckDuckGo file yet. Bitwarden, for
    /// example, writes a Chrome file and a Mozilla file. Without the fallbacks the user must
    /// copy a file by hand.
    static var searchDirectories: [URL] {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        guard let applicationSupport = library?.appendingPathComponent("Application Support") else {
            return []
        }

        let relativePaths = [
            "DuckDuckGo",
            "Google/Chrome",
            "Chromium",
            "Microsoft Edge",
            "BraveSoftware/Brave-Browser",
            "Vivaldi",
            "Mozilla",
        ]

        return relativePaths.map {
            applicationSupport
                .appendingPathComponent($0)
                .appendingPathComponent("NativeMessagingHosts")
        }
    }

    /// Returns the manifest of the named host, and the executable it points to.
    ///
    /// - Parameters:
    ///   - name: The host name, which is also the manifest's file name without the extension.
    ///   - searchDirectories: The directories to search, in order. Defaults to the browsers'
    ///     own manifest directories, and tests pass a directory of their own.
    static func locate(name: String,
                       searchDirectories: [URL] = Self.searchDirectories) throws -> (manifest: NativeMessagingHostManifest, executable: URL) {
        for directory in searchDirectories {
            let manifestURL = directory.appendingPathComponent("\(name).json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: data)
                let executable = manifest.executableURL(relativeTo: manifestURL)

                guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                    throw LocatorError.executableMissing(path: executable.path)
                }

                Logger.webExtensions.debug("🔗 Host \(name, privacy: .public) found at \(manifestURL.path, privacy: .public)")
                return (manifest, executable)
            } catch {
                Logger.webExtensions.error("❌ Host manifest \(manifestURL.path, privacy: .public) unusable: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        throw LocatorError.notFound(name: name)
    }
}
