//
//  DataBrokerDatabaseBrowserView.swift
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

import SwiftUI
import AppKit
import DataBrokerProtectionCore

struct DataBrokerDatabaseBrowserView: View {
    @ObservedObject var viewModel: DataBrokerDatabaseBrowserViewModel

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.tables) { table in
                    NavigationLink(destination: DatabaseTableContainer(table: table, viewModel: viewModel).navigationTitle(table.name),
                                   tag: table,
                                   selection: $viewModel.selectedTable) {
                        Text(table.name)
                    }
                }
            }
            .listStyle(.sidebar)

            if let table = viewModel.selectedTable {
                DatabaseTableContainer(table: table, viewModel: viewModel)
                    .navigationTitle(table.name)
            } else {
                Text("No selection")
            }
        }
        .frame(minWidth: 1300, minHeight: 1000)
    }
}

struct DatabaseTableContainer: View {
    let table: DataBrokerDatabaseBrowserData.Table
    @ObservedObject var viewModel: DataBrokerDatabaseBrowserViewModel
    @State private var selectedData: String = ""
    var body: some View {
        VStack(spacing: 0) {
            // Search bar with export button
            HStack(spacing: 8) {
                SearchBarView(searchText: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.setSearchText($0, for: table) }
                ))

                Button("Export as CSV") {
                    exportTableAsCSV()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            DatabaseTableView(table: table, viewModel: viewModel, selectedData: $selectedData)

            VStack(spacing: 0) {
                if !selectedData.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Row Details:")
                            .font(.headline)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                            .padding(.bottom, 8)

                        ScrollView {
                            TextEditor(text: $selectedData)
                        }
                        .frame(height: 120)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedData.isEmpty)
        .onAppear {
            viewModel.initializeColumnWidths(for: table)
            viewModel.updatePublishedState(for: table)
        }
    }

    private func exportTableAsCSV() {
        let csvContent = viewModel.exportTableAsCSV(table)

        let savePanel = NSSavePanel()
        savePanel.title = "Export \(table.name) as CSV"
        savePanel.nameFieldStringValue = "\(table.name).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try csvContent.write(to: url, atomically: true, encoding: .utf8)

                    // Open the file location in Finder
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                } catch {
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Could not save CSV file: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}

struct SearchBarView: NSViewRepresentable {
    @Binding var searchText: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search table..."
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchChanged)

        context.coordinator.searchField = searchField

        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != searchText {
            nsView.stringValue = searchText
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        let parent: SearchBarView
        weak var searchField: NSSearchField?

        init(_ parent: SearchBarView) {
            self.parent = parent
        }

        @objc func searchChanged() {
            guard let searchField = searchField else { return }
            parent.searchText = searchField.stringValue
        }
    }
}

// MARK: - NSTableView Implementation

struct DatabaseTableView: NSViewRepresentable {
    let table: DataBrokerDatabaseBrowserData.Table
    @ObservedObject var viewModel: DataBrokerDatabaseBrowserViewModel
    @Binding var selectedData: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        // Configure table view
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = NSSize(width: 1, height: 1)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.focusRingType = .none

        // Setup columns
        setupColumns(for: tableView, context: context)

        // Configure scroll view
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false

        // Store references for updates
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }

        context.coordinator.updateData()
        tableView.reloadData()

