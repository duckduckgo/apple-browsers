//
//  MainViewController+LogViewer.swift
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

import Foundation
import OSLog
import AppKit
import SwiftUI

enum LogViewerPreset: String, CaseIterable, Identifiable {
    case allDDG = "All DDG"
    case pixels = "Pixels"
    case networkProtection = "Network Protection"
    case sparkle = "Updates"
    case all = "All"

    var id: String { rawValue }

    var predicate: NSPredicate {
        switch self {
        case .allDDG:
            return NSPredicate(format: "process CONTAINS[c] %@", "duckduckgo")
        case .pixels:
            return NSPredicate(format: "subsystem CONTAINS[cd] %@ AND process CONTAINS[c] %@", "Pixel", "duckduckgo")
        case .networkProtection:
            return NSPredicate(format: "subsystem == %@", "Network protection")
        case .sparkle:
            return NSPredicate(format: """
                (process == "org.sparkle-project.Sparkle" OR processImagePath CONTAINS[c] "Sparkle") \
                OR (subsystem == "Updates") OR (process == "Autoupdate")
            """)
        case .all:
            return NSPredicate(value: true)
        }
    }
}

struct LogViewerEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: OSLogEntryLog.Level
    let subsystem: String
    let category: String
    let process: String
    let message: String
}

@MainActor
final class LogViewerViewModel: ObservableObject {

    @Published var entries: [LogViewerEntry] = []
    @Published var preset: LogViewerPreset = .pixels
    @Published var minutesBack: Int = 30
    @Published var isLoading = false
    @Published var errorMessage: String?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func formattedTimestamp(for entry: LogViewerEntry) -> String {
        Self.timestampFormatter.string(from: entry.date)
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        let preset = self.preset
        let minutesBack = self.minutesBack

        Task.detached(priority: .userInitiated) {
            do {
                let store = try OSLogStore.local()
                let startDate = Date().addingTimeInterval(TimeInterval(-minutesBack * 60))
                let position = store.position(date: startDate)
                let osEntries = try store.getEntries(at: position, matching: preset.predicate)
                let mapped: [LogViewerEntry] = osEntries.compactMap { entry in
                    guard let log = entry as? OSLogEntryLog else { return nil }
                    return LogViewerEntry(
                        date: log.date,
                        level: log.level,
                        subsystem: log.subsystem,
                        category: log.category,
                        process: log.process,
                        message: log.composedMessage
                    )
                }
                await MainActor.run {
                    self.entries = mapped
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

struct LogViewerView: View {

    @StateObject private var viewModel = LogViewerViewModel()
    @State private var searchText = ""
    @State private var minutesText = "30"

    let onClose: () -> Void

    private var filteredEntries: [LogViewerEntry] {
        guard !searchText.isEmpty else { return viewModel.entries }
        let lower = searchText.lowercased()
        return viewModel.entries.filter {
            $0.message.lowercased().contains(lower)
            || $0.subsystem.lowercased().contains(lower)
            || $0.category.lowercased().contains(lower)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var toolbar: some View {
        let emptyPlaceholder: String = ""
        let searchPlaceholder: String = "Search…"
        return HStack(spacing: 12) {
            Picker(selection: $viewModel.preset, label: Text(verbatim: "Filter:")) {
                ForEach(LogViewerPreset.allCases) { preset in
                    Text(verbatim: preset.rawValue).tag(preset)
                }
            }
            .frame(width: 240)
            .onChange(of: viewModel.preset) { _ in
                viewModel.refresh()
            }

            HStack(spacing: 4) {
                Text(verbatim: "Last")
                TextField(emptyPlaceholder, text: $minutesText, onCommit: {
                    if let minutes = Int(minutesText), minutes > 0 {
                        viewModel.minutesBack = minutes
                        viewModel.refresh()
                    } else {
                        minutesText = "\(viewModel.minutesBack)"
                    }
                })
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                Text(verbatim: "min")
            }

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Spacer()

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)

            Button(action: onClose) {
                Text(verbatim: "Close")
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            Text(verbatim: errorMessage)
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredEntries.isEmpty {
            Text(verbatim: "No log entries.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            entryList
        }
    }

    private var entryList: some View {
        List(filteredEntries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(color(for: entry.level))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(viewModel.formattedTimestamp(for: entry)) • \(entry.subsystem.isEmpty ? "—" : entry.subsystem) • \(entry.category.isEmpty ? "—" : entry.category)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }

    private func color(for level: OSLogEntryLog.Level) -> Color {
        switch level {
        case .error, .fault: return .red
        default: return .primary
        }
    }
}

extension MainViewController {

    static var logViewerWindow: NSWindow?

    @objc public func viewLogs(_ sender: NSMenuItem) {
        if let existing = MainViewController.logViewerWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = LogViewerView {
            MainViewController.logViewerWindow?.close()
        }

        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Log Viewer"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainViewController.logViewerWindow = nil
        }

        MainViewController.logViewerWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}
