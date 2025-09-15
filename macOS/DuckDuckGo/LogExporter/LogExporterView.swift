//
//  LogExporterView.swift
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

struct LogExporterConfiguration {
    let confirmed: Bool
    let timeInterval: Int
    let includeAllDDG: Bool
    let includeNetworkProtection: Bool
    let includePersonalInformationRemoval: Bool
    let includeSparkle: Bool
}

struct LogExporterView: View {

    static let defaultInterval: Int = 10
    @State private var timeIntervalString: String = "\(Self.defaultInterval)"
    @State private var includeAllDDG = true
    @State private var includeNetworkProtection = true
    @State private var includePersonalInformationRemoval = true
    @State private var includeSparkle = true

    let onComplete: (_ result: LogExporterConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Time Interval:")
                .font(.headline)
            HStack {
                TextField("", text: $timeIntervalString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text(verbatim: "Minutes")
                    .font(.body)
            }

            // Checkboxes
            VStack(alignment: .leading) {
                Text(verbatim: "File Types:")
                    .font(.headline)
                Toggle(UserText.duckDuckGo, isOn: $includeAllDDG)
                Toggle(UserText.networkProtection, isOn: $includeNetworkProtection)
                Toggle(UserText.personalInformationRemoval, isOn: $includePersonalInformationRemoval)
                Toggle(UserText.update, isOn: $includeSparkle)
            }

            Spacer()

            HStack {
                Spacer()
                Button(UserText.cancel) {
                    onComplete(.init(
                        confirmed: false,
                        timeInterval: Int(timeIntervalString) ?? Self.defaultInterval,
                        includeAllDDG: includeAllDDG,
                        includeNetworkProtection: includeNetworkProtection,
                        includePersonalInformationRemoval: includePersonalInformationRemoval,
                        includeSparkle: includeSparkle
                    ))
                }
                Button(UserText.ok) {
                    onComplete(.init(
                        confirmed: true,
                        timeInterval: Int(timeIntervalString) ?? Self.defaultInterval,
                        includeAllDDG: includeAllDDG,
                        includeNetworkProtection: includeNetworkProtection,
                        includePersonalInformationRemoval: includePersonalInformationRemoval,
                        includeSparkle: includeSparkle
                    ))
                }
                .disabled(timeIntervalString.isEmpty || (includeAllDDG || includeNetworkProtection || includePersonalInformationRemoval || includeSparkle) == false)
                .keyboardShortcut(.defaultAction)

            }
        }
        .padding(20)
        .frame(minWidth: 300, maxWidth: 300, minHeight: 280, maxHeight: 280)
    }
}
