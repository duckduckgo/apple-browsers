//
//  ContentScopeExperimentsDebugView.swift
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
import PrivacyConfig
import Core

public struct ContentScopeExperimentsDebugView: View {
    @StateObject private var viewModel = ContentScopeExperimentsDebugViewModel()

    public init() {}

    private func copyContentToClipboard() {
        var content = "ContentScope Experiments:\n\n"
        for experiment in viewModel.experiments {
            content += "Experiment: \(experiment.name)\n"
            content += "State: \(experiment.state)\n"
            content += "Cohorts: \(experiment.cohorts.joined(separator: ", "))\n"
            if let enrollment = experiment.enrollment {
                content += "Enrolled: \(enrollment.cohortID) (\(ContentScopeExperimentsDebugViewModel.formatDate(enrollment.enrollmentDate)))\n"
            } else {
                content += "Enrolled: No\n"
            }
            content += "\n"
        }
        UIPasteboard.general.string = content
    }

    public var body: some View {
        List {
            if viewModel.experiments.isEmpty {
                Section {
                    Text("No experiments defined in contentScopeExperiments")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(viewModel.experiments) { experiment in
                    experimentRow(experiment)
                }
            }
        }
        .navigationTitle("ContentScope Experiments")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: copyContentToClipboard) {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }

    private func experimentRow(_ experiment: ExperimentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(experiment.name)
                    .font(.headline)
                Spacer()
                enrollmentBadge(experiment)
            }

            HStack {
                Text("State:")
                    .foregroundColor(.secondary)
                Text(experiment.state)
                    .foregroundColor(experiment.state == "enabled" ? .green : .orange)
            }
            .font(.subheadline)

            HStack {
                Text("Cohorts:")
                    .foregroundColor(.secondary)
                Text(experiment.cohorts.joined(separator: ", "))
            }
            .font(.subheadline)

            if let minVersion = experiment.minSupportedVersion {
                HStack {
                    Text("Min Version:")
                        .foregroundColor(.secondary)
                    Text(minVersion)
                }
                .font(.caption)
            }

            if let rollout = experiment.rolloutPercent {
                HStack {
                    Text("Rollout:")
                        .foregroundColor(.secondary)
                    Text("\(rollout)%")
                }
                .font(.caption)
            }

            if let enrollment = experiment.enrollment {
                HStack {
                    Text("Cohort:")
                        .foregroundColor(.secondary)
                    Text(enrollment.cohortID)
                        .fontWeight(.medium)
                    Text("(\(ContentScopeExperimentsDebugViewModel.formatDate(enrollment.enrollmentDate)))")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func enrollmentBadge(_ experiment: ExperimentInfo) -> some View {
        if experiment.enrollment != nil {
            Text("Enrolled")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(4)
        } else {
            Text("Not Enrolled")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.gray)
                .cornerRadius(4)
        }
    }
}

// swiftlint:disable:next private_over_fileprivate
fileprivate struct ExperimentInfo: Identifiable {
    let id: String
    let name: String
    let state: String
    let cohorts: [String]
    let minSupportedVersion: String?
    let rolloutPercent: Double?
    let enrollment: ExperimentData?

    init(name: String, state: String, cohorts: [String], minSupportedVersion: String?, rolloutPercent: Double?, enrollment: ExperimentData?) {
        self.id = name
        self.name = name
        self.state = state
        self.cohorts = cohorts
        self.minSupportedVersion = minSupportedVersion
        self.rolloutPercent = rolloutPercent
        self.enrollment = enrollment
    }
}

class ContentScopeExperimentsDebugViewModel: ObservableObject {
    @Published
    fileprivate var experiments: [ExperimentInfo] = []

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    init() {
        loadExperiments()
    }

    private func loadExperiments() {
        let configManager = ContentBlocking.shared.privacyConfigurationManager
        let experimentsManager = AppDependencyProvider.shared.contentScopeExperimentsManager
        let enrolledExperiments = experimentsManager.allActiveContentScopeExperiments

        guard let configData = try? PrivacyConfigurationData(data: configManager.currentConfig),
              let cssFeature = configData.features["contentScopeExperiments"] else {
            return
        }

        var experiments: [ExperimentInfo] = []

        for (name, subfeature) in cssFeature.features {
            let cohortNames = subfeature.cohorts?.map { $0.name } ?? []
            let minVersion = subfeature.minSupportedVersion
            let rolloutPercent = subfeature.rollout?.steps.last?.percent

            let enrollment = enrolledExperiments[name]

            experiments.append(ExperimentInfo(
                name: name,
                state: subfeature.state,
                cohorts: cohortNames,
                minSupportedVersion: minVersion,
                rolloutPercent: rolloutPercent,
                enrollment: enrollment
            ))
        }

        self.experiments = experiments.sorted { $0.name < $1.name }
    }
}
