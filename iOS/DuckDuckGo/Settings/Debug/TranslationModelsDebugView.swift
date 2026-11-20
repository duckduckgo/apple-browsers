//
//  TranslationModelsDebugView.swift
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

import SwiftUI
import WebPageTranslation

/// Lists the pairs in the translation manifest and downloads or deletes their models.
struct TranslationModelsDebugView: View {

    @StateObject private var viewModel: TranslationModelsDebugViewModel

    init(models: TranslationModels?, capability: WebPageTranslationCapable) {
        _viewModel = StateObject(wrappedValue: TranslationModelsDebugViewModel(models: models, capability: capability))
    }

    var body: some View {
        List {
            if !viewModel.isAvailable {
                Text(verbatim: "Web page translation is off. Turn on pageTranslation in Feature Flags and relaunch.")
            } else if viewModel.rows.isEmpty {
                Text(verbatim: "No manifest. Tap Refresh.")
            } else {
                ForEach(viewModel.rows) { row in
                    rowView(row)
                }
            }
        }
        .navigationTitle(Text(verbatim: "Translation Models"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Text(verbatim: "Refresh")
                }
                .disabled(!viewModel.isAvailable)
            }
        }
    }

    private func rowView(_ row: TranslationModelsDebugViewModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: row.id).font(.headline)
                    Text(verbatim: row.size).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                statusView(row)
            }
            if case .failed(let message) = row.status {
                Text(verbatim: message).font(.caption).foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private func statusView(_ row: TranslationModelsDebugViewModel.Row) -> some View {
        switch row.status {
        case .notInstalled, .failed:
            Button {
                viewModel.download(row.id)
            } label: {
                Text(verbatim: "Download")
            }
            .buttonStyle(.borderless)
        case .downloading(let progress):
            HStack {
                SwiftUI.ProgressView(value: progress).frame(width: 80)
                Text(verbatim: "\(Int(progress * 100))%").font(.caption).monospacedDigit()
            }
        case .installed(let version):
            HStack {
                Text(verbatim: "Installed \(version)").font(.caption)
                Button(role: .destructive) {
                    viewModel.delete(row.id)
                } label: {
                    Text(verbatim: "Delete")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

@MainActor
final class TranslationModelsDebugViewModel: ObservableObject {

    struct Row: Identifiable {
        let id: String
        let size: String
        var status: Status
    }

    enum Status {
        case notInstalled
        case downloading(Double)
        case installed(version: String)
        case failed(String)
    }

    @Published private(set) var rows: [Row] = []
    let isAvailable: Bool

    private let models: TranslationModels?
    /// Downloads in progress and failures; everything else comes from the manifest and the installed bundles.
    private var transientStatuses: [String: Status] = [:]

    init(models: TranslationModels?, capability: WebPageTranslationCapable) {
        self.models = models
        isAvailable = capability.isWebPageTranslationEnabled && models != nil
        rebuildRows()
    }

    func refresh() async {
        _ = await models?.refreshManifest()
        rebuildRows()
    }

    func download(_ pairID: String) {
        guard let models else {
            return
        }

        setStatus(.downloading(0), for: pairID)
        Task {
            do {
                for try await progress in models.install(pairID) {
                    setStatus(.downloading(progress), for: pairID)
                }
                transientStatuses[pairID] = nil
            } catch {
                transientStatuses[pairID] = .failed(String(describing: error))
            }
            rebuildRows()
        }
    }

    func delete(_ pairID: String) {
        do {
            try models?.delete(pairID)
            transientStatuses[pairID] = nil
        } catch {
            transientStatuses[pairID] = .failed(String(describing: error))
        }
        rebuildRows()
    }

    /// Updates one row in place, so progress ticks don't re-read the manifest and the models folder.
    private func setStatus(_ status: Status, for pairID: String) {
        transientStatuses[pairID] = status
        guard let index = rows.firstIndex(where: { $0.id == pairID }) else {
            return
        }

        rows[index].status = status
    }

    private func rebuildRows() {
        guard isAvailable, let models, let manifest = models.manifest else {
            rows = []
            return
        }

        var installedVersions: [String: String] = [:]
        for bundle in models.installed() {
            installedVersions[bundle.id] = bundle.version
        }

        rows = manifest.models.keys.sorted().map { pairID in
            let size = ByteCountFormatter.string(fromByteCount: manifest.models[pairID]?.totalBytes ?? 0, countStyle: .file)
            return Row(id: pairID, size: size, status: status(for: pairID, installedVersion: installedVersions[pairID]))
        }
    }

    private func status(for pairID: String, installedVersion: String?) -> Status {
        if let transient = transientStatuses[pairID] {
            return transient
        }

        if let installedVersion {
            return .installed(version: installedVersion)
        }

        return .notInstalled
    }
}
