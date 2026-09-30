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
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var errorMessage: String?

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
        let text = rows.map { row in
            [row.date.formatted(date: .omitted, time: .standard),
             "\(row.entry.extensionName) v\(row.entry.version)",
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
                Button("Refresh") { viewModel.refresh() }
                Button("Copy") { viewModel.copyToPasteboard() }
                    .disabled(viewModel.rows.isEmpty)
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
                Spacer()
            }
            .padding(8)

            List {
                header
                ForEach(viewModel.rows) { row in
                    HStack(alignment: .top) {
                        Text(row.date.formatted(date: .omitted, time: .standard)).frame(width: 90, alignment: .leading)
                        Text("\(row.entry.extensionName) v\(row.entry.version)").frame(width: 200, alignment: .leading)
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
            Text("Time").frame(width: 90, alignment: .leading)
            Text("Extension").frame(width: 200, alignment: .leading)
            Text("Kind").frame(width: 90, alignment: .leading)
            Text("API")
            Spacer()
        }
        .font(.headline)
    }
}
