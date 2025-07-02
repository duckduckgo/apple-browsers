//
//  AIChatDebugView.swift
//  DuckDuckGo
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
import Combine
import AIChat

struct AIChatDebugView: View {
    @StateObject private var viewModel = AIChatDebugViewModel()

    var body: some View {
        List {
            Section(footer: Text("Stored Hostname: \(viewModel.enteredHostname)")) {
                NavigationLink(destination: AIChatDebugHostnameEntryView(viewModel: viewModel)) {
                    Text("Message policy hostname")
                }
            }
            
            Section(footer: Text("Custom URL: \(viewModel.customURL.isEmpty ? "Default" : viewModel.customURL)")) {
                NavigationLink(destination: AIChatDebugURLEntryView(viewModel: viewModel)) {
                    Text("Set Custom AI Chat URL")
                }
                Button("Reset Custom URL") {
                    viewModel.resetCustomURL()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("AI Chat")
    }
}

private final class AIChatDebugViewModel: ObservableObject {
    private var debugSettings = AIChatDebugSettings()

    @Published var enteredHostname: String {
        didSet {
            debugSettings.messagePolicyHostname = enteredHostname
        }
    }

    @Published var customURL: String {
        didSet {
            debugSettings.customURL = customURL.isEmpty ? nil : customURL
            // Update the hostname in the UI when URL changes
            if customURL.isEmpty {
                enteredHostname = ""
            } else if let url = URL(string: customURL), let host = url.host {
                enteredHostname = host
            }
        }
    }

    init() {
        self.enteredHostname = debugSettings.messagePolicyHostname ?? ""
        self.customURL = debugSettings.customURL ?? ""
    }

    func resetHostname() {
        enteredHostname = ""
    }

    func resetCustomURL() {
        customURL = ""
    }

    func resetAll() {
        debugSettings.reset()
        enteredHostname = ""
        customURL = ""
    }
}

private struct AIChatDebugHostnameEntryView: View {
    @ObservedObject var viewModel: AIChatDebugViewModel
    @State private var policyHostname: String = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Form {
            Section {
                TextField("Hostname", text: $policyHostname)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            }
            Button {
                viewModel.enteredHostname = policyHostname
                presentationMode.wrappedValue.dismiss()
            } label: {
                Text("Confirm")
            }

            Button {
                viewModel.resetHostname()
                policyHostname = ""
                presentationMode.wrappedValue.dismiss()
            } label: {
                Text("Reset")
            }
        }
        .navigationTitle("Edit Hostname")
        .onAppear {
            policyHostname = viewModel.enteredHostname
        }
    }
}

private struct AIChatDebugURLEntryView: View {
    @ObservedObject var viewModel: AIChatDebugViewModel
    @State private var customURLText: String = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Form {
            Section(header: Text(verbatim: "Custom AI Chat URL")) {
                TextField("https://duck.ai", text: $customURLText)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            
            Section {
                Button {
                    if isValidURL(customURLText) {
                        viewModel.customURL = customURLText
                        presentationMode.wrappedValue.dismiss()
                    }
                } label: {
                    Text(verbatim: "Save")
                }
                .disabled(!isValidURL(customURLText))

                Button {
                    viewModel.resetCustomURL()
                    customURLText = ""
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text(verbatim: "Reset to Default")
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Custom AI Chat URL")
        .onAppear {
            customURLText = viewModel.customURL
        }
    }
    
    private func isValidURL(_ string: String) -> Bool {
        if string.isEmpty { return true } // Allow empty to reset
        return URL(string: string) != nil && (string.hasPrefix("http://") || string.hasPrefix("https://"))
    }
}

#Preview {
    AIChatDebugView()
}
