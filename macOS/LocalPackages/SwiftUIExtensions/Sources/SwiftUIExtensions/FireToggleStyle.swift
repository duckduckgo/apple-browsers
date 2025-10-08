//
//  FireToggleStyle.swift
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

public struct FireToggleStyle: ToggleStyle {
    private let onFill: Color
    private let offFill: Color
    private let knobFill: Color

    public init(onFill: Color = Color(NSColor.controlAccentColor),
                offFill: Color = Color(NSColor.disabledControlTextColor),
                knobFill: Color) {
        self.onFill = onFill
        self.offFill = offFill
        self.knobFill = knobFill
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            ToggleSwitch(isOn: configuration.$isOn, onFill: onFill, offFill: offFill, knobFill: knobFill)
        }
    }

    struct ToggleSwitch: View {
        @Binding var isOn: Bool
        let onFill: Color
        let offFill: Color
        let knobFill: Color

        var body: some View {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? onFill : offFill)
                Circle()
                    .fill(knobFill)
                    .shadow(color: .black.opacity(0.15), radius: 0.25, x: 0, y: 0.25)
                    .frame(width: 12, height: 12)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
            }
            .frame(width: 26, height: 15)
            .contentShape(RoundedRectangle(cornerRadius: 6.5))
            .onTapGesture { isOn.toggle() }
            .animation(.easeInOut(duration: 0.12), value: isOn)
        }
    }
}

public extension Toggle where Label == Text {
    init(isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(verbatim: "") }
    }
}
