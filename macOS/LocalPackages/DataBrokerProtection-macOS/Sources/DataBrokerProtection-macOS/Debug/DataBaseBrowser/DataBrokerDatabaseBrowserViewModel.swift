//
//  DataBrokerDatabaseBrowserViewModel.swift
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
import SecureStorage
import DataBrokerProtectionCore
import PixelKit

final class DataBrokerDatabaseBrowserViewModel: ObservableObject {
    @Published var selectedTable: DataBrokerDatabaseBrowserData.Table?
    @Published var tables: [DataBrokerDatabaseBrowserData.Table]
    @Published var sortColumn: String?
    @Published var sortAscending: Bool = true
    @Published var columnWidths: [String: CGFloat] = [:]

    // Table-specific state storage
    private var tableSortState: [String: (column: String?, ascending: Bool)] = [:]
    private var tableColumnWidths: [String: [String: CGFloat]] = [:]
    private let dataManager: DataBrokerProtectionDataManager?

    internal init(tables: [DataBrokerDatabaseBrowserData.Table]? = nil, localBrokerService: LocalBrokerJSONServiceProvider) {

        if let tables = tables {
            self.tables = tables
            self.selectedTable = tables.first
            self.dataManager = nil
        } else {
            let fakeBroker = DataBrokerDebugFlagFakeBroker()
            let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
            let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)

            guard let pixelKit = PixelKit.shared else {
                fatalError("PixelKit not set up")
            }
            let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
            let privacyConfigManager = DBPPrivacyConfigurationManager()

            let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler, privacyConfigManager: privacyConfigManager)
            guard let vault = try? vaultFactory.makeVault(reporter: reporter) else {
                fatalError("Failed to make secure storage vault")
            }

