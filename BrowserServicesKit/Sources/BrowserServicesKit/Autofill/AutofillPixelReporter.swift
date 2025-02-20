//
//  AutofillPixelReporter.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import SecureStorage
import Common

public enum AutofillPixelEvent {
    case autofillActiveUser
    case autofillEnabledUser
    case autofillOnboardedUser
    case autofillToggledOn
    case autofillToggledOff
    case autofillLoginsStacked
    case autofillCreditCardsStacked
    case autofillIdentitiesStacked

    enum Parameter {
        static let countBucket = "count_bucket"
    }
}

public final class AutofillPixelReporter {

    public enum Keys {
        static let autofillSearchDauDateKey = "com.duckduckgo.app.autofill.SearchDauDate"
        static let autofillFillDateKey = "com.duckduckgo.app.autofill.FillDate"
        static let autofillOnboardedUserKey = "com.duckduckgo.app.autofill.OnboardedUser"
        static public let autofillDauMigratedKey = "com.duckduckgo.app.autofill.DauDataMigrated"
    }

    enum BucketName: String {
        case none
        case few
        case some
        case many
        case lots
    }

    private enum EventType {
        case fill
        case searchDAU
    }

    private let userDefaults: UserDefaults
    private let eventMapping: EventMapping<AutofillPixelEvent>
    private var secureVault: (any AutofillSecureVault)?
    private var reporter: SecureVaultReporting?
    // Third party password manager
    private let passwordManager: PasswordManager?
    private var installDate: Date?
    private var autofillEnabled: Bool

    private var autofillSearchDauDate: Date? { userDefaults.object(forKey: Keys.autofillSearchDauDateKey) as? Date ?? .distantPast }
    private var autofillFillDate: Date? { userDefaults.object(forKey: Keys.autofillFillDateKey) as? Date ?? .distantPast }
    private var autofillOnboardedUser: Bool { userDefaults.object(forKey: Keys.autofillOnboardedUserKey) as? Bool ?? false }
    private var autofillDauMigrated: Bool { userDefaults.object(forKey: Keys.autofillDauMigratedKey) as? Bool ?? false }

    public init(standardUserDefaults: UserDefaults,
                appGroupUserDefaults: UserDefaults?,
                autofillEnabled: Bool,
                eventMapping: EventMapping<AutofillPixelEvent>,
                secureVault: (any AutofillSecureVault)? = nil,
                reporter: SecureVaultReporting? = nil,
                passwordManager: PasswordManager? = nil,
                installDate: Date? = nil
    ) {
        self.userDefaults = appGroupUserDefaults ?? standardUserDefaults
        self.autofillEnabled = autofillEnabled
        self.eventMapping = eventMapping
        self.secureVault = secureVault
        self.reporter = reporter
        self.passwordManager = passwordManager
        self.installDate = installDate

        if let appGroupUserDefaults {
            migrateDataIfNeeded(from: standardUserDefaults, to: appGroupUserDefaults)
        }
        createNotificationObservers()
    }

    public func updateAutofillEnabledStatus(_ autofillEnabled: Bool) {
        self.autofillEnabled = autofillEnabled
    }

    public func resetStoreDefaults() {
        userDefaults.set(Date.distantPast, forKey: Keys.autofillSearchDauDateKey)
        userDefaults.set(Date.distantPast, forKey: Keys.autofillFillDateKey)
        userDefaults.set(false, forKey: Keys.autofillOnboardedUserKey)
    }

