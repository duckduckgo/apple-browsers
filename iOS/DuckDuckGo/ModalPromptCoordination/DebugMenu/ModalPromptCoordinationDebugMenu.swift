//
//  ModalPromptCoordinationDebugMenu.swift
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
import Persistence
import class Common.EventMapping

struct ModalPromptCoordinationDebugView: View {
    @StateObject private var viewModel: ModalPromptCoordinationDebugViewModel

    init(keyValueStore: ThrowingKeyValueStoring) {
        let store = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStore, eventMapper: .init(mapping: { _, _, _, _ in }))
        self._viewModel = StateObject(wrappedValue: ModalPromptCoordinationDebugViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Text(viewModel.formattedCooldownPeriod)
                if viewModel.isCooldownPeriodActive {
                    Button("Reset Cooldown") {
                        viewModel.resetCoolDownPeriod()
                    }
                }
            } header: {
                Text(verbatim: "Prompt Cooldown")
            } footer: {
                if viewModel.isCooldownPeriodActive {
                    Text(verbatim: "Reset Cooldown period to allow modal prompt to show again.")
                        .foregroundColor(.red)
                }
            }
        }
    }
}

private final class ModalPromptCoordinationDebugViewModel: ObservableObject {
    private let store: PromptCooldownStore

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return formatter
    }()

    @Published private(set) var isCooldownPeriodActive: Bool = false
    @Published private(set) var formattedCooldownPeriod: String = ""

    init(store: PromptCooldownStore) {
        self.store = store
        updateUI()
    }

    func resetCoolDownPeriod() {
        store.lastPresentationTimestamp = nil
        updateUI()
    }

    private func updateUI() {
        isCooldownPeriodActive = isCooldownActive()
        formattedCooldownPeriod = makeFormattedCooldownPeriod()
    }

    private func isCooldownActive() -> Bool {
        store.lastPresentationTimestamp != nil
    }

    private func makeFormattedCooldownPeriod() -> String {
        guard let timestamp = store.lastPresentationTimestamp else {
            return "No Prompt Cooldown active."
        }

        let lastTimeStampDate = Date(timeIntervalSince1970: timestamp)
        return "Modal Prompt shown \(Self.dateFormatter.string(from: lastTimeStampDate))."
    }
}
