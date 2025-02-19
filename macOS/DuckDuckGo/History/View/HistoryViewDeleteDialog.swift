//
//  HistoryViewDeleteDialog.swift
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

import SwiftUIExtensions

final class HistoryViewDeleteDialogModel: ObservableObject {
    enum Response {
        case unknown, noAction, delete, burn
    }
    let entriesCount: Int
    @Published var shouldBurn: Bool = true
    @Published private(set) var response: Response = .unknown

    init(entriesCount: Int) {
        self.entriesCount = entriesCount
    }

    func cancel() {
        response = .noAction
    }

    func delete() {
        response = shouldBurn ? .burn : .delete
    }
}

struct HistoryViewDeleteDialog: ModalView {

    @ObservedObject var model: HistoryViewDeleteDialogModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(.historyBurn)

            VStack(spacing: 12) {
                Text("Delete history?").font(.title3)
                Text("Do you want to delete \(model.entriesCount) history items?").font(.body)
                    VStack(spacing: 8) {
                        Toggle("Also delete cookies and site data", isOn: $model.shouldBurn)
                            .lineLimit(nil)
                            .toggleStyle(.checkbox)
                        Text("This will log you out of these sites, reset site preferences, and remove saved sessions. Fireproof site cookies and data won’t be deleted.")
                            .fixMultilineScrollableText()
                            .foregroundColor(.blackWhite60)
                            .frame(width: 242)
                    }
                    .padding(.init(top: 16, leading: 12, bottom: 8, trailing: 12))
                    .background(RoundedRectangle(cornerRadius: 8.0).stroke(.blackWhite5))
            }

            HStack(spacing: 8) {
                Button(UserText.cancel) {
                    model.cancel()
                    dismiss()
                }
                .buttonStyle(StandardButtonStyle())
                .frame(height: 28)

                Button(UserText.delete) {
                    model.delete()
                    dismiss()
                }
                .buttonStyle(DestructiveActionButtonStyle(enabled: true))
                .frame(height: 28)
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}
