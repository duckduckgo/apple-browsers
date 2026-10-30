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
import DesignResourcesKitIcons

struct SlideToDeleteDebugView: View {
    @AppStorage(SlideToDeleteVariant.preferenceKey) private var variant = SlideToDeleteVariant.defaultValue
    @AppStorage(SlideToDeleteStyle.preferenceKey) private var style = SlideToDeleteStyle.defaultValue
    @State private var doubleLength = false
    @State private var previewID = UUID()
    @State private var completed = false
    @State private var hapticRequests = 0
    @State private var touchRequests = 0
    @State private var labelReveals = 0
    @StateObject private var feedback = SlideToDeleteFeedback()

    private var title: String {
        let title = UserText.scopedFireConfirmationSlideToDeleteAll
        return doubleLength ? "\(title) \(title)" : title
    }

    var body: some View {
        List {
            Section {
                ForEach(SlideToDeleteStyle.allCases) { option in
                    let available = option != .glass || SlideToDeleteStyle.isGlassAvailable
                    Button {
                        style = option
                    } label: {
                        HStack {
                            Text(verbatim: option.title)
                                .foregroundColor(Color(designSystemColor: available ? .textPrimary : .textSecondary))
                            Spacer()
                            if option == style.resolved(isGlassAvailable: SlideToDeleteStyle.isGlassAvailable) {
                                Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSmall)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(!available)
                    .accessibilityIdentifier("SlideToDelete.Debug.Style.\(option.rawValue)")
                    .accessibilityAddTraits(option == style.resolved(isGlassAvailable: SlideToDeleteStyle.isGlassAvailable) ? .isSelected : [])
                }
            } header: {
                Text(verbatim: "Slider style")
            } footer: {
                Text(verbatim: SlideToDeleteStyle.isGlassAvailable
                     ? "The selected style also applies to the Fire confirmation sheet."
                     : "Liquid Glass requires iOS 26 or later. Original is used on this device.")
                    .accessibilityIdentifier("SlideToDelete.Debug.StyleAvailability")
            }

            Section {
                Picker(selection: $variant) {
                    ForEach(SlideToDeleteVariant.allCases) { variant in
                        Text(verbatim: variant.title).tag(variant)
                    }
                } label: {
                    Text(verbatim: "Completion effect")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("SlideToDelete.Debug.Variant")
                Text(verbatim: "The selected effect also applies to the Fire confirmation sheet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text(verbatim: "Completion effect")
            }

            Section {
                Toggle(isOn: $doubleLength) {
                    Text(verbatim: "Double-length text")
                }
                .accessibilityIdentifier("SlideToDelete.Debug.DoubleLength")
                SlideToDeleteControl(title: title,
                                     variant: variant,
                                     style: style,
                                     onHapticRequest: { hapticRequests += 1 },
                                     onTouchHapticRequest: { touchRequests += 1 },
                                     onCompletionLabelReveal: { labelReveals += 1 }) {
                    completed = true
                }
                .id(previewID)
                .accessibilityIdentifier("SlideToDelete.Debug.Preview")
                .listRowInsets(EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12))
                Text(verbatim: completed ? "Slide completed. No data deleted." : "Slide to the end, move back, then try again. Release at the end to complete.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("SlideToDelete.Debug.Status")
                Text(verbatim: "Haptic requests: \(hapticRequests) · Label reveals: \(labelReveals)")
                    .font(.footnote)
                    .accessibilityIdentifier("SlideToDelete.Debug.Diagnostics")
                Text(verbatim: "Touch requests: \(touchRequests)")
                    .font(.footnote)
                    .accessibilityIdentifier("SlideToDelete.Debug.TouchDiagnostics")
                Button(action: resetPreview) {
                    Text(verbatim: "Reset Preview")
                }
                Button {
                    feedback.prepare()
                    if feedback.impact() {
                        hapticRequests += 1
                    }
                } label: {
                    Text(verbatim: "Test haptic")
                }
                .background(SlideToDeleteFeedbackView(feedback: feedback))
                .accessibilityIdentifier("SlideToDelete.Debug.TestHaptic")
            } header: {
                Text(verbatim: "Safe preview")
            } footer: {
                Text(verbatim: "No data is deleted here. Hold at the end to reveal Shimmer’s label; release to complete immediately. Feel a light tap on touch and a firmer tick near the end. Diagnostics show requests, not vibrations felt. Test on an iPhone with System Haptics and Accessibility > Touch > Vibration enabled.")
            }
        }
        .navigationTitle(Text(verbatim: "Slide to Delete"))
        .onChange(of: variant) { _ in resetPreview() }
        .onChange(of: style) { _ in resetPreview() }
        .onChange(of: doubleLength) { _ in resetPreview() }
    }

    private func resetPreview() {
        completed = false
        hapticRequests = 0
        touchRequests = 0
        labelReveals = 0
        previewID = UUID()
    }
}
