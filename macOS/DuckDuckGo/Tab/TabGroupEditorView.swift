//
//  TabGroupEditorView.swift
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

struct TabGroupEditorView: View {

    enum Mode {
        case create
        case edit(TabGroup)

        var title: String {
            switch self {
            case .create: return "New Tab Group"
            case .edit: return "Edit Tab Group"
            }
        }

        var confirmButtonTitle: String {
            switch self {
            case .create: return "Create"
            case .edit: return "Save"
            }
        }
    }

    let mode: Mode
    let onSave: (String, TabGroupColor) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var selectedColor: TabGroupColor

    init(mode: Mode,
         onSave: @escaping (String, TabGroupColor) -> Void,
         onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedColor = State(initialValue: .blue)
        case .edit(let group):
            _name = State(initialValue: group.name)
            _selectedColor = State(initialValue: group.color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(mode.title)
                .font(.headline)
                .padding(.top, 10)

            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Enter group name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(TabGroupColor.allCases, id: \.self) { color in
                        ColorDotButton(
                            color: color,
                            isSelected: color == selectedColor,
                            action: { selectedColor = color }
                        )
                    }
                }
            }

            Divider()
                .padding(.top, 8)

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(mode.confirmButtonTitle) {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), selectedColor)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 10)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .frame(width: 280)
    }
}

// MARK: - Color Dot Button

private struct ColorDotButton: View {
    let color: TabGroupColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(color.nsColor))
                    .frame(width: 24, height: 24)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .frame(width: 30, height: 30)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.rawValue.capitalized)
    }
}

#Preview("Create Mode") {
    TabGroupEditorView(
        mode: .create,
        onSave: { _, _ in },
        onCancel: {}
    )
}

#Preview("Edit Mode") {
    TabGroupEditorView(
        mode: .edit(TabGroup(name: "Work", color: .blue)),
        onSave: { _, _ in },
        onCancel: {}
    )
}
