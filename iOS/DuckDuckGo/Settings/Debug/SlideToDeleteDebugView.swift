//
//  SlideToDeleteDebugView.swift
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
import DesignResourcesKit

struct SlideToDeleteDebugView: View {
    @AppStorage(SlideToDeleteVariant.preferenceKey) private var variant = SlideToDeleteVariant.basic
    @State private var doubleLength = false
    @State private var previewID = UUID()
    @State private var completed = false

    private var title: String {
        let title = UserText.scopedFireConfirmationSlideToDeleteAll
        return doubleLength ? "\(title) \(title)" : title
    }

    var body: some View {
        List {
            Section {
                Picker("Completion effect", selection: $variant) {
                    ForEach(SlideToDeleteVariant.allCases) { variant in
                        Text(variant.title).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("SlideToDelete.Debug.Variant")
                Text("The selected effect also applies to the Fire confirmation sheet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("Completion effect")
            }

            Section {
                Toggle("Double-length text", isOn: $doubleLength)
                    .accessibilityIdentifier("SlideToDelete.Debug.DoubleLength")
                SlideToDeleteControl(title: title, variant: variant) {
                    completed = true
                }
                .id(previewID)
                .accessibilityIdentifier("SlideToDelete.Debug.Preview")
                .listRowInsets(EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12))
                Text(completed ? "Slide completed. No data deleted." : "Slide to the end, move back, then try again. Release at the end to complete.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("SlideToDelete.Debug.Status")
                Button("Reset Preview", action: resetPreview)
            } header: {
                Text("Safe preview")
            } footer: {
                Text("No tabs or site data are deleted here. On a device, a haptic plays each time you cross the completion threshold. Reduce Motion uses a static completion effect.")
            }
        }
        .navigationTitle("Swipe to Delete")
        .onChange(of: variant) { _ in resetPreview() }
        .onChange(of: doubleLength) { _ in resetPreview() }
    }

    private func resetPreview() {
        completed = false
        previewID = UUID()
    }
}
