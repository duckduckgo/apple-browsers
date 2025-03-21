//
//  MockStore.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import Configuration

final class MockStore: ConfigurationStoring {

    var configToEmbeddedEtag = [Configuration: String?]()
    var configToStoredEtagAndData = [Configuration: (etag: String?, data: Data?)]()
    var defaultSaveData: ((_ data: Data, _ configuration: Configuration) throws -> Void)?
    var defaultSaveEtag: ((_ etag: String, _ configuration: Configuration) throws -> Void)?

    init() {
        defaultSaveData = { data, configuration in
            let (currentEtag, _) = self.configToStoredEtagAndData[configuration] ?? (nil, nil)
            self.configToStoredEtagAndData[configuration] = (currentEtag, data)
        }

        defaultSaveEtag = { etag, configuration in
            let (_, currentData) = self.configToStoredEtagAndData[configuration] ?? (nil, nil)
            self.configToStoredEtagAndData[configuration] = (etag, currentData)
        }
    }

    func loadData(for configuration: Configuration) -> Data? { configToStoredEtagAndData[configuration]?.data }
    func loadEtag(for configuration: Configuration) -> String? { configToStoredEtagAndData[configuration]?.etag }
    func loadEmbeddedEtag(for configuration: Configuration) -> String? { configToEmbeddedEtag[configuration] ?? nil }

    func saveData(_ data: Data, for configuration: Configuration) throws {
        try defaultSaveData?(data, configuration)
    }

    func saveEtag(_ etag: String, for configuration: Configuration) throws {
        try defaultSaveEtag?(etag, configuration)
    }

    func fileUrl(for configuration: Configuration) -> URL {
        return FileManager.default.temporaryDirectory.appending(configuration.rawValue)
    }

}
