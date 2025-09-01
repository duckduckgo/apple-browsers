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
    @Published var searchText: String = ""

    // Table-specific state storage
    private var tableSortState: [String: (column: String?, ascending: Bool)] = [:]
    private var tableColumnWidths: [String: [String: CGFloat]] = [:]
    private var tableSearchText: [String: String] = [:]
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
        let filteredRows = filteredRows(for: table)

        guard let sortState = tableSortState[table.name],
              let sortColumn = sortState.column else {
            return filteredRows
        }

        return filteredRows.sorted { row1, row2 in
            let val1 = row1.data[sortColumn]?.description.lowercased() ?? ""
            let val2 = row2.data[sortColumn]?.description.lowercased() ?? ""
            return sortState.ascending ? val1 < val2 : val1 > val2
        }
    }

    func filteredRows(for table: DataBrokerDatabaseBrowserData.Table) -> [DataBrokerDatabaseBrowserData.Row] {
        let searchText = tableSearchText[table.name] ?? ""

        guard !searchText.isEmpty else {
            return table.rows
        }

        let lowercasedSearch = searchText.lowercased()
        return table.rows.filter { row in
            return row.data.values.contains { value in
                value.description.lowercased().contains(lowercasedSearch)
            }
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
        let clampedWidth = max(60.0, width)

        if tableColumnWidths[tableName] == nil {
            tableColumnWidths[tableName] = [:]
        }
        tableColumnWidths[tableName]?[column] = clampedWidth

        // Only update published property if there's a meaningful change
        if abs((columnWidths[column] ?? 0) - clampedWidth) > 1.0 {
            columnWidths[column] = clampedWidth
        }
    }

    func initializeColumnWidths(for table: DataBrokerDatabaseBrowserData.Table) {
        guard !table.rows.isEmpty else { return }

        let tableName = table.name
        let columnKeys = sortedColumnKeys(for: table)

        if tableColumnWidths[tableName] == nil {
            tableColumnWidths[tableName] = [:]
        }

        for key in columnKeys where tableColumnWidths[tableName]?[key] == nil  {
            tableColumnWidths[tableName]?[key] = 200.0 // Default width
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

        // Update search text
        searchText = tableSearchText[tableName] ?? ""
    }

    func setSearchText(_ searchText: String, for table: DataBrokerDatabaseBrowserData.Table) {
        let tableName = table.name
        tableSearchText[tableName] = searchText
        self.searchText = searchText
    }

    func sortedColumnKeys(for table: DataBrokerDatabaseBrowserData.Table) -> [String] {
        guard !table.rows.isEmpty else { return [] }

        return Array(table.rows[0].data.keys).sorted { key1, key2 in
            let key1Lower = key1.lowercased()
            let key2Lower = key2.lowercased()

            // Prioritize ID columns first
            let key1IsId = key1Lower.hasSuffix("id") || key1Lower == "id"
            let key2IsId = key2Lower.hasSuffix("id") || key2Lower == "id"

            if key1IsId && !key2IsId {
                return true
            } else if !key1IsId && key2IsId {
                return false
            } else {
                // Both are ID columns or neither are ID columns, sort alphabetically
                return key1 < key2
            }
        }
    }

    func exportTableAsCSV(_ table: DataBrokerDatabaseBrowserData.Table) -> String {
        let columnKeys = sortedColumnKeys(for: table)
        let rows = sortedRows(for: table)

        guard !columnKeys.isEmpty else { return "" }

        var csvContent = ""

        // Add header row
        let headers = columnKeys.map { escapeCSVField($0) }
        csvContent += headers.joined(separator: ",") + "\n"

        // Add data rows
        for row in rows {
            let values = columnKeys.map { key in
                let value = row.data[key]?.description ?? ""
                return escapeCSVField(value)
            }
            csvContent += values.joined(separator: ",") + "\n"
        }

        return csvContent
    }

    private func escapeCSVField(_ field: String) -> String {
        // If field contains comma, newline, or quotes, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\n") || field.contains("\"") {
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedField)\""
        }
        return field
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
