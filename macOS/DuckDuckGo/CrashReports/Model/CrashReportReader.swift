//
//  CrashReportReader.swift
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

import Foundation

final class CrashReportReader {

    static let vpnExtensionDisplayName = "com.duckduckgo.macos.vpn.network-extension"

    private let fileManager: FileManager
    private let userDiagnosticReportsDirectory: URL
    private let systemDiagnosticReportsDirectory: URL
    private let currentAppDisplayName: String?
    private let currentAppBundleIdentifier: String?
    private let vpnExtensionBundleIdentifier: String?
    private let dateProvider: () -> Date

    init(fileManager: FileManager = .default,
         userDiagnosticReportsDirectory: URL = FileManager.userDiagnosticReports,
         systemDiagnosticReportsDirectory: URL = FileManager.systemDiagnosticReports,
         currentAppDisplayName: String? = Bundle.main.displayName,
         currentAppBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         vpnExtensionBundleIdentifier: String? = "com.duckduckgo.macos.vpn.network-extension",
         dateProvider: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.userDiagnosticReportsDirectory = userDiagnosticReportsDirectory
        self.systemDiagnosticReportsDirectory = systemDiagnosticReportsDirectory
        self.currentAppDisplayName = currentAppDisplayName
        self.currentAppBundleIdentifier = currentAppBundleIdentifier
        self.vpnExtensionBundleIdentifier = vpnExtensionBundleIdentifier
        self.dateProvider = dateProvider
    }

    func getCrashReports(since lastCheckDate: Date) -> [CrashReport] {
        var allPaths: [URL]

        do {
            allPaths = try fileManager.contentsOfDirectory(at: userDiagnosticReportsDirectory, includingPropertiesForKeys: nil)
        } catch {
            assertionFailure("CrashReportReader: Can't read content of diagnostic reports \(error.localizedDescription)")
            return []
        }

        do {
            let systemPaths = try fileManager.contentsOfDirectory(at: systemDiagnosticReportsDirectory, includingPropertiesForKeys: nil)
            allPaths.append(contentsOf: systemPaths)
        } catch {
            assertionFailure("Failed to read system crash reports: \(error)")
        }

        let filteredPaths = allPaths.filter({
            isCrashReportPath($0) && isFile(at: $0, newerThan: lastCheckDate)
        })

        return filteredPaths
            .compactMap(crashReport(from:))
            .filter(matchesBundleID)
    }

    private func isCrashReportPath(_ path: URL) -> Bool {
        let validExtensions = [LegacyCrashReport.fileExtension, JSONCrashReport.fileExtension]
        guard validExtensions.contains(path.pathExtension) else {
            return false
        }

        let fileName = path.lastPathComponent
        let hasAppPrefix = fileName.hasPrefix(currentAppDisplayName ?? "DuckDuckGo")
        let hasVPNPrefix = fileName.hasPrefix(Self.vpnExtensionDisplayName)
        return hasAppPrefix || hasVPNPrefix
    }

    private func matchesBundleID(_ crashReport: CrashReport) -> Bool {
        guard let bundleID = crashReport.bundleID else {
            return true
        }

        let allowedBundleIdentifiers = [currentAppBundleIdentifier, vpnExtensionBundleIdentifier].compactMap { $0 }
        guard !allowedBundleIdentifiers.isEmpty else { return true }

        return allowedBundleIdentifiers.contains(bundleID)
    }

    private func isFile(at path: URL, newerThan lastCheckDate: Date) -> Bool {
        guard let creationDate = fileManager.fileCreationDate(url: path) else {
            assertionFailure("CrashReportReader: Can't get the creation date of the report")
            return true
        }

        let currentDate = dateProvider()
        return creationDate > lastCheckDate && creationDate < currentDate
    }

    private func crashReport(from url: URL) -> CrashReport? {
        switch url.pathExtension {
        case LegacyCrashReport.fileExtension: return LegacyCrashReport(url: url)
        case JSONCrashReport.fileExtension: return JSONCrashReport(url: url)
        default: return nil
        }
    }

}

fileprivate extension FileManager {

    static let userDiagnosticReports: URL = {
        let homeDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        return homeDirectoryURL
            .appendingPathComponent("Library/Logs/DiagnosticReports")
    }()

    static let systemDiagnosticReports: URL = {
        return URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")
    }()

    func fileCreationDate(url: URL) -> Date? {
        let fileAttributes: [FileAttributeKey: Any] = (try? self.attributesOfItem(atPath: url.path)) ?? [:]
        return fileAttributes[.creationDate] as? Date
    }

}
