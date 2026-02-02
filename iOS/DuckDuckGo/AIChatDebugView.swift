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

            Section(header: Text("Contextual Onboarding")) {
                Button("Reset Context Sheet Onboarding") {
                    viewModel.resetContextualOnboarding()
                }
                .foregroundColor(.red)
            }

            Section(header: Text("Contextual Session Timer"),
                    footer: Text(viewModel.sessionTimerDescription)) {
                ForEach(viewModel.sessionTimerPresets, id: \.seconds) { preset in
                    Button {
                        viewModel.setSessionTimer(seconds: preset.seconds)
                    } label: {
                        HStack {
                            Text(preset.label)
                            Spacer()
                            if viewModel.contextualSessionTimerSeconds == preset.seconds {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }

                NavigationLink(destination: AIChatDebugSessionTimerEntryView(viewModel: viewModel)) {
                    HStack {
                        Text("Custom Duration")
                        Spacer()
                        if let seconds = viewModel.contextualSessionTimerSeconds,
                           !viewModel.sessionTimerPresets.contains(where: { $0.seconds == seconds }) {
                            Text("\(seconds)s")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Reset to Default") {
                    viewModel.resetSessionTimer()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("AI Chat")
    }
}

private final class AIChatDebugViewModel: ObservableObject {
    private var debugSettings = AIChatDebugSettings()
    private var aiChatSettings = AIChatSettings()

    struct SessionTimerPreset {
        let label: String
        let seconds: Int
    }

    let sessionTimerPresets = [
        SessionTimerPreset(label: "30 seconds", seconds: 30),
        SessionTimerPreset(label: "1 minute", seconds: 60),
        SessionTimerPreset(label: "5 minutes", seconds: 300),
        SessionTimerPreset(label: "10 minutes", seconds: 600)
    ]

    @Published var enteredHostname: String {
        didSet {
            debugSettings.messagePolicyHostname = enteredHostname
        }
    }

    @Published var customURL: String {
        didSet {
            debugSettings.customURL = customURL.isEmpty ? nil : customURL
            if customURL.isEmpty {
                enteredHostname = ""
            } else if let url = URL(string: customURL), let host = url.host {
                enteredHostname = host
            }
        }
    }

    @Published var contextualSessionTimerSeconds: Int? {
        didSet {
            debugSettings.contextualSessionTimerSeconds = contextualSessionTimerSeconds
        }
    }

    var sessionTimerDescription: String {
        if let seconds = contextualSessionTimerSeconds {
            return "Current: \(seconds) seconds (\(formatDuration(seconds)))"
        } else {
            return "Current: Default (from privacy config)"
        }
    }

    init() {
        self.enteredHostname = debugSettings.messagePolicyHostname ?? ""
        self.customURL = debugSettings.customURL ?? ""
        self.contextualSessionTimerSeconds = debugSettings.contextualSessionTimerSeconds
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
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

    func resetContextualOnboarding() {
        aiChatSettings.resetContextualOnboarding()
    }

    func setSessionTimer(seconds: Int) {
        contextualSessionTimerSeconds = seconds
    }

    func resetSessionTimer() {
        contextualSessionTimerSeconds = nil
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
        if string.isEmpty { return true }
        return URL(string: string) != nil && (string.hasPrefix("http://") || string.hasPrefix("https://"))
    }
}

private struct AIChatDebugSessionTimerEntryView: View {
    @ObservedObject var viewModel: AIChatDebugViewModel
    @State private var secondsText: String = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Form {
            Section(header: Text("Custom Session Timer Duration"),
                    footer: Text("Enter duration in seconds. Examples: 30, 60, 300")) {
                TextField("Seconds", text: $secondsText)
                    .keyboardType(.numberPad)
            }

            Section {
                Button {
                    if let seconds = Int(secondsText), seconds > 0 {
                        viewModel.setSessionTimer(seconds: seconds)
                        presentationMode.wrappedValue.dismiss()
                    }
                } label: {
                    Text("Save")
                }
                .disabled(Int(secondsText) == nil || Int(secondsText)! <= 0)

                Button {
                    viewModel.resetSessionTimer()
                    secondsText = ""
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Reset to Default")
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Custom Timer Duration")
        .onAppear {
            if let seconds = viewModel.contextualSessionTimerSeconds {
                secondsText = "\(seconds)"
            }
        }
    }
}

#Preview {
    AIChatDebugView()
}
