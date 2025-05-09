//
//  DebugSaveProfileView.swift
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

public struct DebugSaveProfileView: View {

    @ObservedObject var viewModel: DebugSaveProfileViewModel

    public var body: some View {
        VStack(alignment: .leading) {
            ForEach(viewModel.names.indices, id: \.self) { index in
                HStack {
                    TextField("First name", text: $viewModel.names[index].first)
                        .padding()
                    TextField("Middle", text: $viewModel.names[index].middle)
                        .padding()
                    TextField("Last name", text: $viewModel.names[index].last)
                        .padding()
                }
            }

            Button("Add other name") {
                viewModel.names.append(.empty())
            }

            Divider()

            ForEach(viewModel.addresses.indices, id: \.self) { index in
                HStack {
                    TextField("City", text: $viewModel.addresses[index].city)
                        .padding()
                    TextField("State (two characters format)", text: $viewModel.addresses[index].state)
                        .onChange(of: viewModel.addresses[index].state) { newValue in
                            if newValue.count > 2 {
                                viewModel.addresses[index].state = String(newValue.prefix(2))
                            }
                        }
                        .padding()
                }
            }

            Button("Add other address") {
                viewModel.addresses.append(.empty())
            }

            Divider()

            HStack {
                TextField("Birth year (YYYY)", text: $viewModel.birthYear)
                    .padding()
            }

            Divider()

            Button("Save") {
                viewModel.saveProfile()
            }
        }
        .padding()
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text(viewModel.alert?.title ?? "-"),
                  message: Text(viewModel.alert?.description ?? "-"),
                  dismissButton: .default(Text("OK"), action: { viewModel.showAlert = false })
            )
        }
    }
}
