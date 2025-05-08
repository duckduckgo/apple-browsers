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
    let includeSparkle: Bool
}

struct LogExporterView: View {

    static let defaultInterval: Int = 10
    @State private var timeIntervalString: String = "\(Self.defaultInterval)"
    @State private var includeAllDDG = true
    @State private var includeNetworkProtection = true
    @State private var includeSparkle = true

    let onComplete: (_ result: LogExporterConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Time Interval Input
            HStack {
                Text("Time Interval:")
                    .font(.headline)
                TextField("Enter time interval in minutes (e.g., 30)", text: $timeIntervalString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            // Checkboxes
            VStack(alignment: .leading) {
                Text("File Types:")
                    .font(.headline)
                Toggle("All DDG", isOn: $includeAllDDG).padding(.leading)
                Toggle("Network protection", isOn: $includeNetworkProtection).padding(.leading)
                Toggle("Sparkle", isOn: $includeSparkle).padding(.leading)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete(.init(
                        confirmed: false,
                        timeInterval: Int(timeIntervalString) ?? Self.defaultInterval,
                        includeAllDDG: includeAllDDG,
                        includeNetworkProtection: includeNetworkProtection,
                        includeSparkle: includeSparkle
                    ))
                }
                Button("OK") {
                    onComplete(.init(
                        confirmed: true,
                        timeInterval: Int(timeIntervalString) ?? Self.defaultInterval,
                        includeAllDDG: includeAllDDG,
                        includeNetworkProtection: includeNetworkProtection,
                        includeSparkle: includeSparkle
                    ))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 250, minHeight: 200)
    }
}
