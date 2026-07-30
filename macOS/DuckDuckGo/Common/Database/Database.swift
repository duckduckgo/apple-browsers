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
import AppKitExtensions
import BrowserServicesKit
import Common
import FoundationExtensions
import CoreData
import Foundation
import Persistence
import PixelKit
import Security
import Utilities

final class Database {

    public let db: CoreDataDatabase

    fileprivate struct Constants {
        static let databaseName = "Database"
    }

    init(keyStore: EncryptionKeyStoring? = nil) {
#if DEBUG
        assert(![.unitTests, .xcPreviews].contains(AppVersion.runType), {
            "Use CoreData.---Container() methods for testing purposes:\n" + Thread.callStackSymbols.description
        }())
#endif

        let keyStore: EncryptionKeyStoring = keyStore ?? Self.defaultKeyStore()

        let containerLocation: URL = {
#if DEBUG
            guard case .normal = AppVersion.runType else {
                return FileManager.default.temporaryDirectory
            }
#endif
            return .sandboxApplicationSupportURL
        }()

        let mainModel = NSManagedObjectModel.mergedModel(from: [.main])!

        Self.registerValueTransformers(in: mainModel, keyStore: keyStore)

        let httpsUpgradeModel = HTTPSUpgrade.managedObjectModel

        db = CoreDataDatabase(
            name: Constants.databaseName,
            containerLocation: containerLocation,
            model: .init(byMerging: [mainModel, httpsUpgradeModel])!
        )
    }

    private static func defaultKeyStore() -> EncryptionKeyStoring {
#if DEBUG
        guard case .normal = AppVersion.runType else {
            return (NSClassFromString("MockEncryptionKeyStore") as? EncryptionKeyStoring.Type)!.init()
        }
#endif
        return EncryptionKeyStore(generator: EncryptionKeyGenerator())
    }

    // MARK: - Value transformers

    private enum KeychainFailureOutcome: String {
        /// No window server session to prompt in, e.g. a dark wake launch.
        case noUI = "no_ui"
        case quit
        case retried
        case recovered
    }

    /// Registers the encrypted value transformers, which requires the data encryption key from the login keychain.
    ///
    /// A locked, damaged or password-mismatched login keychain used to be fatal here. The app can't run without the
    /// key — the encrypted attributes would be unreadable — but the failure is recoverable by the user, so offer a
    /// retry and quit cleanly instead of trapping.
    private static func registerValueTransformers(in model: NSManagedObjectModel, keyStore: EncryptionKeyStoring) {
        var previousError: Error?
        while true {
            do {
                _ = try model.registerValueTransformers(withAllowedPropertyClasses: [
                    NSImage.self,
                    NSString.self,
                    NSURL.self,
                    NSNumber.self,
                    NSError.self,
                    NSData.self
                ], keyStore: keyStore)

                if let previousError {
                    fire(previousError, outcome: .recovered)
                }
                return
            } catch {
                previousError = error

                guard case .normal = AppVersion.runType else {
                    fatalError("Could not register value transformers: \(error.localizedDescription)")
                }
                guard canPromptUser(about: error) else {
                    fire(error, outcome: .noUI)
                    quit()
                }
                NSApp.activate(ignoringOtherApps: true)
                guard NSAlert.keychainKeyUnavailable(status: status(of: error)).runModal() == .alertFirstButtonReturn else {
                    fire(error, outcome: .quit)
                    quit()
                }
                fire(error, outcome: .retried)
            }
        }
    }

    private static func canPromptUser(about error: Error) -> Bool {
        // Nothing can be displayed in dark wake or without an unlockable session, so a prompt would fail the same way.
        ![errSecInDarkWake, errSecInteractionNotAllowed].contains(status(of: error))
    }

    private static func status(of error: Error) -> OSStatus {
        (error as? EncryptionKeyStoreError)?.status ?? OSStatus((error as NSError).code)
    }

    private static func fire(_ error: Error, outcome: KeychainFailureOutcome) {
        PixelKit.fire(DebugEvent(GeneralPixel.dbValueTransformerRegistrationError, error: error),
                      frequency: .dailyAndCount,
                      withAdditionalParameters: [PixelKit.Parameters.keychainKeyOutcome: outcome.rawValue])
    }

    /// Exits without a crash report, leaving time for the pixel to be sent.
    private static func quit() -> Never {
        Thread.sleep(forTimeInterval: 1)
        exit(0)
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
