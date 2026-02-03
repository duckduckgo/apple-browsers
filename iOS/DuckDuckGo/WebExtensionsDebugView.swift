//
//  WebExtensionsDebugView.swift
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
import WebExtensions
import UniformTypeIdentifiers

@available(iOS 18.4, *)
struct WebExtensionsDebugView: View {

    let webExtensionManager: WebExtensionManaging

    @State private var installedExtensions: [InstalledExtension] = []
    @State private var showDocumentPicker = false
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Install from Files...", systemImage: "folder")
                }
            } header: {
                Text("Install Extension")
            }

            Section {
                if isLoading {
                    SwiftUI.ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if installedExtensions.isEmpty {
                    Text("No extensions installed")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedExtensions) { installedExtension in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(installedExtension.name)
                                    .font(.body)
                                Text(installedExtension.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                    }
                    .onDelete(perform: uninstallExtensions)
                }
            } header: {
                Text("Installed Extensions (\(installedExtensions.count))")
            }

            if !installedExtensions.isEmpty {
                Section {
                    Button(role: .destructive) {
                        uninstallAllExtensions()
                    } label: {
                        Label("Uninstall All Extensions", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Web Extensions")
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                Task {
                    await installExtension(from: url)
                }
            }
        }
        .onAppear {
            refreshExtensions()
        }
        .refreshable {
            refreshExtensions()
        }
    }

    private func refreshExtensions() {
        isLoading = true
        let paths = webExtensionManager.webExtensionPaths
        installedExtensions = paths.map { path in
            let name = webExtensionManager.extensionName(from: path) ?? "Unknown Extension"
            return InstalledExtension(path: path, name: name)
        }
        isLoading = false
    }

    private func installExtension(from url: URL) async {
        isLoading = true
        await webExtensionManager.installExtension(path: url.absoluteString)
        refreshExtensions()
    }

    private func uninstallExtensions(at offsets: IndexSet) {
        for index in offsets {
            let installedExtension = installedExtensions[index]
            try? webExtensionManager.uninstallExtension(path: installedExtension.path)
        }
        refreshExtensions()
    }

    private func uninstallAllExtensions() {
        webExtensionManager.uninstallAllExtensions()
        refreshExtensions()
    }
}

@available(iOS 18.4, *)
struct InstalledExtension: Identifiable {
    let id = UUID()
    let path: String
    let name: String
}

@available(iOS 18.4, *)
struct DocumentPickerView: UIViewControllerRepresentable {

    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .zip])
        picker.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelect(url)
        }
    }
}
