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

struct DataBrokerRunCustomJSONView: View {
    @ObservedObject var viewModel: DataBrokerRunCustomJSONViewModel

    @State private var jsonText: String = ""
    @State private var selectedResultId: UUID?
    private let maxNames = 3
    private let maxAddresses = 5
    private let brokerConfigWidth: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            TabView {
                contentContainer(scanView)
                    .tabItem {
                        Text("Scan")
                    }

                contentContainer(resultsView)
                    .tabItem {
                        Text("Extracted Profiles")
                    }
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
            Button("Run") {
                viewModel.runJSON(jsonString: jsonText)
            }

            if viewModel.isRunningOnAllBrokers {
                ProgressView("Scanning...")
            } else {
                Button("Run all brokers") {
                    viewModel.runAllBrokers()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var brokerConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Broker Config")
                .font(.headline)

            Divider()

            List(viewModel.brokers.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }), id: \.name) { broker in
                Text(broker.name)
                    .onTapGesture {
                        jsonText = broker.toJSONString()
                    }
            }
            .frame(maxHeight: .infinity)
            .listStyle(.plain)

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
            Text("Extracted Profiles")
                .font(.headline)

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
            .frame(maxHeight: 320)
            .listStyle(.plain)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let selectedResult = selectedResult {
                    Text(selectedResult.extractedProfile.name ?? "No name")
                        .font(.headline)
                    Text(selectedResult.extractedProfile.addresses?.map { $0.fullAddress }.joined(separator: ", ") ?? "No address")
                    Text(selectedResult.extractedProfile.relatives?.joined(separator: ", ") ?? "No relatives")
                        .foregroundColor(.secondary)
                } else {
                    Text("Select a profile to view details.")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary, lineWidth: 1)
                .frame(maxWidth: .infinity, minHeight: 240)
                .overlay(
                    Text("Web view")
                        .foregroundColor(.secondary)
                )

            Divider()

            Button("Clear and go back") {
                viewModel.results.removeAll()
                selectedResultId = nil
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedResult: ScanResult? {
        guard let selectedResultId else { return nil }
        return viewModel.results.first { $0.id == selectedResultId }
    }

    private func contentContainer<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
