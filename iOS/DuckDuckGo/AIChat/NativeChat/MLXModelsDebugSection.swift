//
//  MLXModelsDebugSection.swift
//  DuckDuckGo
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

import Combine
import DuckAIChatMLX
import SwiftUI

/// Demo branch: pick the MLX model the native chat uses, and download or delete each one.
struct MLXModelsDebugSection: View {
    @State private var states: [String: ModelState] = [:]
    @State private var refresh = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var store: ModelStore { NativeChatProviderFactory.modelStore }

    var body: some View {
        Section {
            ForEach(ModelCatalog.all) { model in
                row(for: model)
            }
        } header: {
            Text("MLX models")
        } footer: {
            Text("Download a model to use it for a job. Fits this device: \(NativeChatProviderFactory.recommendedMLXModel.displayName).")
        }
        .onReceive(refresh) { _ in states = store.states }
        .onAppear { states = store.states }
    }

    private func row(for model: Model) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                Text(detail(for: model)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            action(for: model)
        }
    }

    private func detail(for model: Model) -> String {
        let fits = ModelCatalog.fits(model, physicalMemory: ProcessInfo.processInfo.physicalMemory) ? "" : " · needs \(model.minimumPhysicalMemoryGB) GB"
        switch states[model.id] ?? store.state(of: model) {
        case .notDownloaded:
            return "\(ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file)) · not downloaded\(fits)"
        case .downloading(let fraction, _, _):
            return "Downloading \(Int(fraction * 100))%"
        case .downloaded(let bytes):
            return "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · on device\(fits)"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    @ViewBuilder
    private func action(for model: Model) -> some View {
        switch states[model.id] ?? store.state(of: model) {
        case .notDownloaded, .failed:
            Button("Get") { Task { try? await store.download(model) } }
                .disabled(store.isDownloading)
        case .downloading:
            Button("Cancel") { store.cancelDownload() }
        case .downloaded:
            Button("Delete", role: .destructive) { Task { await store.delete(model) } }
        }
    }
}
