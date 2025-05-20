//
//  AppKeyValueFileStoreService.swift
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

import Persistence
import Foundation
import Common
import Core

final class AppKeyValueFileStoreService {

    private enum Constants {
        static let defaultStorageName = "AppKeyValueStore"
    }

    enum Error: Swift.Error {
        case appSupportDirAccessError
        case kvfsInitError
    }

    let keyValueFilesStore: ThrowingKeyValueStoring

    init() throws {

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Pixel.fire(pixel: .keyValueFileStoreSupportDirAccessError)

            // Move app to Terminating state
            throw Error.appSupportDirAccessError
        }

        do {
            self.keyValueFilesStore = try KeyValueFileStore(location: appSupportDir, name: Constants.defaultStorageName)

            // Try to preload data, to break init flow immediately on access issue
            try _ = keyValueFilesStore.object(forKey: "any")
        } catch {
            Pixel.fire(pixel: .keyValueFileStoreInitError)

            // Move app to Terminating state
            throw Error.kvfsInitError
        }
    }

}
