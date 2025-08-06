//
//  PersistentStoresConfiguration.swift
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

import Foundation
import Core
import Persistence

final class PersistentStoresConfiguration {

    let database = Database.shared
    let bookmarksDatabase = BookmarksDatabase.make()
    private let application: UIApplication

    init(application: UIApplication = .shared) {
        self.application = application
    }

    func configure() throws {
        clearTemporaryDirectory()
        try loadDatabase()
        try loadAndMigrateBookmarksDatabase()
    }

    private func clearTemporaryDirectory() {
        let tmp = FileManager.default.temporaryDirectory
        do {
            try FileManager.default.removeItem(at: tmp)
            Logger.general.info("🧹 Removed temp directory at: \(tmp.path)")
            // https://app.asana.com/1/137249556945/project/1201392122292466/task/1210925187026095?focus=true
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: nil)
            Logger.general.info("📁 Recreated temp directory at: \(tmp.path)")
        } catch {
            Logger.general.error("❌ Failed to reset tmp dir: \(error.localizedDescription)")
        }
    }

    private func loadDatabase() throws {
        var thrownError: Error?
        database.loadStore { [application] context, error in
            do {
                guard let context = context else {
                    let parameters = [PixelParameters.applicationState: "\(application.applicationState.rawValue)",
                                      PixelParameters.dataAvailability: "\(application.isProtectedDataAvailable)"]
                    switch error {
                    case .none:
                        fatalError("Could not create database stack: Unknown Error")
                    case .some(CoreDataDatabase.Error.containerLocationCouldNotBePrepared(let underlyingError)):
                        Pixel.fire(pixel: .dbContainerInitializationError,
                                   error: underlyingError,
                                   withAdditionalParameters: parameters)
                        Thread.sleep(forTimeInterval: 1)
                        fatalError("Could not create database stack: \(underlyingError.localizedDescription)")
                    case .some(let error):
                        Pixel.fire(pixel: .dbInitializationError,
                                   error: error,
                                   withAdditionalParameters: parameters)
                        if error.isDiskFull {
                            throw UIApplication.TerminationError.insufficientDiskSpace
                        } else {
                            Thread.sleep(forTimeInterval: 1)
                            fatalError("Could not create database stack: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
    }

    private func loadAndMigrateBookmarksDatabase() throws {
        switch BookmarksDatabaseSetup().loadStoreAndMigrate(bookmarksDatabase: bookmarksDatabase) {
        case .success:
            break
        case .failure(let error):
            Pixel.fire(pixel: .bookmarksCouldNotLoadDatabase,
                       error: error)
            if error.isDiskFull {
                throw UIApplication.TerminationError.insufficientDiskSpace
            } else {
                Thread.sleep(forTimeInterval: 1)
                fatalError("Could not create database stack: \(error.localizedDescription)")
            }
        }
    }

}

extension Error {

    var isDiskFull: Bool {
        let nsError = self as NSError
        if let underlyingError = nsError.userInfo["NSUnderlyingError"] as? NSError, underlyingError.code == 13 {
            return true
        } else if nsError.userInfo["NSSQLiteErrorDomain"] as? Int == 13 {
            return true
        }
        return false
    }

}