    private func createNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveSearchDAU), name: .searchDAU, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveFillEvent), name: .autofillFillEvent, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveSaveEvent), name: .autofillSaveEvent, object: nil)
    }

    private func migrateDataIfNeeded(from source: UserDefaults, to destination: UserDefaults) {
        guard autofillDauMigrated == false else {
            return
        }

        let keysToMigrate = [
            Keys.autofillSearchDauDateKey,
            Keys.autofillFillDateKey,
            Keys.autofillOnboardedUserKey
        ]

        for key in keysToMigrate {
            if let value = source.object(forKey: key) {
                destination.set(value, forKey: key)
                source.removeObject(forKey: key)  // Delete from source after migration
            }
        }

        destination.set(true, forKey: Keys.autofillDauMigratedKey)
    }

    @objc
    private func didReceiveSearchDAU() {
        guard let autofillSearchDauDate = autofillSearchDauDate, !Date.isSameDay(Date(), autofillSearchDauDate) else {
            return
        }

        userDefaults.set(Date(), forKey: Keys.autofillSearchDauDateKey)

        firePixelsFor(.searchDAU)
    }

    @objc
    private func didReceiveFillEvent() {
        guard let autofillFillDate = autofillFillDate, !Date.isSameDay(Date(), autofillFillDate) else {
            return
        }

        userDefaults.set(Date(), forKey: Keys.autofillFillDateKey)

        firePixelsFor(.fill)
    }

    @objc
    private func didReceiveSaveEvent() {
        guard !autofillOnboardedUser else {
            return
        }

        if shouldFireOnboardedUserPixel() {
            eventMapping.fire(.autofillOnboardedUser)
        }
    }

    private func firePixelsFor(_ type: EventType) {
        if shouldFireActiveUserPixel() {
            eventMapping.fire(.autofillActiveUser)

            if let accountsCountBucket = getAccountsCountBucket() {
                eventMapping.fire(.autofillLoginsStacked, parameters: [AutofillPixelEvent.Parameter.countBucket: accountsCountBucket])
            }

            if let cardsCount = try? vault()?.creditCardsCount() {
                eventMapping.fire(.autofillCreditCardsStacked, parameters: [AutofillPixelEvent.Parameter.countBucket: creditCardsBucketNameFrom(count: cardsCount)])
            }

            if let identitiesCount = try? vault()?.identitiesCount() {
                eventMapping.fire(.autofillIdentitiesStacked, parameters: [AutofillPixelEvent.Parameter.countBucket: identitiesBucketNameFrom(count: identitiesCount)])
            }
        }

        switch type {
        case .searchDAU:
            if shouldFireEnabledUserPixel() {
                eventMapping.fire(.autofillEnabledUser)
            }

            if let accountsCountBucket = getAccountsCountBucket() {
                eventMapping.fire(autofillEnabled ? .autofillToggledOn : .autofillToggledOff,
                                  parameters: [AutofillPixelEvent.Parameter.countBucket: accountsCountBucket])
            }

        default:
            break
        }
    }

    private func getAccountsCountBucket() -> String? {
        if let passwordManager = passwordManager, passwordManager.isEnabled {
            // if a user is using a password manager we can't get a count of their passwords so we are assuming they are likely to have a lot of passwords saved
            return BucketName.lots.rawValue
        } else if let accountsCount = try? vault()?.accountsCount() {
            return Self.accountsBucketNameFrom(count: accountsCount)
        }
        return nil
    }

    private func shouldFireActiveUserPixel() -> Bool {
        let today = Date()
        if Date.isSameDay(today, autofillSearchDauDate) && Date.isSameDay(today, autofillFillDate) {
            return true
        }
        return false
    }

    private func shouldFireEnabledUserPixel() -> Bool {
        if Date.isSameDay(Date(), autofillSearchDauDate) {
            if let passwordManager = passwordManager, passwordManager.isEnabled {
                return true
            } else if autofillEnabled, let count = try? vault()?.accountsCount(), count >= 10 {
                return true
            }
        }
        return false
    }

    private func shouldFireOnboardedUserPixel() -> Bool {
        guard !autofillOnboardedUser, let installDate = installDate else {
            return false
        }

        let pastWeek = Date().addingTimeInterval(.days(-7))

        if installDate >= pastWeek {
            if let passwordManager = passwordManager, passwordManager.isEnabled {
                return true
            } else if let count = try? vault()?.accountsCount(), count > 0 {
                userDefaults.set(true, forKey: Keys.autofillOnboardedUserKey)
                return true
            }
        } else {
            userDefaults.set(true, forKey: Keys.autofillOnboardedUserKey)
        }

        return false
    }

    private func vault() -> (any AutofillSecureVault)? {
        if secureVault == nil {
            secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: reporter)
        }
        return secureVault
    }

    public static func accountsBucketNameFrom(count: Int) -> String {
        if count == 0 {
            return BucketName.none.rawValue
        } else if count < 4 {
            return BucketName.few.rawValue
        } else if count < 11 {
            return BucketName.some.rawValue
        } else if count < 50 {
            return BucketName.many.rawValue
        } else {
            return BucketName.lots.rawValue
        }
    }

    private func creditCardsBucketNameFrom(count: Int) -> String {
        if count == 0 {
            return BucketName.none.rawValue
        } else if count < 4 {
            return BucketName.some.rawValue
        } else {
            return BucketName.many.rawValue
        }
    }

    private func identitiesBucketNameFrom(count: Int) -> String {
        if count == 0 {
            return BucketName.none.rawValue
        } else if count < 5 {
            return BucketName.some.rawValue
        } else if count < 12 {
            return BucketName.many.rawValue
        } else {
            return BucketName.lots.rawValue
        }
    }

}

public extension NSNotification.Name {

    static let autofillFillEvent: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.browserServicesKit.AutofillFillEvent")
    static let autofillSaveEvent: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.browserServicesKit.AutofillSaveEvent")
    static let searchDAU: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.browserServicesKit.SearchDAU")

}
