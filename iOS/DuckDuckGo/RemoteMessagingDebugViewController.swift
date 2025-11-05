//
//  RemoteMessagingDebugViewController.swift
//  DuckDuckGo
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

import UIKit
import SwiftUI
import RemoteMessaging
import Core
import CoreData
import Combine
import Persistence
import OSLog

class RemoteMessagingDebugViewController: UIHostingController<RemoteMessagingDebugRootView> {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: RemoteMessagingDebugRootView())
    }

}

struct RemoteMessagingDebugRootView: View {

    @ObservedObject var model = RemoteMessagingDebugViewModel()
    @State private var shareItem: ShareItem?

    var body: some View {
        List {
            Section {
                if let configInfo = model.configInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Version: \(configInfo.version)")
                            .font(.system(size: 15))
                        Text("Last Processed: \(configInfo.lastProcessedFormatted)")
                            .font(.system(size: 15))
                        if configInfo.invalidate {
                            Text("Status: Invalidated")
                                .font(.system(size: 15))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Button("Refresh Config", action: model.refreshConfig)
            } header: {
                Text("Configuration")
            }

            Section {
                if model.messages.isEmpty {
                    Text("No messages")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(baseColor: .gray70))
                } else {
                    ForEach(model.messages, id: \.id) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ID: \(message.id) | \(message.shown) | \(message.status)")
                                .font(.system(size: 15))
                            Text(message.json ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(baseColor: .gray70))
                        }
                    }
                }
            } header: {
                Text("Messages")
            } footer: {
                Text("This list contains messages that have been shown plus at most 1 message that is scheduled for showing. There may be more messages in the config that will be presented, but they haven't been processed yet.")
            }

            Section {
                if model.isLoadingLogs {
                    HStack {
                        Spacer()
                        SwiftUI.ProgressView()
                        Spacer()
                    }
                } else if model.recentLogs.isEmpty {
                    Text("No Logs")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(baseColor: .gray70))
                } else {
                    ForEach(model.recentLogs.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.recentLogs[index].timestamp)
                                .font(.system(size: 10))
                                .foregroundStyle(Color(baseColor: .gray50))
                            Text(model.recentLogs[index].message)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Recent Processing Logs")
                    Spacer()
                    Button("Export") {
                        shareItem = ShareItem(logs: model.getLogsText())
                    }
                    .font(.system(size: 14))
                    .disabled(model.recentLogs.isEmpty || model.isLoadingLogs)

                    Button("Refresh") {
                        Task {
                            await model.fetchLogs()
                        }
                    }
                    .font(.system(size: 14))
                    .disabled(model.isLoadingLogs)
                }
            } footer: {
                Text("Shows logs from the last minute, to help diagnose issues immediately after a refresh.")
            }
        }
        .navigationTitle("Remote Messaging Debug")
        .toolbar {
            Button("Delete All", role: .destructive, action: model.deleteAll)
                .disabled(model.messages.isEmpty && model.configInfo == nil)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.fileURL])
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let fileURL: URL

    init(logs: String) {
        let fileName = "remote-messaging-logs-\(Date().timeIntervalSince1970).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try logs.write(to: tempURL, atomically: true, encoding: .utf8)
            self.fileURL = tempURL
        } catch {
            // Fallback to a minimal file if writing fails
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("error.txt")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ConfigDebugModel {
    var version: Int64
    var lastProcessed: Date
    var invalidate: Bool

    var lastProcessedFormatted: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: lastProcessed)
    }

    init?(_ config: RemoteMessagingConfigManagedObject) {
        guard let version = config.version?.int64Value,
              let evaluationTimestamp = config.evaluationTimestamp else {
            return nil
        }
        self.version = version
        self.lastProcessed = evaluationTimestamp
        self.invalidate = config.invalidate?.boolValue ?? false
    }
}

struct MessageDebugModel {
    var id: String
    var shown: String
    var status: String
    var json: String?

