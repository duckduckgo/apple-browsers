//
//  WebViewStateRestorationDebugView.swift
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
import AIChat

struct WebViewStateRestorationDebugView: View {
    @StateObject private var viewModel = WebViewStateRestorationDebugViewModel()

    var body: some View {
        List {
            Section {
                ForEach(viewModel.allFiles, id: \.self) { file in
                    Text(verbatim: file.lastPathComponent)
                }
            } header: {
                Text(verbatim: "All cache files")
            } footer: {
                if !viewModel.allFiles.isEmpty {
                    Button {
                        viewModel.clearCache()
                    } label: {
                        Text(verbatim: "Delete all cache files")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle(Text(verbatim: "WebView State Restoration"))
    }
}

private final class WebViewStateRestorationDebugViewModel: ObservableObject {
    private let interactionStateSource = TabInteractionStateDiskSource()

    @Published private(set) var allFiles: [URL]

    init() {
        allFiles = (try? interactionStateSource?.allCacheFiles()) ?? []
    }

    func clearCache() {
        interactionStateSource?.removeAll(excluding: [])
        allFiles = (try? interactionStateSource?.allCacheFiles()) ?? []
    }
}
