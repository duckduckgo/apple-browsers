//
//  SafariPerformanceTestWindowView.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

struct SafariPerformanceTestWindowView: View {
    @ObservedObject var viewModel: SafariPerformanceTestViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let resultsPath = viewModel.resultsFilePath {
                completionView(resultsPath: resultsPath)
            } else if viewModel.isRunning {
                progressView
            } else {
                startView
            }
        }
        .frame(width: 600, height: 400)
        .alert(item: Binding(
            get: { viewModel.errorMessage.map { ErrorWrapper(message: $0) } },
            set: { viewModel.errorMessage = $0?.message }
        )) { error in
            Alert(
                title: Text("Test Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gauge.high")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Safari Performance Test")
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let url = viewModel.currentURL {
                VStack(spacing: 8) {
                    Text("Testing")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(url.host ?? url.absoluteString)
                        .font(.system(.title2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                }
                .multilineTextAlignment(.center)
                .padding(.top)
            }

            VStack(spacing: 12) {
                Text("Test Configuration")
                    .font(.headline)

                Picker("Iterations", selection: $viewModel.selectedIterations) {
                    ForEach([1, 3, 5, 10, 20], id: \.self) { count in
                        Text("\(count) iterations").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            .padding(.top)

            Button(action: {
                Task {
                    await viewModel.runTest()
                }
            }) {
                Label("Start Test", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.currentURL == nil)

            Spacer()
        }
        .padding()
        .padding(.horizontal, 40)
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 20) {
            Text("Testing in Progress")
                .font(.title)
                .fontWeight(.semibold)

            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 400)

            Text(viewModel.statusText)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.currentIteration > 0 {
                Text("Iteration \(viewModel.currentIteration) of \(viewModel.totalIterations) (\(Int(viewModel.progress * 100))% Complete)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Cancel Test") {
                viewModel.cancelTest()
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
    }

    // MARK: - Completion View

    private func completionView(resultsPath: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Test Complete")
                .font(.largeTitle)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                Text("Results have been saved to:")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(resultsPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding()

            Text("Check the console for detailed output")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: {
                    viewModel.reset()
                }) {
                    Label("Test Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    NSWorkspace.shared.selectFile(resultsPath, inFileViewerRootedAtPath: "")
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Error Wrapper

private struct ErrorWrapper: Identifiable {
    let id = UUID()
    let message: String
}