        // Update sort indicators
        updateSortIndicators(for: tableView, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func setupColumns(for tableView: NSTableView, context: Context) {
        let sortedData = viewModel.sortedRows(for: table)
        guard !sortedData.isEmpty else { return }

        let columnKeys = viewModel.sortedColumnKeys(for: table)

        // Remove existing columns
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

        for key in columnKeys {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = key
            column.isEditable = false
            column.width = viewModel.columnWidth(for: key, in: table)
            column.minWidth = 60
            column.maxWidth = 1000

            // Create custom header cell with bold font
            let headerCell = NSTableHeaderCell(textCell: key)
            headerCell.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            column.headerCell = headerCell

            // Enable sorting
            let descriptor = NSSortDescriptor(key: key, ascending: true)
            column.sortDescriptorPrototype = descriptor

            tableView.addTableColumn(column)
        }
    }

    private func updateSortIndicators(for tableView: NSTableView, context: Context) {
        // First clear all sort indicators
        for column in tableView.tableColumns {
            tableView.setIndicatorImage(nil, in: column)
        }

        // Set the sort indicator for the current sort column
        if let sortColumn = viewModel.sortColumn,
           let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(sortColumn)) {
            let ascending = viewModel.sortAscending
            let image = ascending ? NSImage(named: "NSAscendingSortIndicator") : NSImage(named: "NSDescendingSortIndicator")
            tableView.setIndicatorImage(image, in: column)
        }
    }
}

// MARK: - NSTableView Coordinator

extension DatabaseTableView {
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let parent: DatabaseTableView
        private var sortedRows: [DataBrokerDatabaseBrowserData.Row] = []
        private var columnKeys: [String] = []

        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        init(_ parent: DatabaseTableView) {
            self.parent = parent
            super.init()
            updateData()
        }

        func updateData() {
            sortedRows = parent.viewModel.sortedRows(for: parent.table)
            if !sortedRows.isEmpty {
                columnKeys = parent.viewModel.sortedColumnKeys(for: parent.table)
            }
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            return sortedRows.count
        }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard let identifier = tableColumn?.identifier.rawValue,
                  row < sortedRows.count else { return nil }

            return sortedRows[row].data[identifier]?.description ?? ""
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let key = tableColumn.identifier.rawValue
            parent.viewModel.toggleSort(for: key, in: parent.table)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }

            if tableView.selectedRow >= 0 && tableView.selectedRow < sortedRows.count {
                let selectedRow = sortedRows[tableView.selectedRow]
                // Show all data from the selected row with improved formatting
                let rowData = columnKeys.compactMap { key in
                    if let value = selectedRow.data[key] {
                        return "\(key): \(value)"
                    }
                    return nil
                }.joined(separator: "\n\n")  // Double newline for better readability

                parent.selectedData = rowData
            } else {
                parent.selectedData = ""
            }
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return true
        }

        // Handle column resizing to update view model
        func tableViewColumnDidResize(_ notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let column = userInfo["NSTableColumn"] as? NSTableColumn else { return }

            let key = column.identifier.rawValue
            parent.viewModel.setColumnWidth(column.width, for: key, in: parent.table)
        }
    }
}

struct ColumnData: Identifiable {
    var id = UUID()
    var columnName: String
    var items: [String]
}

#Preview {
    let fakeRows1 = (1...10).map { index in
        DataBrokerDatabaseBrowserData.Row(data: ["Name": "John Doe", "Age": Int.random(in: 20...60), "Email": "john.doe\(index)@example.com"])
    }
    let fakeTable1 = DataBrokerDatabaseBrowserData.Table(name: "Users", rows: fakeRows1)

    let fakeRows2 = (1...10).map { index in
        DataBrokerDatabaseBrowserData.Row(data: ["Product": "Product \(index)", "Price": Double.random(in: 10...100), "Quantity": Int.random(in: 1...10)])
    }
    let fakeTable2 = DataBrokerDatabaseBrowserData.Table(name: "Products", rows: fakeRows2)

    let fakeTables =  [fakeTable1, fakeTable2]

    DataBrokerDatabaseBrowserView(viewModel: DataBrokerDatabaseBrowserViewModel(tables: fakeTables, localBrokerService: MockLocalBrokerJSONService())
    )
}

private struct MockLocalBrokerJSONService: LocalBrokerJSONServiceProvider {
    func bundledBrokers() throws -> [DataBroker]? { [] }
    func checkForUpdates() async throws {}
}
