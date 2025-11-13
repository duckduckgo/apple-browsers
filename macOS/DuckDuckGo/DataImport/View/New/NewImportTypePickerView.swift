//
//  NewImportTypePickerView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKit

struct NewImportTypePickerView: View {

    @Binding var items: [ImportTypeItem]
    let doneAction: () -> Void
    let cancelAction: () -> Void
    @Binding var isDoneDisabled: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.importSelectedDataTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.top, 20)
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let item = $items[index]
                    HStack(alignment: .center) {
                        Text(item.wrappedValue.dataType.displayName)
                        Spacer()
                        Toggle(isOn: item.isSelected).toggleStyle(.switch)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 10)

                    if index < items.count - 1 {
                        Divider()
                            .foregroundColor(.secondary)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(designSystemColor: .surfacePrimary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(.blackWhite10), lineWidth: 1)
            )

            HStack {
                Spacer()
                // Hidden “Cancel” target so hitting Esc sets the flag before dismiss
                Button("") {
                    cancelAction()
                }
                .keyboardShortcut(.cancelAction)  // Esc
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                Button(UserText.done) {
                    doneAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDoneDisabled)
            }
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 388, maxHeight: .infinity)
    }
}
