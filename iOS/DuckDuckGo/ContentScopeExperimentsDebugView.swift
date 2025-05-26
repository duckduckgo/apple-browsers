//
//  ContentScopeExperimentsDebugView.swift
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
import BrowserServicesKit

public struct ContentScopeExperimentsDebugView: View {
    @StateObject private var viewModel = ContentScopeExperimentsDebugViewModel()
    
    public init() {}
    
    private func copyContentToClipboard() {
        var content = "ContentScope Experiments:\n\n"
        for (key, value) in viewModel.activeExperiments.sorted(by: { $0.key < $1.key }) {
            content += "Subfeature: \(key)\n"
            content += "Feature: \(value.parentID)\n"
            content += "Cohort: \(value.cohortID)\n"
            content += "Enrolled: \(value.enrollmentDate.formatted())\n\n"
        }
        UIPasteboard.general.string = content
    }
    
    public var body: some View {
        List {
            ForEach(Array(viewModel.activeExperiments.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subfeature: \(key)")
                        .font(.headline)
                    Text("Feature: \(value.parentID)")
                        .font(.subheadline)
                    Text("Cohort: \(value.cohortID)")
                        .font(.body)
                    Text("Enrolled: \(value.enrollmentDate.formatted())")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Active ContentScope Experiments")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: copyContentToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
}

class ContentScopeExperimentsDebugViewModel: ObservableObject {
    @Published var activeExperiments: Experiments = [:]
    
    init() {
        let experimentsManager = AppDependencyProvider.shared.contentScopeExperimentsManager
        activeExperiments = experimentsManager.allActiveContentScopeExperiments
    }
}
