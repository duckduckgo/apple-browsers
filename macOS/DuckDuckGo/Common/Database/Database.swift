//
//  Database.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import AppKit
import BrowserServicesKit
import Common
import CoreData
import Foundation
import Persistence
import PixelKit
import Utilities

final class Database {

    public let db: CoreDataDatabase

    fileprivate struct Constants {
        static let databaseName = "Database"
    }

    init() {
#if DEBUG
        assert(![.unitTests, .xcPreviews].contains(AppVersion.runType), {
            "Use CoreData.---Container() methods for testing purposes:\n" + Thread.callStackSymbols.description
        }())
#endif

        let keyStore: EncryptionKeyStoring = {
#if DEBUG
            guard case .normal = AppVersion.runType else {
                return (NSClassFromString("MockEncryptionKeyStore") as? EncryptionKeyStoring.Type)!.init()
            }
#endif
            return EncryptionKeyStore(generator: EncryptionKeyGenerator())
        }()

        let containerLocation: URL = {
#if DEBUG
            guard case .normal = AppVersion.runType else {
                return FileManager.default.temporaryDirectory
            }
#endif
            return .sandboxApplicationSupportURL
        }()

        let mainModel = NSManagedObjectModel.mergedModel(from: [.main])!

        _ = mainModel.registerValueTransformers(withAllowedPropertyClasses: [
            NSImage.self,
            NSString.self,
            NSURL.self,
            NSNumber.self,
            NSError.self,
            NSData.self
        ], keyStore: keyStore)

        let httpsUpgradeModel = HTTPSUpgrade.managedObjectModel

        db = CoreDataDatabase(
            name: Constants.databaseName,
            containerLocation: containerLocation,
            model: .init(byMerging: [mainModel, httpsUpgradeModel])!
        )
    }
}

extension NSManagedObjectContext {

    func save(onErrorFire event: PixelKitEvent) throws {
        do {
            try save()
        } catch {
            let nsError = error as NSError
            let processedErrors = CoreDataErrorsParser.parse(error: nsError)

            PixelKit.fire(DebugEvent(event, error: error),
                       withAdditionalParameters: processedErrors.errorPixelParameters)

            throw error
        }
    }
}

extension Array where Element == CoreDataErrorsParser.ErrorInfo {

    var errorPixelParameters: [String: String] {
        let params: [String: String]
        if let first = first {
            params = ["errorCount": "\(count)",
                      "coreDataCode": "\(first.code)",
                      "coreDataDomain": first.domain,
                      "coreDataEntity": first.entity ?? "empty",
                      "coreDataAttribute": first.property ?? "empty"]
        } else {
            params = ["errorCount": "\(count)"]
        }
        return params
    }
}
