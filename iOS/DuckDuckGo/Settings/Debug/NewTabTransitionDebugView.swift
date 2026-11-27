//
//  NewTabTransitionDebugView.swift
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

struct NewTabTransitionDebugView: View {

    typealias Origin = NewTabTransitionTuning.Origin

    @StateObject private var store = NewTabTransitionConfigurationStore()
    @State private var editedOrigin = Origin.rightOfCenter

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $store.configuration.isEnabled)
                Toggle("Slow motion (4×)", isOn: $store.configuration.isSlowMotion)
                Toggle("Spring instead of curve", isOn: $store.configuration.usesSpring)
                Toggle("Tab manager stays still", isOn: $store.configuration.tabManagerStaysStill)
                Picker("Old keyboard", selection: $store.configuration.oldKeyboard) {
                    ForEach(NewTabTransitionTuning.OldKeyboard.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                originPicker("Toolbar +, menus, links", selection: $store.configuration.inTabOrigin)
                originPicker("Tab manager +", selection: $store.configuration.tabManagerOrigin)
            } header: {
                Text(verbatim: "Where the new page starts")
            }

            Section {
                Picker("Edit", selection: $editedOrigin) {
                    ForEach(Origin.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                MotionSliders(motion: motionBinding(for: editedOrigin), origin: editedOrigin)
            } header: {
                Text(verbatim: "Motion")
            }

            Section {
                Toggle("Rounded corners", isOn: $store.configuration.roundsCorners)
                ValueSlider(title: "Corner radius", value: $store.configuration.cornerRadius,
                              range: 0...70, step: 1, format: { "\(Int($0)) pt" })
                Toggle("Fade in new page", isOn: $store.configuration.fadesInNewPage)
            }

            Section {
                Button("Reset to design defaults", role: .destructive) {
                    store.reset()
                }
            }
        }
        .navigationTitle("New Tab Transition")
    }

    private func originPicker(_ title: String, selection: Binding<Origin>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Origin.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }

    private func motionBinding(for origin: Origin) -> Binding<NewTabTransitionTuning.Motion> {
        switch origin {
        case .rightOfCenter: return $store.configuration.rightOfCenter
        case .belowCenter: return $store.configuration.belowCenter
        }
    }
}

private struct MotionSliders: View {

    @Binding var motion: NewTabTransitionTuning.Motion
    let origin: NewTabTransitionTuning.Origin

    var body: some View {
        ValueSlider(title: "New page start size", value: $motion.startScale, range: 0.4...1, format: Self.percent)
        ValueSlider(title: offsetTitle, value: $motion.offset, range: offsetRange, format: Self.percent)
        ValueSlider(title: "Old page scales back to", value: $motion.oldPageScale, range: 0.75...1, format: Self.percent)
        if origin == .rightOfCenter {
            ValueSlider(title: "Old page drifts left", value: $motion.oldPageDrift, range: 0...0.3, format: Self.percent)
        }
        ValueSlider(title: "Old page dims by", value: $motion.dimming, range: 0...1, format: Self.percent)
        ValueSlider(title: "Duration", value: durationBinding, range: 150...900, step: 10, format: { "\(Int($0)) ms" })
    }

    private var offsetTitle: String {
        origin == .rightOfCenter ? "Right of center offset" : "Below center offset"
    }

    private var offsetRange: ClosedRange<CGFloat> {
        origin == .rightOfCenter ? 0...0.3 : -0.3...0.5
    }

    private var durationBinding: Binding<CGFloat> {
        Binding(get: { motion.duration * 1000 }, set: { motion.duration = $0 / 1000 })
    }

    private static func percent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct ValueSlider: View {

    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 0.01
    let format: (CGFloat) -> String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundColor(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private extension NewTabTransitionTuning.OldKeyboard {
    var title: String {
        switch self {
        case .leavesInstantly: return "Leaves instantly"
        case .slidesDown: return "Slides down"
        case .staysUp: return "Stays up"
        }
    }
}

private extension NewTabTransitionTuning.Origin {
    var title: String {
        switch self {
        case .rightOfCenter: return "Right of center"
        case .belowCenter: return "Below center"
        }
    }
}
