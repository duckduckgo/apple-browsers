//
//  SyncSetupWideEventDefinitionTests.swift
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
import Testing

@testable import DDGSync

@Suite("Sync setup wide event definitions")
struct SyncSetupWideEventDefinitionTests {

    static let metaTypes = ["ios-sync-setup", "macos-sync-setup"]

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../../..")
        .standardizedFileURL

    private static let cancelledFailureReasons: [SyncSetupFailureReason: String] = [
        .incompatibleCode: "code_rejected",
        .unrecognizedCode: "code_rejected"
    ]

    @available(iOS 16, macOS 13, *)
    @Test("Every status_reason the classic failure mapping produces is defined", .timeLimit(.minutes(1)), arguments: metaTypes)
    func failureReasonsAreDefined(metaType: String) throws {
        let defined = try Self.extEnum("status_reason", metaType: metaType)
        let sent = SyncSetupFailureReason.allCases.map { Self.cancelledFailureReasons[$0] ?? $0.rawValue }

        #expect(Set(sent).subtracting(defined) == [])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Every timeout stage the event sends is defined", .timeLimit(.minutes(1)), arguments: metaTypes)
    func timeoutStagesAreDefined(metaType: String) throws {
        let defined = try Self.extEnum("timeout_stage", metaType: metaType)
        let sent = SyncSetupTimeoutStage.allCases.filter { $0 != .waitingForJoinStatus }.map(\.rawValue)

        #expect(Set(sent).subtracting(defined) == [])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A host timing out while waiting for the joiner sends no timeout stage", .timeLimit(.minutes(1)), arguments: metaTypes)
    func joinStatusTimeoutIsNotDefined(metaType: String) throws {
        let defined = try Self.extEnum("timeout_stage", metaType: metaType)

        #expect(!defined.contains(SyncSetupTimeoutStage.waitingForJoinStatus.rawValue))
    }

    private static func extEnum(_ field: String, metaType: String) throws -> Set<String> {
        var node = try latestSchema(metaType: metaType)
        for key in ["feature", "data", "ext", field] {
            let properties = try #require(node["properties"] as? [String: Any])
            node = try #require(properties[key] as? [String: Any], "\(metaType) has no \(key)")
        }
        return Set(try #require(node["enum"] as? [String]))
    }

    private static func latestSchema(metaType: String) throws -> [String: Any] {
        let platform = metaType.hasPrefix("ios-") ? "iOS" : "macOS"
        let directory = repositoryRoot.appendingPathComponent("\(platform)/PixelDefinitions/wide_events/generated_schemas")
        let prefix = "\(metaType)-"
        let versions = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .map { name in
                name.dropFirst(prefix.count).dropLast(".json".count).split(separator: ".").compactMap { Int($0) }
            }
        let latest = try #require(versions.max { $0.lexicographicallyPrecedes($1) }, "no generated schema for \(metaType)")
        let url = directory.appendingPathComponent("\(prefix)\(latest.map(String.init).joined(separator: ".")).json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
