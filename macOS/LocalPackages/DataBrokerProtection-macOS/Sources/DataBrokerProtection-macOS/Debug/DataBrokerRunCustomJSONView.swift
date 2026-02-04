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
import FeatureFlags

struct DataBrokerRunCustomJSONView: View {
    private enum Constants {
        static let eventTimeColumnWidth: CGFloat = 120
        static let eventKindColumnWidth: CGFloat = 80
        static let eventProfileQueryColumnWidth: CGFloat = 180
        static let eventSummaryColumnWidth: CGFloat = 200
        static let eventDetailsMinWidth: CGFloat = 320
        static let columnSpacing: CGFloat = 12
        static let resultNameColumnWidth: CGFloat = 180
        static let resultAddressColumnWidth: CGFloat = 340
        static let resultRelativesMinWidth: CGFloat = 240
    }

    @ObservedObject var viewModel: DataBrokerRunCustomJSONViewModel

    @State private var jsonText: String = ""
    @State private var selectedResultId: UUID?
    @State private var selectedBrokerUrl: String?
    @State private var brokerFilter: BrokerFilter = .all
    @State private var brokerSearchText: String = ""
    @State private var selectedTab: Tab = .scan
    @State private var selectedDebugEventId: String?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            TabView(selection: $selectedTab) {
                scanView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tabItem {
                        Text("Scan")
                    }
                    .tag(Tab.scan)

                resultsView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tabItem {
                        Text(extractedProfilesTitle)
                    }
                    .tag(Tab.extractedProfiles)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            brokerConfigView
        }
        .padding(24)
        .frame(minWidth: 1080, minHeight: 800)
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text(viewModel.alert?.title ?? "-"),
                  message: Text(viewModel.alert?.description ?? "-"),
                  dismissButton: .default(Text("OK"), action: { viewModel.showAlert = false })
            )
        }
    }

    // MARK: - Broker list + JSON side bar

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
                .font(monospacedTextFont)
                .autocorrectionDisabled()
                .border(Color.gray, width: 1)
                .frame(minHeight: 220)
                .padding(.bottom)
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .topLeading)
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

    private var dbpFeatureFlagLines: [(name: String, value: String)] {
        [
            (FeatureFlag.dbpRemoteBrokerDelivery.rawValue, viewModel.featureFlagger.isRemoteBrokerDeliveryFeatureOn.description),
            (FeatureFlag.dbpEmailConfirmationDecoupling.rawValue, viewModel.featureFlagger.isEmailConfirmationDecouplingFeatureOn.description),
            (FeatureFlag.dbpClickActionDelayReductionOptimization.rawValue, viewModel.featureFlagger.isClickActionDelayReductionOptimizationOn.description),
        ]
    }

    // MARK: - Tab 1: Scan

    private var scanView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Scan")
                    .font(.headline)
                Spacer()
                if #available(macOS 12.0, *) {
                    if viewModel.isEditingPresets {
                        Button("Save Presets") {
                            viewModel.savePresets()
                            viewModel.isEditingPresets = false
                        }

                        Button("Cancel") {
                            viewModel.loadPresets()
                            viewModel.isEditingPresets = false
                        }
                    } else {
                        Menu("Load Preset...") {
                            ForEach(viewModel.presets) { preset in
                                Button(String(describing: preset)) {
                                    viewModel.applyPreset(preset)
                                }
                            }
                        }
                        .disabled(viewModel.presets.isEmpty)

                        Button("Edit Presets") {
                            viewModel.isEditingPresets = true
                        }

                        Button("Save Form as Preset") {
                            viewModel.saveCurrentFormAsPreset()
                        }
                    }
                }
            }

            Divider()

            if #available(macOS 12.0, *), viewModel.isEditingPresets {
                presetForm
            } else {
                scanForm
            }

            Divider()

            Text("macOS App version: \(viewModel.appVersion())")
            Text("DBP API endpoint: \(viewModel.dbpEndpoint)")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(dbpFeatureFlagLines, id: \.name) { flag in
                    Text("\(flag.name): \(flag.value)")
                        .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var presetForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $viewModel.presetsText)
                .font(monospacedTextFont)
                .frame(minHeight: 260)
        }
    }

    private var scanForm: some View {
        Group {
            ForEach(viewModel.names.prefix(DataBrokerRunCustomJSONViewModel.Constants.maxNames)) { name in
                NameRow(name: name)
            }

            Button("Add other name") {
                viewModel.names.append(.empty())
            }
            .disabled(viewModel.names.count >= DataBrokerRunCustomJSONViewModel.Constants.maxNames)

            Divider()

            ForEach(viewModel.addresses.prefix(DataBrokerRunCustomJSONViewModel.Constants.maxAddresses)) { address in
                AddressRow(address: address)
            }

            Button("Add other address") {
                viewModel.addresses.append(.empty())
            }
            .disabled(viewModel.addresses.count >= DataBrokerRunCustomJSONViewModel.Constants.maxAddresses)

            Divider()

            HStack(spacing: 12) {
                TextField("Birth year (YYYY)", text: $viewModel.birthYear)
                    .onChange(of: viewModel.birthYear) { newValue in
                        viewModel.syncAge(fromBirthYear: newValue)
                    }
                    .frame(maxWidth: 200)
                TextField("Age (years)", text: $viewModel.age)
                    .onChange(of: viewModel.age) { newValue in
                        viewModel.syncBirthYear(fromAge: newValue)
                    }
                    .frame(maxWidth: 200)
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
        }
    }

    // MARK: - Tab 2: Extracted profiles

    private var resultsList: some View {
        GeometryReader { proxy in
            let listHeight: CGFloat = 220
            let listWidth = max(resultsTableMinWidth, proxy.size.width)

            if viewModel.results.isEmpty {
                Text("No results yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header: resultsTableHeader
                            .frame(width: listWidth, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                        ) {
                            ForEach(viewModel.results, id: \.id) { scanResult in
                                resultsRow(for: scanResult, listWidth: listWidth)
                                Divider()
                            }
                        }
                    }
                    .frame(minHeight: listHeight, alignment: .topLeading)
                }
                .background(Color(NSColor.textBackgroundColor))
                .frame(height: listHeight)
            }
        }
        .frame(height: 220)
    }

    private var eventsTable: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.combinedDebugEvents.isEmpty {
                    Text("No events yet.")
                        .foregroundColor(.secondary)
                } else {
                    let detailsHeight = debugEventDetailsHeight
                    let listHeight = max(200, proxy.size.height - detailsHeight - 12)
                    let listWidth = max(debugEventTableMinWidth, proxy.size.width)

                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section(header: eventTableHeader
                                .frame(width: listWidth, alignment: .leading)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                            ) {
                                ForEach(viewModel.combinedDebugEvents, id: \DebugEventRow.id) { event in
                                    DebugEventRowView(
                                        event: event,
                                        isSelected: selectedDebugEventId == event.id,
                                        listWidth: listWidth,
                                        eventTimeColumnWidth: Constants.eventTimeColumnWidth,
                                        eventProfileQueryColumnWidth: Constants.eventProfileQueryColumnWidth,
                                        eventKindColumnWidth: Constants.eventKindColumnWidth,
                                        eventSummaryColumnWidth: Constants.eventSummaryColumnWidth,
                                        eventDetailsMinWidth: Constants.eventDetailsMinWidth,
                                        historyDateFormatter: Self.historyDateFormatter
                                    ) {
                                        selectedDebugEventId = event.id
                                    }

                                    Divider()
                                }
                            }
                        }
                        .frame(minHeight: listHeight, alignment: .topLeading)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .frame(height: listHeight)

                    TextEditor(text: .constant(selectedDebugEventDetails))
                        .font(monospacedTextFont)
                        .border(Color.gray, width: 1)
                        .frame(height: detailsHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

            resultsList
            Divider()

            HStack(spacing: 12) {
                Button("Opt-out Selected") {
                    if let selectedResult {
                        viewModel.runOptOut(scanResult: selectedResult)
                    }
                }
                .disabled(selectedResult == nil)

                if let selectedResult, selectedResult.dataBroker.requiresEmailConfirmationDuringOptOut() {
                    Button("Check for email confirmation") {
                        viewModel.checkForEmailConfirmation()
                    }
                    .disabled(!viewModel.canCheckEmailConfirmation(for: selectedResult))

                    Button("Continue opt-out") {
                        viewModel.continueOptOutAfterEmailConfirmation(scanResult: selectedResult)
                    }
                    .disabled(!viewModel.canContinueOptOutAfterEmailConfirmation(for: selectedResult))
                }

                if selectedResult == nil {
                    Text("Select a row to opt out")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            eventsTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resultsTableHeader: some View {
        HStack(spacing: Constants.columnSpacing) {
            Text("Name")
                .frame(width: Constants.resultNameColumnWidth, alignment: .leading)
            Text("Address")
                .frame(width: Constants.resultAddressColumnWidth, alignment: .leading)
            Text("Relatives")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: resultsTableMinWidth, alignment: .leading)
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func resultsRow(for scanResult: DebugScanResult, listWidth: CGFloat) -> some View {
        HStack(spacing: Constants.columnSpacing) {
            Text(scanResult.extractedProfile.name ?? "No name")
                .frame(width: Constants.resultNameColumnWidth, alignment: .leading)
            Text(scanResult.extractedProfile.addresses?.map { $0.fullAddress }.joined(separator: ", ") ?? "No address")
                .frame(width: Constants.resultAddressColumnWidth, alignment: .leading)
            Text(scanResult.extractedProfile.relatives?.joined(separator: ", ") ?? "No relatives")
                .frame(minWidth: Constants.resultRelativesMinWidth,
                       maxWidth: .infinity,
                       alignment: .leading)
        }
        .frame(width: listWidth, alignment: .leading)
        .padding(.vertical, 6)
        .foregroundColor(selectedResultId == scanResult.id ? Color(NSColor.selectedControlTextColor) : Color.primary)
        .background(selectedResultId == scanResult.id ? Color(NSColor.selectedControlColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedResultId = scanResult.id
        }
    }

    private var eventTableHeader: some View {
        HStack(spacing: 12) {
            Text("Time")
                .frame(width: Constants.eventTimeColumnWidth, alignment: .leading)
            Text("Profile Query")
                .frame(width: Constants.eventProfileQueryColumnWidth, alignment: .leading)
            Text("Kind")
                .frame(width: Constants.eventKindColumnWidth, alignment: .leading)
            Text("Summary")
                .frame(width: Constants.eventSummaryColumnWidth, alignment: .leading)
            Text("Details")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: debugEventTableMinWidth, alignment: .leading)
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var debugEventTableMinWidth: CGFloat {
        Constants.eventTimeColumnWidth
        + Constants.eventProfileQueryColumnWidth
        + Constants.eventKindColumnWidth
        + Constants.eventSummaryColumnWidth
        + Constants.eventDetailsMinWidth
        + Constants.columnSpacing * 4
    }
    private var resultsTableMinWidth: CGFloat {
        Constants.resultNameColumnWidth
        + Constants.resultAddressColumnWidth
        + Constants.resultRelativesMinWidth
        + Constants.columnSpacing * 2
    }
    private var debugEventDetailsHeight: CGFloat { 160 }
    private var selectedResult: DebugScanResult? {
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

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private var monospacedTextFont: Font {
        if #available(macOS 12.0, *) {
            return .system(.body, design: .monospaced)
        }
        return .system(.body)
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
        case .all: return "All"
        case .active: return "Active"
        case .deprecated: return "Deprecated"
        }
    }

    func includes(_ broker: DataBroker) -> Bool {
        switch self {
        case .all: return true
        case .active: return broker.removedAt == nil
        case .deprecated: return broker.removedAt != nil
        }
    }
}

private struct DebugEventRowView: View {
    let event: DebugEventRow
    let isSelected: Bool
    let listWidth: CGFloat
    let eventTimeColumnWidth: CGFloat
    let eventProfileQueryColumnWidth: CGFloat
    let eventKindColumnWidth: CGFloat
    let eventSummaryColumnWidth: CGFloat
    let eventDetailsMinWidth: CGFloat
    let historyDateFormatter: DateFormatter
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(historyDateFormatter.string(from: event.timestamp))
                .frame(width: eventTimeColumnWidth, alignment: .leading)
            Text(event.profileQueryLabel)
                .frame(width: eventProfileQueryColumnWidth, alignment: .leading)
            Text(event.kind)
                .frame(width: eventKindColumnWidth, alignment: .leading)
            Text(event.summary)
                .frame(width: eventSummaryColumnWidth, alignment: .leading)
            Text(event.details)
                .lineLimit(10)
                .help(event.details)
                .frame(minWidth: eventDetailsMinWidth,
                       maxWidth: .infinity,
                       alignment: .leading)
        }
        .foregroundColor(isSelected ? Color(NSColor.selectedControlTextColor) : Color.primary)
        .frame(width: listWidth, alignment: .leading)
        .padding(.vertical, 6)
        .background(isSelected ? Color(NSColor.selectedControlColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

private struct NameRow: View {
    @ObservedObject var name: NameUI

    var body: some View {
        HStack(spacing: 12) {
            TextField("First name", text: $name.first)
                .frame(maxWidth: .infinity)
            TextField("Middle", text: $name.middle)
                .frame(minWidth: 120)
            TextField("Last name", text: $name.last)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct AddressRow: View {
    @ObservedObject var address: AddressUI

    var body: some View {
        HStack(spacing: 12) {
            TextField("City", text: $address.city)
                .frame(maxWidth: .infinity)
            TextField("State (two characters format)", text: $address.state)
                .onChange(of: address.state) { newValue in
                    if newValue.count > 2 {
                        address.state = String(newValue.prefix(2))
                    }
                }
                .frame(minWidth: 180)
        }
    }
}

extension NameUI: Identifiable {}
extension AddressUI: Identifiable {}
