//
//  DataBrokerLogMonitorComponents.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import OSLog
import DataBrokerProtectionCore

struct LogMonitorToolbarView: View {
    let isMonitoring: Bool
    let logCount: Int

    let onStartStop: () -> Void
    let onClear: () -> Void

    @Binding var retentionLimit: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button(isMonitoring ? "Stop" : "Start") {
                    onStartStop()
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    onClear()
                }
                .disabled(logCount == 0)
            }

            Divider()

            HStack(spacing: 4) {
                Text("Retain:")
                    .font(.caption)

                TextField("2000", text: $retentionLimit)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .disabled(isMonitoring)

                Text("logs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Text("\(logCount) logs")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(isMonitoring ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(isMonitoring ? "Monitoring" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct LogFilterControlsView: View {
    @Binding var filterSettings: LogFilterSettings

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Categories:")
                    .font(.caption)
                    .fontWeight(.medium)

                ForEach(DataBrokerProtectionLoggerCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: Binding(
                        get: { filterSettings.categories.contains(category) },
                        set: { isOn in
                            if isOn {
                                filterSettings.categories.insert(category)
                            } else {
                                filterSettings.categories.remove(category)
                            }
                        }
                    ))
                    .toggleStyle(CheckboxToggleStyle())
                    .font(.caption)
                }

                Spacer()

                TextField("Search logs...", text: $filterSettings.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
            }

            HStack {
                Text("Levels:")
                    .font(.caption)
                    .fontWeight(.medium)

                ForEach(OSLogEntryLog.Level.allPirSupportedLevels, id: \.self) { level in

                    Toggle(level.description, isOn: Binding(
                        get: { filterSettings.logLevels.contains(level) },
                        set: { isOn in
                            if isOn {
                                filterSettings.logLevels.insert(level)
                            } else {
                                filterSettings.logLevels.remove(level)
                            }
                        }
                    ))
                    .toggleStyle(CheckboxToggleStyle())
                    .font(.caption)
                }

                Spacer()

                Toggle("Auto-scroll", isOn: $filterSettings.autoScroll)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

extension OSLogEntryLog.Level {
    public static var allPirSupportedLevels: [OSLogEntryLog.Level] {
        [OSLogEntryLog.Level.debug,
         OSLogEntryLog.Level.info,
         OSLogEntryLog.Level.notice,
         OSLogEntryLog.Level.error,
         OSLogEntryLog.Level.fault]
    }

    var description: String {
        switch self {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        case .notice:
            return "NOTICE"
        case .undefined:
            return "UNDEFINED"
        @unknown default:
            fatalError("New log level introduced, but not yet implemented")
        }
    }
}

struct LogListView: View {
    let logs: [LogEntry]
    let autoScroll: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logs) { log in
                        LogEntryRowView(log: log)
                            .id(log.id)
                            .padding(.horizontal, 8)
                    }

                    if !logs.isEmpty {
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
            }
            .onChange(of: logs.count) { _ in
                if autoScroll && !logs.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}

struct LogEntryRowView: View {
    let log: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeFormatter.string(from: log.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 2) {
                Text(log.levelIcon)
                    .font(.caption)
                Text(log.levelDescription)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(width: 80, alignment: .leading)

            Text(log.category.rawValue)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(4)
                .frame(width: 100, alignment: .leading)

            if #available(macOS 12.0, *) {
                Text(log.message)
                    .font(.caption)
                    .lineLimit(nil)
                    .textSelection(.enabled)
            } else {
                Text(log.message)
                    .font(.caption)
                    .lineLimit(nil)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct LogEmptyStateView: View {
    let isMonitoring: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(PlainButtonStyle())
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.orange),
            alignment: .top
        )
    }
}
