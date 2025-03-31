//
//  BrokenSiteReporter.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import Persistence
import os.log

public protocol BrokenSiteReportPersistencyManaging {

    func getBrokenSiteReportHistory(forDomainIdentifier domainIdentifier: String) throws -> BrokenSiteReportEntry?
    func persist(entry: BrokenSiteReportEntry) throws

}

public enum BrokenSiteReporterError: Error {

    case failedToGenerateHistoryEntry
    case missingExpiryDate

}

/// Class responsible of reporting broken sites
/// The actual report is sent via Pixel from the main app, this class only persists the reports' history and prepares the models.
public class BrokenSiteReporter {

    /// A closure that receives the Pixel's parameters
    public typealias PixelHandler = (_ parameters: [String: String]) -> Void
    /// Pixels are sent by the main apps not by BSK, this is the closure called by the class when a pixel need to be sent
    let pixelHandler: PixelHandler
    public let persistencyManager: ExpiryStorage

    public init(pixelHandler: @escaping PixelHandler,
                keyValueStoring: KeyValueStoringDictionaryRepresentable,
                storageConfiguration: ExpiryStorageConfiguration = .defaultConfig) {
        self.pixelHandler = pixelHandler
        self.persistencyManager = ExpiryStorage(keyValueStoring: keyValueStoring, configuration: storageConfiguration)
    }

    /// Report the site breakage
    public func report(_ report: BrokenSiteReport, reportMode: BrokenSiteReport.Mode, daysToExpiry: Int = 30) throws {

        let now = Date()
        let removedCount = persistencyManager.removeExpiredItems(currentDate: now)
        if removedCount > 0 {
            Logger.privacyDashboard.debug("\(removedCount) breakage history record removed")
        }

        var report = report

        // Create history entry
        guard let entry = BrokenSiteReportEntry(report: report, currentDate: now, daysToExpiry: daysToExpiry) else {
            Logger.privacyDashboard.error("Failed to create a history entry for broken site report")
            throw BrokenSiteReporterError.failedToGenerateHistoryEntry
        }

        Logger.privacyDashboard.debug("Reporting website breakage for \(entry.identifier)")

        // Check if the report has been sent before
        if let storedHistoryEntry = try persistencyManager.getBrokenSiteReportHistory(forDomainIdentifier: entry.identifier) {
            report.lastSentDay = storedHistoryEntry.lastSentDayString
            Logger.privacyDashboard.debug("Broken site report sent on the \(report.lastSentDay ?? "?") for \(entry.identifier)")
        }

        let pixelParams = report.getRequestParameters(forReportMode: reportMode)

        // report the breakage
        pixelHandler(pixelParams)

        // persist history entry
        try persistencyManager.persist(entry: entry) // this overrides the previously stored entry if existed

        Logger.privacyDashboard.debug("Website breakage reported for \(entry.identifier)")
    }

}

extension ExpiryStorage: BrokenSiteReportPersistencyManaging {

    public func getBrokenSiteReportHistory(forDomainIdentifier domainIdentifier: String) throws -> BrokenSiteReportEntry? {

        if let savedData = value(forKey: domainIdentifier) as? String {
            return BrokenSiteReportEntry(safeDomainIdentifier: domainIdentifier, lastSentDayString: savedData)
        }
        return nil
    }

    public func persist(entry: BrokenSiteReportEntry) throws {

        guard let expiryDate = entry.expiryDate else {
            throw BrokenSiteReporterError.missingExpiryDate
        }
        set(value: entry.lastSentDayString, forKey: entry.identifier, expiryDate: expiryDate)
    }
}
