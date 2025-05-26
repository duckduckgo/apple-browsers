//
//  AIChatInputBox.swift
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
import UIKit

struct AIChatInputBox: View {
    @ObservedObject var viewModel: AIChatInputBoxViewModel

    @State private var text = ""
    @State private var textHeight: CGFloat = 40
    @State private var showingDeleteConfirmation = false

    private var isSendButtonDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .waitingForGeneration:
                stopGeneratingButton
            case .unknown:
                EmptyView()
            default:
                VStack {
                    inputViews
                    Spacer()
                }
                .opacity(viewModel.visibility == .hidden ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: viewModel.visibility == .hidden ? .clear : .secondarySystemBackground))
    }

    // MARK: - Subviews

    private var inputViews: some View {
        VStack {
            if viewModel.focusState == .focused {
                pickerView
                    .padding(.horizontal)
                    .padding(.top)
            }
            HStack {
                if viewModel.focusState == .focused {
                    selectedBarView
                } else {
                    unselectedBarView
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(viewModel.focusState == .focused ? Color.blue : Color.clear, lineWidth: 2)
            )
            .padding()
        }
    }

    private var unselectedBarView: some View {
        HStack {
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "flame")
                    .foregroundColor(.red)
            }
            .confirmationDialog(
                "Delete this chat?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Chat", role: .destructive) {
                    viewModel.fireButtonPressed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this chat? This cannot be undone.")
            }
            Text("Ask anything...")
                .foregroundColor(Color(uiColor: .secondaryLabel))
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    withAnimation {
                        viewModel.focusState = .focused
                    }
                }
            Spacer()
            Button {
                newChatPressed()
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundColor(Color(uiColor: .label))
            }
        }
    }

    private var pickerView: some View {
        HStack(alignment: .center) {
            Button {
                viewModel.focusState = .unfocused
                viewModel.didPressBackButton.send()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)


            Spacer()

            Picker("", selection: $viewModel.inputMode) {
                ForEach(AIChatInputBoxViewModel.InputMode.allCases) { mode in
                    Text(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()
        }
        .padding(.trailing)
    }

    private var selectedBarView: some View {
        VStack {
            BrowserToggleInputView(viewModel: viewModel) {
                submitText()
            }
        }
    }

    private var stopGeneratingButton: some View {

        Button(action: viewModel.stopGenerating) {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 20, weight: .medium))
                Text("Stop generating...")
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding()
    }

    // MARK: - Actions

    private func submitText() {
        viewModel.focusState = .unfocused
        viewModel.submitText(viewModel.inputText)
        viewModel.clearText()
    }

    private func newChatPressed() {
        viewModel.newChatButtonPressed()
        withAnimation {
            viewModel.focusState = .focused
        }
    }
}

struct AIChatInputBox_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            AIChatInputBox(viewModel: AIChatInputBoxViewModel())
        }
    }
}
