//
//  UserAssistanceTestBrokers.swift
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

/// Debug-menu helper for trying user assistance locally: installs the bundled BeenVerified JSON, dropping `removedAt`
/// because the broker is marked removed in production.
public enum UserAssistanceTestBrokers {
    static var files: [URL] {
        guard let resourceURL = Bundle.module.resourceURL?.appendingPathComponent("BundleResources") else { return [] }
        return [resourceURL.appendingPathComponent("JSON/beenverified.com.json")]
    }

    public static func install(into store: BrokerStoring) throws {
        for file in files {
            try store.upsertBroker(try resource(from: file))
        }
    }

    static func resource(from file: URL) throws -> BrokerResource {
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            throw Step.DecodingError.invalidActionData
        }
        object["removedAt"] = nil
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return BrokerResource(broker: try decoder.decode(DataBroker.self, from: data), rawJSON: data)
    }
}
