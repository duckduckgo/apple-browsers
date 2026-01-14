//
//  DataBrokerRunCustomJSONView.swift
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
import BrowserServicesKit
import DataBrokerProtectionCore

struct DataBrokerRunCustomJSONView: View {
    @ObservedObject var viewModel: DataBrokerRunCustomJSONViewModel

    @State private var jsonText: String = ""
    @State private var selectedResultId: UUID?
    @State private var selectedBrokerUrl: String?
    @State private var brokerFilter: BrokerFilter = .all
    @State private var brokerSearchText: String = ""
    @State private var selectedTab: Tab = .scan
    @State private var selectedDebugEventId: String?
    @State private var logMonitorWindow: NSWindow?
    
    private let maxNames = 3
    private let maxAddresses = 5
    private let brokerConfigWidth: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            TabView(selection: $selectedTab) {
                contentContainer(scanView)
                    .tabItem {
                        Text("Scan")
                    }
                    .tag(Tab.scan)

                contentContainer(resultsView)
                    .tabItem {
                        Text(extractedProfilesTitle)
                    }
                    .tag(Tab.extractedProfiles)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            brokerConfigView
        }
        .padding(24)
        .frame(minWidth: 1100, minHeight: 800)
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text(viewModel.alert?.title ?? "-"),
                  message: Text(viewModel.alert?.description ?? "-"),
                  dismissButton: .default(Text("OK"), action: { viewModel.showAlert = false })
            )
        }
    }

    private var scanView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan")
                .font(.headline)

            Divider()

            Text("macOS App version: \(viewModel.appVersion())")

            Divider()

            ForEach(0..<min(viewModel.names.count, maxNames), id: \.self) { index in
                HStack(spacing: 12) {
                    TextField("First name", text: $viewModel.names[index].first)
                        .frame(maxWidth: .infinity)
                        .textFieldStyle(.roundedBorder)
                    TextField("Middle", text: $viewModel.names[index].middle)
                        .frame(minWidth: 120)
                        .textFieldStyle(.roundedBorder)
                    TextField("Last name", text: $viewModel.names[index].last)
                        .frame(maxWidth: .infinity)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button("Add other name") {
                viewModel.names.append(.empty())
            }
            .disabled(viewModel.names.count >= maxNames)

            Divider()

            ForEach(0..<min(viewModel.addresses.count, maxAddresses), id: \.self) { index in
                HStack(spacing: 12) {
                    TextField("City", text: $viewModel.addresses[index].city)
                        .frame(maxWidth: .infinity)
                        .textFieldStyle(.roundedBorder)
                    TextField("State (two characters format)", text: $viewModel.addresses[index].state)
                        .onChange(of: viewModel.addresses[index].state) { newValue in
                            if newValue.count > 2 {
                                viewModel.addresses[index].state = String(newValue.prefix(2))
                            }
                        }
                        .frame(minWidth: 180)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button("Add other address") {
                viewModel.addresses.append(.empty())
            }
            .disabled(viewModel.addresses.count >= maxAddresses)

            Divider()

            HStack {
                TextField("Birth year (YYYY)", text: $viewModel.birthYear)
                    .frame(maxWidth: 200)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button("Run") {
                    viewModel.runJSON(jsonString: jsonText)
                    selectedTab = .extractedProfiles
                }
                .disabled(jsonText.isEmpty)

                if jsonText.isEmpty {
                    Text("Please enter broker JSON to enable scan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.isRunningOnAllBrokers {
                ProgressView("Scanning...")
            } else {
                Button("Run all brokers") {
                    viewModel.runAllBrokers()
                    selectedTab = .extractedProfiles
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var brokerConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $brokerFilter) {
                ForEach(BrokerFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()

            TextField("Type to search", text: $brokerSearchText)
                .textFieldStyle(.roundedBorder)

            Divider()

            List(selection: $selectedBrokerUrl) {
                ForEach(filteredBrokers, id: \.url) { (broker: DataBroker) in
                    HStack {
                        Text(broker.url)
                        Spacer()
                        Text(broker.version)
                            .foregroundColor(.secondary)
                    }
                    .tag(broker.url)
                }
            }
            .frame(maxHeight: .infinity)
            .listStyle(.plain)
            .onChange(of: selectedBrokerUrl) { newValue in
                guard let newValue else { return }
                if let broker = viewModel.brokers.first(where: { $0.url == newValue }) {
                    jsonText = broker.toJSONString()
                }
            }

            Divider()

            TextEditor(text: $jsonText)
                .autocorrectionDisabled()
                .border(Color.gray, width: 1)
                .frame(minHeight: 220)
                .padding(.bottom)
        }
        .frame(width: brokerConfigWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if viewModel.isProgressActive {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.progressText)
                    .font(.headline)
            }

            Divider()

            List(selection: $selectedResultId) {
                ForEach(viewModel.results, id: \.id) { scanResult in
                    HStack {
                        Text(scanResult.extractedProfile.name ?? "No name")
                            .padding(.horizontal, 10)
                        Divider()
                        Text(scanResult.extractedProfile.addresses?.map { $0.fullAddress }.joined(separator: ", ") ?? "No address")
                            .padding(.horizontal, 10)
                        Divider()
                        Text(scanResult.extractedProfile.relatives?.joined(separator: ",") ?? "No relatives")
                            .padding(.horizontal, 10)
                        Divider()
                        Button("Opt-out") {
                            viewModel.runOptOut(scanResult: scanResult)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedResultId = scanResult.id
                    }
                    .tag(scanResult.id)
                }
            }
            .frame(maxHeight: 220)
            .listStyle(.plain)

            Divider()

            GeometryReader { proxy in
                let detailsHeight = debugEventDetailsHeight
                let listHeight = max(200, proxy.size.height - detailsHeight - 12)

                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.combinedDebugEvents.isEmpty {
                        Text("No events yet.")
                            .foregroundColor(.secondary)
                    } else {
                        List(selection: $selectedDebugEventId) {
                            Section(header: eventTableHeader.listRowInsets(EdgeInsets())) {
                                ForEach(viewModel.combinedDebugEvents) { event in
                                    HStack(spacing: 12) {
                                        Text(historyDateFormatter.string(from: event.timestamp))
                                            .frame(width: eventTimeColumnWidth, alignment: .leading)
                                        Text(event.kind)
                                            .frame(width: eventKindColumnWidth, alignment: .leading)
                                        Text(event.summary)
                                            .frame(width: eventSummaryColumnWidth, alignment: .leading)
                                        Text(event.details)
                                            .foregroundColor(.secondary)
                                            .lineLimit(10)
                                            .help(event.details)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .listRowInsets(EdgeInsets())
                                    .tag(event.id)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(height: listHeight)
                    }

                    TextEditor(text: .constant(selectedDebugEventDetails))
                        .border(Color.gray, width: 1)
                        .frame(height: detailsHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var eventTableHeader: some View {
        HStack(spacing: 12) {
            Text("Time")
                .frame(width: eventTimeColumnWidth, alignment: .leading)
            Text("Kind")
                .frame(width: eventKindColumnWidth, alignment: .leading)
            Text("Summary")
                .frame(width: eventSummaryColumnWidth, alignment: .leading)
            Text("Details")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var eventTimeColumnWidth: CGFloat { 140 }
    private var eventKindColumnWidth: CGFloat { 90 }
    private var eventSummaryColumnWidth: CGFloat { 240 }
    private var debugEventDetailsHeight: CGFloat { 160 }

    private var selectedResult: ScanResult? {
        guard let selectedResultId else { return nil }
        return viewModel.results.first { $0.id == selectedResultId }
    }

    private var selectedDebugEventDetails: String {
        guard let selectedDebugEventId else { return "" }
        return viewModel.combinedDebugEvents.first { $0.id == selectedDebugEventId }?.details ?? ""
    }

    private var extractedProfilesTitle: String {
        "Extracted Profiles (\(viewModel.results.count))"
    }

    private var filteredBrokers: [DataBroker] {
        let trimmedSearch = brokerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchKey = trimmedSearch.lowercased()
        let sorted = viewModel.brokers.sorted(by: { $0.url.lowercased() < $1.url.lowercased() })
        return sorted.filter { broker in
            guard brokerFilter.includes(broker) else { return false }
            guard !searchKey.isEmpty else { return true }
            let urlMatch = broker.url.lowercased().contains(searchKey)
            let nameMatch = broker.name.lowercased().contains(searchKey)
            return urlMatch || nameMatch
        }
    }

    private func contentContainer<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }

    private func openLogMonitor() {
        if let logMonitorWindow, logMonitorWindow.isVisible {
            logMonitorWindow.makeKeyAndOrderFront(nil)
            return
        }

        let viewModel = DataBrokerLogMonitorViewModel()
        viewModel.startMonitoring()

        let contentView = DataBrokerLogMonitorView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DataBrokerProtection Log Monitor"
        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)

        logMonitorWindow = window
    }
}

private enum Tab: Hashable {
    case scan
    case extractedProfiles
}

private enum BrokerFilter: String, CaseIterable {
    case all
    case active
    case deprecated

    var title: String {
        switch self {
        case .all:
            return "All"
        case .active:
            return "Active"
        case .deprecated:
            return "Deprecated"
        }
    }

    func includes(_ broker: DataBroker) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return broker.removedAt == nil
        case .deprecated:
            return broker.removedAt != nil
        }
    }
}