    init(_ message: RemoteMessageManagedObject) {
        id = message.id ?? "?"
        shown = message.shown ? "shown" : "not shown"
        status = Self.statusString(for: message.status)
        json = message.message
    }

    /// This should be kept in sync with `RemoteMessageStatus` private enum from BSK
    private static func statusString(for status: NSNumber?) -> String {
        switch status?.int16Value {
        case 0:
            return "scheduled"
        case 1:
            return "dismissed"
        case 2:
            return "done"
        default:
            return "unknown"
        }
    }
}

struct LogEntry {
    let timestamp: String
    let message: String
}

class RemoteMessagingDebugViewModel: ObservableObject {

    @Published var messages: [MessageDebugModel] = []
    @Published var configInfo: ConfigDebugModel?
    @Published var recentLogs: [LogEntry] = []
    @Published var isLoadingLogs: Bool = false

    let database: CoreDataDatabase

    init() {
        database = Database.shared
        fetchMessages()
        fetchConfigInfo()
        Task {
            await fetchLogs()
        }

        notificationCancellable = NotificationCenter.default.publisher(for: RemoteMessagingStore.Notifications.remoteMessagesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchMessages()
                self?.fetchConfigInfo()
                Task {
                    await self?.fetchLogs()
                }
            }
    }

    func deleteAll() {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        context.refreshAllObjects()
        context.deleteAll(entityDescriptions: [
            RemoteMessageManagedObject.entity(in: context),
            RemoteMessagingConfigManagedObject.entity(in: context)
        ])

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save after delete all")
        }
        fetchMessages()
        fetchConfigInfo()
    }

    func refreshConfig() {
        (UIApplication.shared.delegate as? AppDelegate)?.debugRefreshRemoteMessages()
    }

    func fetchMessages() {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        context.refreshAllObjects()
        let fetchRequest = RemoteMessageManagedObject.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        messages = ((try? context.fetch(fetchRequest)) ?? []).map(MessageDebugModel.init)
    }

    func fetchConfigInfo() {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        context.refreshAllObjects()
        let fetchRequest = RemoteMessagingConfigManagedObject.fetchRequest()
        fetchRequest.fetchLimit = 1
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "version", ascending: false)]
        fetchRequest.returnsObjectsAsFaults = false

        guard let configs = try? context.fetch(fetchRequest),
              let latestConfig = configs.first else {
            configInfo = nil
            return
        }

        configInfo = ConfigDebugModel(latestConfig)
    }

    @MainActor
    func fetchLogs() async {
        guard #available(iOS 15.0, *) else {
            recentLogs = []
            return
        }

        isLoadingLogs = true

        let logs = await Task.detached {
            do {
                // Only pull the last minute of logs, since the idea is to refresh the config from the menu and see
                // the logs from that refresh - if you want to check logs further back then you can use the dedicated
                // Log Viewer debug menu.
                let logStore = try OSLogStore(scope: .currentProcessIdentifier)
                let predicate = NSPredicate(format: "subsystem == 'Remote Messaging'")

                let startDate = Date().addingTimeInterval(-TimeInterval.minutes(1))
                let position = logStore.position(date: startDate)
                let entries = try logStore.getEntries(at: position, matching: predicate)

                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"

                var logs: [LogEntry] = []
                for entry in entries {
                    if let logEntry = entry as? OSLogEntryLog, logEntry.level != .debug {
                        let timestamp = formatter.string(from: logEntry.date)
                        logs.append(LogEntry(timestamp: timestamp, message: logEntry.composedMessage))
                    }
                }

                return Array(logs.reversed())
            } catch {
                return []
            }
        }.value

        recentLogs = logs
        isLoadingLogs = false
    }

    func getLogsText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let exportDate = dateFormatter.string(from: Date())

        var output = "Remote Messaging Debug Logs\n"
        output += "Exported: \(exportDate)\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        for log in recentLogs {
            output += "[\(log.timestamp)] \(log.message)\n"
        }

        return output
    }

    private var notificationCancellable: AnyCancellable?
}
