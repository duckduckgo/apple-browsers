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

import AppKitExtensions
import Foundation
import os.log
import WebExtensions

/// A native messaging host manifest, as Chrome defines it.
///
/// ```
/// { "name": "com.example.host",
///   "path": "/Applications/Example.app/Contents/MacOS/host",
///   "type": "stdio",
///   "allowed_origins": ["chrome-extension://<id>/"] }
/// ```
struct NativeMessagingHostManifest: Decodable {

    enum HostType: String, Decodable {
        case stdio
    }

    let name: String
    let path: String
    let type: HostType

    /// The extensions the host trusts, as `chrome-extension://<id>/` origins.
    let allowedOrigins: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case type
        case allowedOrigins = "allowed_origins"
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
        case invalidName(name: String)
        case notFound(name: String)
        case executableMissing(path: String)
    }

    /// Directories that hold host manifests, in search order.
    ///
    /// Our own directories come first: the one in the user's Library, then the one in our container.
    /// The other Chromium browsers' directories follow, because a companion app writes one file
    /// per browser it knows and may not write one for us.
    ///
    /// A companion app may also install its manifest for all users, under `/Library` rather than
    /// the user's own Library. macOS does this for iCloud Passwords, whose manifest lives in the
    /// system-level Chrome directory, `/Library/Google/Chrome/NativeMessagingHosts`. Chrome searches
    /// the user-level directory first and the system-level one second, so the system-level list,
    /// in the same browser order, follows the user-level one. Several Chrome-family browsers keep
    /// their system-level directory outside `/Library/Application Support`.
    ///
    /// The browser fallbacks, at either level, go away once companion apps write a DuckDuckGo file.
    static var searchDirectories: [URL] {
        var directories = ownHostsDirectories

        if let userLibrary = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let userRelativePaths = [
                "Application Support/Google/Chrome",
                "Application Support/Chromium",
                "Application Support/Microsoft Edge",
                "Application Support/BraveSoftware/Brave-Browser",
                "Application Support/Vivaldi",
            ]
            directories += hostDirectories(in: userLibrary, relativePaths: userRelativePaths)
        }

        // The local domain's Library is `/Library`.
        if let systemLibrary = FileManager.default.urls(for: .libraryDirectory, in: .localDomainMask).first {
            let systemRelativePaths = [
                ownRelativePath,
                "Google/Chrome",
                "Application Support/Chromium",
                "Microsoft/Edge",
                "Application Support/BraveSoftware/Brave-Browser",
                "Application Support/Vivaldi",
            ]
            directories += hostDirectories(in: systemLibrary, relativePaths: systemRelativePaths)
        }

        return directories
    }

    /// Our own directory in the user's Library, which is the first directory searched.
    static var userHostsDirectory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first.map {
            hostDirectory(in: $0, relativePath: ownRelativePath)
        }
    }

    /// Our own directory in our container's Application Support, which is the second directory searched.
    ///
    /// The path is `~/Library/Containers/<bundle ID>/Data/Library/Application Support/NativeMessagingHosts`
    /// also in builds that are not sandboxed.
    static var containerHostsDirectory: URL {
        URL.sandboxApplicationSupportURL.appendingPathComponent("NativeMessagingHosts")
    }

    /// Our own directories in the user's Library and in our container, in search order.
    static var ownHostsDirectories: [URL] {
        [userHostsDirectory, containerHostsDirectory].compactMap { $0 }
    }

    /// Creates our own host directory if it does not exist, so that a companion app has a place for its manifest.
    static func createHostsDirectoryIfNeeded(at directory: URL?) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            let nsError = error as NSError
            Logger.webExtensions.error("""
            ❌ Cannot create \(directory.path, privacy: .private): \
            errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code)
            """)
        }
    }

    private static let ownRelativePath = "Application Support/DuckDuckGo"

    private static func hostDirectory(in library: URL, relativePath: String) -> URL {
        library
            .appendingPathComponent(relativePath)
            .appendingPathComponent("NativeMessagingHosts")
    }

    private static func hostDirectories(in library: URL, relativePaths: [String]) -> [URL] {
        relativePaths.map { hostDirectory(in: library, relativePath: $0) }
    }

    /// Chrome's rule for host names: lowercase letters, digits and underscores in dot-separated components.
    private static let validNamePattern = "^[a-z0-9_]+(\\.[a-z0-9_]+)*$"

    /// Returns the manifest of the named host, and the executable it points to.
    ///
    /// The name must follow Chrome's rule, so it cannot reach outside the search directories,
    /// and the manifest found must carry the same name.
    ///
    /// - Parameters:
    ///   - name: The host name, which is also the manifest's file name without the extension.
    ///   - searchDirectories: The directories to search, in order. Defaults to the browsers'
    ///     own manifest directories, and tests pass a directory of their own.
    static func locate(name: String,
                       searchDirectories: [URL] = Self.searchDirectories) throws -> (manifest: NativeMessagingHostManifest, executable: URL) {
        guard name.range(of: validNamePattern, options: .regularExpression) != nil else {
            throw LocatorError.invalidName(name: name)
        }

        for directory in searchDirectories {
            let manifestURL = directory.appendingPathComponent("\(name).json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: data)
                guard manifest.name == name else {
                    throw LocatorError.invalidName(name: manifest.name)
                }
                let executable = manifest.executableURL(relativeTo: manifestURL)

                guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                    throw LocatorError.executableMissing(path: executable.path)
                }

                Logger.webExtensions.debug("🔗 Host \(name, privacy: .public) found at \(manifestURL.path, privacy: .private)")
                return (manifest, executable)
            } catch {
                let nsError = error as NSError
                Logger.webExtensions.error("""
                ❌ Host manifest \(manifestURL.path, privacy: .private) unusable: \
                errorDomain=\(nsError.domain, privacy: .public) errorCode=\(nsError.code)
                """)
                continue
            }
        }

        throw LocatorError.notFound(name: name)
    }
}
