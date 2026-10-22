//
//  SnapshotRecordMode.swift
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

import Foundation
import SnapshotTesting

public enum SnapshotRecordMode {
    public static let environmentVariableName = "GENERATE_SNAPSHOTS"
    public static let requireReferencesEnvironmentVariableName = "REQUIRE_SNAPSHOT_REFERENCES"

    public static func shouldRecord(
        record: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        record || isEnabled(environment[environmentVariableName])
    }

    public static func requiresReferences(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        isEnabled(environment[requireReferencesEnvironmentVariableName])
    }

    static func snapshotTestingRecord(
        record: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SnapshotTestingConfiguration.Record {
        if shouldRecord(record: record, environment: environment) {
            return .all
        }
        return requiresReferences(environment: environment) ? .never : .missing
    }

    private static func isEnabled(_ value: String?) -> Bool {
        switch value?.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}
