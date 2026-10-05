//
//  WebExtensionAPICompatibilityLogWindow.swift
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

import AppKit
import OSLog
import SwiftUI
import WebExtensions

/// Shows which unsupported `chrome.*` APIs the loaded extensions touched since launch.
///
/// The entries are the compatibility log lines the app itself wrote (see
/// `WebExtensionAPICompatibilityLog`), read back from the current process's log store.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionAPICompatibilityLogViewModel: ObservableObject {

    struct Row: Identifiable {
        let id: Int
        let date: Date
        let entry: WebExtensionAPICompatibilityLog.Entry

        var extensionLabel: String {
            WebExtensionAPICompatibilityLogViewModel.extensionLabel(name: entry.extensionName, version: entry.version)
        }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var errorMessage: String?

    /// The extension the list is limited to, as `extensionLabel(name:version:)`; `nil` shows all extensions.
    @Published var selectedExtension: String?

    init(rows: [Row] = []) {
        self.rows = rows
    }

    /// How an extension is named in the list and in the filter.
    nonisolated static func extensionLabel(name: String, version: String) -> String {
        "\(name) v\(version)"
    }

    /// The extensions that have entries, plus the selected one so the filter always shows what it is set to.
    var extensionLabels: [String] {
        var labels = Set(rows.map(\.extensionLabel))
        if let selectedExtension {
            labels.insert(selectedExtension)
        }
        return labels.sorted()
    }

    var filteredRows: [Row] {
        guard let selectedExtension else { return rows }
        return rows.filter { $0.extensionLabel == selectedExtension }
    }

    func refresh() {
        Task {
            // The log store can be slow to enumerate, so it is read off the main thread.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Self.readRows() }
            }.value

            switch result {
            case .success(let rows):
                self.rows = rows
                errorMessage = nil
            case .failure(let error):
                errorMessage = "Could not read the log: \(error.localizedDescription)"
            }
        }
    }

    func copyToPasteboard() {
        let text = filteredRows.map { row in
            [row.date.formatted(date: .omitted, time: .standard),
             row.extensionLabel,
             row.entry.kind.rawValue,
             row.entry.api].joined(separator: "\t")
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    nonisolated private static func readRows() throws -> [Row] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@",
                                    WebExtensionAPICompatibilityLog.subsystem,
                                    WebExtensionAPICompatibilityLog.category)

        return try store.getEntries(matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .compactMap { logEntry in
                WebExtensionAPICompatibilityLog.Entry(line: logEntry.composedMessage).map { (logEntry.date, $0) }
            }
            .enumerated()
            .map { Row(id: $0.offset, date: $0.element.0, entry: $0.element.1) }
    }
}

@available(macOS 15.4, *)
struct WebExtensionAPICompatibilityLogView: View {

    @ObservedObject var viewModel: WebExtensionAPICompatibilityLogViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Refresh" as String) { viewModel.refresh() }
                Button("Copy" as String) { viewModel.copyToPasteboard() }
                    .disabled(viewModel.filteredRows.isEmpty)
                Picker("Extension" as String, selection: $viewModel.selectedExtension) {
                    Text(verbatim: "All Extensions").tag(String?.none)
                    ForEach(viewModel.extensionLabels, id: \.self) { label in
                        Text(label).tag(String?.some(label))
                    }
                }
                .fixedSize()
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
                Spacer()
            }
            .padding(8)

            List {
                header
                ForEach(viewModel.filteredRows) { row in
                    HStack(alignment: .top) {
                        Text(row.date.formatted(date: .omitted, time: .standard)).frame(width: 90, alignment: .leading)
                        Text(row.extensionLabel).frame(width: 200, alignment: .leading)
                        Text(row.entry.kind.rawValue).frame(width: 90, alignment: .leading)
                        Text(row.entry.api).textSelection(.enabled)
                        Spacer()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 320)
    }

    private var header: some View {
        HStack {
            Text(verbatim: "Time").frame(width: 90, alignment: .leading)
            Text(verbatim: "Extension").frame(width: 200, alignment: .leading)
            Text(verbatim: "Kind").frame(width: 90, alignment: .leading)
            Text(verbatim: "API")
            Spacer()
        }
        .font(.headline)
    }
}

/// Owns the single compatibility log window, so the Debug Menu and the extension toolbar buttons open the same one.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionAPICompatibilityLogPresenter {

    static let shared = WebExtensionAPICompatibilityLogPresenter()

    private let viewModel = WebExtensionAPICompatibilityLogViewModel()
    private var window: NSWindow?

    /// Opens the window, limited to the given extension (as the log names it) or showing all of them.
    func show(extensionName: String? = nil, version: String? = nil) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: WebExtensionAPICompatibilityLogView(viewModel: viewModel)))
            window.title = "JavaScript API Compatibility Log"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let extensionName, let version {
            viewModel.selectedExtension = WebExtensionAPICompatibilityLogViewModel.extensionLabel(name: extensionName, version: version)
        } else {
            viewModel.selectedExtension = nil
        }
        viewModel.refresh()
        window?.makeKeyAndOrderFront(nil)
    }
}
