//
//  HistoryTestDBBuilder.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import CoreData
import Persistence
import History

// swiftlint:disable force_try

@main
struct HistoryTestDBBuilder {

    static func main() {
        generateDatabase(modelVersion: 1)
    }

    private static func generateDatabase(modelVersion: Int) {
        let bundle = History.bundle
        var momUrl: URL?
        if modelVersion == 1 {
            momUrl = bundle.url(forResource: "BrowsingHistory.momd/BrowsingHistory", withExtension: "mom")
        } else {
            momUrl = bundle.url(forResource: "BrowsingHistory.momd/BrowsingHistory \(modelVersion)", withExtension: "mom")
        }

        guard let momUrl = momUrl else {
            fatalError("Could not find model URL for version \(modelVersion)")
        }

        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            fatalError("Could not find downloads directory")
        }

        let model = NSManagedObjectModel(contentsOf: momUrl)
        guard let model = model else {
            fatalError("Could not load model from \(momUrl)")
        }

        let stack = CoreDataDatabase(name: "BrowsingHistory_V\(modelVersion)",
                                     containerLocation: dir,
                                     model: model)
        stack.loadStore()

        let context = stack.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            buildTestData(in: context)
        }
    }

    private static func buildTestData(in context: NSManagedObjectContext) {
        /* When modifying, please add requirements to list below
             - Test history entries migration and data preservation
             - Test visits relationship migration
             - Test various attributes (trackers, titles, URLs)
             - Test entries with visits (entries 1-4) and without visits (entry 5)
         */

        // Entry 1: Simple entry with title
        let visitDates1 = [
            Date(timeIntervalSince1970: 1000)
        ]
        let entry1 = createHistoryEntry(
            identifier: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            url: URL(string: "https://example.com")!,
            title: "Example Domain",
            lastVisit: visitDates1.last!,
            numberOfTotalVisits: Int64(visitDates1.count),
            trackersFound: false,
            numberOfTrackersBlocked: 0,
            blockedTrackingEntities: nil,
            failedToLoad: false,
            visits: visitDates1,
            in: context
        )

        // Entry 2: Entry with multiple visits
        let visitDates2 = [
            Date(timeIntervalSince1970: 2000),
            Date(timeIntervalSince1970: 2100),
            Date(timeIntervalSince1970: 2200)
        ]
        let entry2 = createHistoryEntry(
            identifier: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            url: URL(string: "https://duckduckgo.com")!,
            title: "DuckDuckGo",
            lastVisit: visitDates2.last!,
            numberOfTotalVisits: Int64(visitDates2.count),
            trackersFound: false,
            numberOfTrackersBlocked: 0,
            blockedTrackingEntities: nil,
            failedToLoad: false,
            visits: visitDates2,
            in: context
        )

        // Entry 3: Entry with trackers blocked
        let visitDates3 = [
            Date(timeIntervalSince1970: 3000),
            Date(timeIntervalSince1970: 3100)
        ]
        let entry3 = createHistoryEntry(
            identifier: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            url: URL(string: "https://tracking-site.com")!,
            title: "Tracking Site",
            lastVisit: visitDates3.last!,
            numberOfTotalVisits: Int64(visitDates3.count),
            trackersFound: true,
            numberOfTrackersBlocked: 3,
            blockedTrackingEntities: "tracker1.com|tracker2.com|tracker3.com",
            failedToLoad: false,
            visits: visitDates3,
            in: context
        )

        // Entry 4: Entry without title
        let visitDates4 = [
            Date(timeIntervalSince1970: 4000)
        ]
        let entry4 = createHistoryEntry(
            identifier: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            url: URL(string: "https://notitle.com/page")!,
            title: nil,
            lastVisit: visitDates4.last!,
            numberOfTotalVisits: Int64(visitDates4.count),
            trackersFound: false,
            numberOfTrackersBlocked: 0,
            blockedTrackingEntities: nil,
            failedToLoad: false,
            visits: visitDates4,
            in: context
        )

        // Entry 5: Entry that failed to load
        let entry5 = createHistoryEntry(
            identifier: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            url: URL(string: "https://failed-load.com")!,
            title: nil,
            lastVisit: Date(timeIntervalSince1970: 5000),
            numberOfTotalVisits: 1,
            trackersFound: false,
            numberOfTrackersBlocked: 0,
            blockedTrackingEntities: nil,
            failedToLoad: true,
            visits: [],
            in: context
        )

        // Ensure all entries are created
        _ = [entry1, entry2, entry3, entry4, entry5]

        try! context.save()
        print("✅ Created BrowsingHistory_V1 database with 5 entries")
    }

    // swiftlint:disable force_cast
    private static func createHistoryEntry(
        identifier: UUID,
        url: URL,
        title: String?,
        lastVisit: Date,
        numberOfTotalVisits: Int64,
        trackersFound: Bool,
        numberOfTrackersBlocked: Int64,
        blockedTrackingEntities: String?,
        failedToLoad: Bool,
        visits: [Date],
        in context: NSManagedObjectContext
    ) -> BrowsingHistoryEntryManagedObject {
        let entry = NSEntityDescription.insertNewObject(
            forEntityName: "BrowsingHistoryEntryManagedObject",
            into: context
        ) as! BrowsingHistoryEntryManagedObject

        entry.identifier = identifier
        entry.url = url
        entry.title = title
        entry.lastVisit = lastVisit
        entry.numberOfTotalVisits = numberOfTotalVisits
        entry.trackersFound = trackersFound
        entry.numberOfTrackersBlocked = numberOfTrackersBlocked
        entry.blockedTrackingEntities = blockedTrackingEntities
        entry.failedToLoad = failedToLoad

        // Note: cookiePopupBlocked is NOT set here because V1 model doesn't have this attribute
        // It will be added with default value (false) during migration to V2

        // Create visits
        for visitDate in visits {
            let visit = NSEntityDescription.insertNewObject(
                forEntityName: "PageVisitManagedObject",
                into: context
            ) as! PageVisitManagedObject
            visit.date = visitDate
            visit.historyEntry = entry
            entry.addToVisits(visit)
        }

        return entry
    }
    // swiftlint:enable force_cast
}

// swiftlint:enable force_try