            let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault, localBrokerService: localBrokerService)

            self.dataManager = DataBrokerProtectionDataManager(database: database)
            self.tables = [DataBrokerDatabaseBrowserData.Table]()
            self.selectedTable = nil
            updateTables()
        }
    }

    private func createTable(using fetchData: [Any], tableName: String) -> DataBrokerDatabaseBrowserData.Table {
        let rows = fetchData.map { convertToGenericRowData($0) }
        let table = DataBrokerDatabaseBrowserData.Table(name: tableName, rows: rows)
        return table
    }

    private func updateTables() {
        guard let dataManager = self.dataManager else { return }

        Task {
            guard let data = try? dataManager.fetchBrokerProfileQueryData(ignoresCache: true),
                  let attempts = try? dataManager.fetchAllOptOutAttempts() else {
                assertionFailure("DataManager error during DataBrokerDatavaseBrowserViewModel.updateTables")
                return
            }

            let profileBrokers = data.map { $0.dataBroker }
            let dataBrokers = Array(Set(profileBrokers)).sorted { $0.id ?? 0 < $1.id ?? 0 }

            let profileQuery = Array(Set(data.map { $0.profileQuery }))
            let scanJobs = data.map { $0.scanJobData }
            let optOutJobs = data.flatMap { $0.optOutJobData }
            let extractedProfiles = data.flatMap { $0.extractedProfiles }
            let events = data.flatMap { $0.events }

            let brokersTable = createTable(using: dataBrokers, tableName: "DataBrokers")
            let profileQueriesTable = createTable(using: profileQuery, tableName: "ProfileQuery")
            let scansTable = createTable(using: scanJobs, tableName: "ScanOperation")
            let optOutsTable = createTable(using: optOutJobs, tableName: "OptOutOperation")
            let extractedProfilesTable = createTable(using: extractedProfiles, tableName: "ExtractedProfile")
            let eventsTable = createTable(using: events.sorted(by: { $0.date < $1.date }), tableName: "Events")
            let attemptsTable = createTable(using: attempts.sorted(by: <), tableName: "OptOutAttempts")

            DispatchQueue.main.async {
                self.tables = [brokersTable, profileQueriesTable, scansTable, optOutsTable, extractedProfilesTable, eventsTable, attemptsTable]
            }
        }
 }

    func sortedRows(for table: DataBrokerDatabaseBrowserData.Table) -> [DataBrokerDatabaseBrowserData.Row] {
        guard let sortState = tableSortState[table.name],
              let sortColumn = sortState.column else {
            return table.rows
        }

        return table.rows.sorted { row1, row2 in
            let val1 = row1.data[sortColumn]?.description.lowercased() ?? ""
            let val2 = row2.data[sortColumn]?.description.lowercased() ?? ""
            return sortState.ascending ? val1 < val2 : val1 > val2
        }
    }

    func toggleSort(for column: String, in table: DataBrokerDatabaseBrowserData.Table) {
        let tableName = table.name
        let currentState = tableSortState[tableName]

        if currentState?.column == column {
            // Toggle ascending/descending for same column
            let newAscending = !(currentState?.ascending ?? true)
            tableSortState[tableName] = (column: column, ascending: newAscending)
            sortColumn = column
            sortAscending = newAscending
        } else {
            // New column, default to ascending
            tableSortState[tableName] = (column: column, ascending: true)
            sortColumn = column
            sortAscending = true
        }
    }

    func columnWidth(for column: String, in table: DataBrokerDatabaseBrowserData.Table) -> CGFloat {
        return tableColumnWidths[table.name]?[column] ?? 200.0
    }

    func setColumnWidth(_ width: CGFloat, for column: String, in table: DataBrokerDatabaseBrowserData.Table) {
        let tableName = table.name
        if tableColumnWidths[tableName] == nil {
            tableColumnWidths[tableName] = [:]
        }
        tableColumnWidths[tableName]?[column] = max(60.0, width) // Minimum width of 60

        // Update the published property for UI binding
        columnWidths[column] = max(60.0, width)
    }

    func initializeColumnWidths(for table: DataBrokerDatabaseBrowserData.Table) {
        guard !table.rows.isEmpty else { return }

        let tableName = table.name
        let columnKeys = Array(table.rows[0].data.keys).sorted()

        if tableColumnWidths[tableName] == nil {
            tableColumnWidths[tableName] = [:]
        }

        for key in columnKeys {
            if tableColumnWidths[tableName]?[key] == nil {
                tableColumnWidths[tableName]?[key] = 200.0 // Default width
            }
        }

        // Update published properties for current table
        updatePublishedState(for: table)
    }

    func updatePublishedState(for table: DataBrokerDatabaseBrowserData.Table) {
        let tableName = table.name

        // Update sort state
        if let sortState = tableSortState[tableName] {
            sortColumn = sortState.column
            sortAscending = sortState.ascending
        } else {
            sortColumn = nil
            sortAscending = true
        }

        // Update column widths
        if let tableWidths = tableColumnWidths[tableName] {
            columnWidths = tableWidths
        } else {
            columnWidths = [:]
        }
    }

    private func convertToGenericRowData<T>(_ item: T) -> DataBrokerDatabaseBrowserData.Row {
        let mirror = Mirror(reflecting: item)
        var data: [String: CustomStringConvertible] = [:]
        for child in mirror.children {
            var label: String

            if let childLabel = child.label {
                label = childLabel
            } else {
                label = "No label"
            }

            data[label] = "\(unwrapChildValue(child.value) ?? "-")"
        }
        return DataBrokerDatabaseBrowserData.Row(data: data)
    }

    private func unwrapChildValue(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle != .optional {
            return value
        }

        guard let child = mirror.children.first else {
            return nil
        }

        return unwrapChildValue(child.value)
    }
}

struct DataBrokerDatabaseBrowserData {

    struct Row: Identifiable, Hashable {
        var id = UUID()
        var data: [String: CustomStringConvertible]

        static func == (lhs: Row, rhs: Row) -> Bool {
            return lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    struct Table: Hashable, Identifiable {
        let id = UUID()
        let name: String
        let rows: [DataBrokerDatabaseBrowserData.Row]

        static func == (lhs: Table, rhs: Table) -> Bool {
            return lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }

}

extension DataBrokerProtectionDataManager {
    func fetchAllOptOutAttempts() throws -> [AttemptInformation] {
        try database.fetchAllAttempts()
    }
}

extension AttemptInformation: Comparable {
    public static func < (lhs: AttemptInformation, rhs: AttemptInformation) -> Bool {
        if lhs.extractedProfileId != rhs.extractedProfileId {
            return lhs.extractedProfileId < rhs.extractedProfileId
        } else if lhs.dataBroker != rhs.dataBroker {
            return lhs.dataBroker < rhs.dataBroker
        } else {
            return lhs.startDate < rhs.startDate
        }
    }

    public static func == (lhs: AttemptInformation, rhs: AttemptInformation) -> Bool {
        lhs.attemptId == rhs.attemptId
    }
}
