//
//  MockStoreWithStorage.swift
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
import Persistence
import PersistenceTestingUtils
@testable import Configuration

final class MockStoreWithStorage: ConfigurationStoring {

    var etagStorage: KeyValueStoring

    init(etagStorage: KeyValueStoring) {
        self.etagStorage = etagStorage
    }

    func loadEtag(for configuration: Configuration) -> String? { etagStorage.object(forKey: configuration.rawValue) as? String }
    func loadEmbeddedEtag(for configuration: Configuration) -> String? { nil }

    func loadData(for configuration: Configuration) -> Data? {
        let file = fileUrl(for: configuration)
        var data: Data?
        var coordinatorError: NSError?

        NSFileCoordinator().coordinate(readingItemAt: file, error: &coordinatorError) { fileUrl in
            do {
                data = try Data(contentsOf: fileUrl)
            } catch {
                let nserror = error as NSError

                if nserror.domain != NSCocoaErrorDomain || nserror.code != NSFileReadNoSuchFileError {
                    fatalError("Unable to load config file: \(error.localizedDescription)")
                }
            }
        }

        if let coordinatorError {
            fatalError("Unable to read due to coordinator error: \(coordinatorError.localizedDescription)")
        }

        return data
    }

    func saveData(_ data: Data, for configuration: Configuration) throws {
        let file = fileUrl(for: configuration)
        var coordinatorError: NSError?

        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinatorError) { fileUrl in
            do {
                try data.write(to: fileUrl, options: .atomic)
            } catch {
                fatalError("Unable to write temp configuration file: \(error.localizedDescription)")
            }
        }

        if let coordinatorError {
            fatalError("Unable to write due to coordinator error: \(coordinatorError.localizedDescription)")
        }
    }

    func saveEtag(_ etag: String, for configuration: Configuration) {
        etagStorage.set(etag, forKey: configuration.rawValue)
    }

    func fileUrl(for configuration: Configuration) -> URL {
        return FileManager.default.temporaryDirectory.appending(configuration.rawValue)
    }

    static func clearTempConfigs() {
        let tempStore = MockStoreWithStorage(etagStorage: MockKeyValueStore())
        for conf in Configuration.allCases {
            try? FileManager.default.removeItem(at: tempStore.fileUrl(for: conf))
        }
    }

}
