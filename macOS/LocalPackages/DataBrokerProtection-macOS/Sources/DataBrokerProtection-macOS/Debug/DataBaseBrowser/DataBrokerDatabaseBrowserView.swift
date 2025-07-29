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
import DataBrokerProtectionCore

struct DataBrokerDatabaseBrowserView: View {
    @ObservedObject var viewModel: DataBrokerDatabaseBrowserViewModel

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.tables) { table in
                    NavigationLink(destination: DatabaseView(data: table.rows, table: table, viewModel: viewModel).navigationTitle(table.name),
                                   tag: table,
                                   selection: $viewModel.selectedTable) {
                        Text(table.name)
                    }
                }
            }
            .listStyle(.sidebar)

            if let table = viewModel.selectedTable {
                DatabaseView(data: table.rows, table: table, viewModel: viewModel)
                    .navigationTitle(table.name)
                    .onAppear {
                        viewModel.updatePublishedState(for: table)
                    }
            } else {
                Text("No selection")
            }
        }
        .frame(minWidth: 1300, minHeight: 800)
    }
}

struct DatabaseView: View {
    @State private var isPopoverVisible = false
    @State private var selectedData: String = ""
    let data: [DataBrokerDatabaseBrowserData.Row]
    let table: DataBrokerDatabaseBrowserData.Table
    @ObservedObject var viewModel: DataBrokerDatabaseBrowserViewModel
    let rowHeight: CGFloat = 40.0

    var body: some View {
        let sortedData = viewModel.sortedRows(for: table)
        if sortedData.count > 0 {
            VStack {
                dataView()
                TextEditor(text: $selectedData)
                    .frame(height: 100)
            }
            .onAppear {
                viewModel.initializeColumnWidths(for: table)
                viewModel.updatePublishedState(for: table)
            }
        } else {
            Text("No Data")
        }
    }

    private func spacerHeight(_ geometry: GeometryProxy) -> CGFloat {
        let sortedData = viewModel.sortedRows(for: table)
        let result = geometry.size.height - CGFloat(sortedData.count) * rowHeight
        return max(0, result)
    }

    private func dataView() -> some View {
        let sortedData = viewModel.sortedRows(for: table)
        let columnKeys = Array(sortedData[0].data.keys).sorted()

        return GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    columnHeadersView(columnKeys: columnKeys)
                    dataRowsView(columnKeys: columnKeys)
                    spacerView(geometry)
                }
                .frame(minWidth: geometry.size.width, minHeight: 0, alignment: .topLeading)
            }
            .clipped()
        }
    }

    private func columnHeadersView(columnKeys: [String]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(columnKeys.enumerated()), id: \.offset) { index, key in
                    columnHeaderCell(key: key, isLastColumn: index == columnKeys.count - 1)
                }
            }
            Divider()
                .background(Color.gray)
        }
    }

    private func columnHeaderCell(key: String, isLastColumn: Bool) -> some View {
        HStack(spacing: 0) {
            sortableColumnButton(for: key)

            if !isLastColumn {
                columnResizeHandle(for: key)
            }
        }
    }

    private func sortableColumnButton(for key: String) -> some View {
        Button(action: {
            viewModel.toggleSort(for: key, in: table)
        }) {
            HStack {
                Text(key)
                    .font(.headline)
                if viewModel.sortColumn == key {
                    Text(viewModel.sortAscending ? "▲" : "▼")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: viewModel.columnWidth(for: key, in: table), height: 35, alignment: .center)
        .clipped()
    }

    private func columnResizeHandle(for key: String) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.5))
            .frame(width: 4, height: 35)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let translation = value.translation
                        let newWidth = viewModel.columnWidth(for: key, in: table) + translation.width
                        viewModel.setColumnWidth(newWidth, for: key, in: table)
                    }
            )
    }

    private func dataRowsView(columnKeys: [String]) -> some View {
        let sortedRows = viewModel.sortedRows(for: table)
        return ForEach(Array(sortedRows.enumerated()), id: \.offset) { index, row in
            VStack(spacing: 0) {
                dataRowView(row: row, columnKeys: columnKeys)
                if index < sortedRows.count - 1 {
                    Divider()
                        .background(Color.gray)
                }
            }
        }
    }

    private func dataRowView(row: DataBrokerDatabaseBrowserData.Row, columnKeys: [String]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(columnKeys.enumerated()), id: \.offset) { index, key in
                dataCell(row: row, key: key, isLastColumn: index == columnKeys.count - 1)
            }
        }
    }

    private func dataCell(row: DataBrokerDatabaseBrowserData.Row, key: String, isLastColumn: Bool) -> some View {
        HStack(spacing: 0) {
            Text("\(row.data[key]?.description ?? "")")
                .padding(.horizontal, 8)
                .frame(width: viewModel.columnWidth(for: key, in: table), height: rowHeight, alignment: .center)
                .background(Color.clear)
                .clipped()
                .onTapGesture {
                    selectedData = row.data[key]?.description ?? ""
                }

            if !isLastColumn {
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 1)
                    .padding(.horizontal, 1.5)
            }
        }
        .frame(height: rowHeight)
    }

    private func spacerView(_ geometry: GeometryProxy) -> some View {
        Spacer()
            .frame(height: spacerHeight(geometry))
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
