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

    // MARK: - Constants

    private enum Constants {
        enum Text {
            static let title = "Safari Performance Test"
            static let testFailed = "Test Failed"
            static let ok = "OK"
            static let testing = "Testing"
            static let testConfiguration = "Test Configuration"
            static let iterations = "Iterations"
            static let iterationsFormat = "%d iterations"
            static let startTest = "Start Test"
            static let testingInProgress = "Testing in Progress"
            static let iterationProgress = "Iteration %d of %d (%d%% Complete)"
            static let cancelTest = "Cancel Test"
            static let testComplete = "Test Complete"
            static let resultsSaved = "Results have been saved to:"
            static let checkConsole = "Check the console for detailed output"
            static let testAgain = "Test Again"
            static let showInFinder = "Show in Finder"
        }

        enum Icons {
            static let gauge = "gauge.high"
            static let play = "play.fill"
            static let checkmark = "checkmark.circle.fill"
            static let refresh = "arrow.clockwise"
            static let folder = "folder"
        }

        static let iterationOptions = [1, 3, 5, 10, 20]
    }
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
                title: Text(Constants.Text.testFailed),
                message: Text(error.message),
                dismissButton: .default(Text(Constants.Text.ok))
            )
        }
    }

    // MARK: - Start View

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: Constants.Icons.gauge)
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text(Constants.Text.title)
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let url = viewModel.currentURL {
                VStack(spacing: 8) {
                    Text(Constants.Text.testing)
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
                Text(Constants.Text.testConfiguration)
                    .font(.headline)

                Picker(Constants.Text.iterations, selection: $viewModel.selectedIterations) {
                    ForEach(Constants.iterationOptions, id: \.self) { count in
                        Text(String(format: Constants.Text.iterationsFormat, count)).tag(count)
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
                Label(Constants.Text.startTest, systemImage: Constants.Icons.play)
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
            Text(Constants.Text.testingInProgress)
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
                Text(String(format: Constants.Text.iterationProgress, viewModel.currentIteration, viewModel.totalIterations, Int(viewModel.progress * 100)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(Constants.Text.cancelTest) {
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

            Image(systemName: Constants.Icons.checkmark)
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text(Constants.Text.testComplete)
                .font(.largeTitle)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                Text(Constants.Text.resultsSaved)
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

            Text(Constants.Text.checkConsole)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: {
                    viewModel.reset()
                }) {
                    Label(Constants.Text.testAgain, systemImage: Constants.Icons.refresh)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    NSWorkspace.shared.selectFile(resultsPath, inFileViewerRootedAtPath: "")
                }) {
                    Label(Constants.Text.showInFinder, systemImage: Constants.Icons.folder)
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
