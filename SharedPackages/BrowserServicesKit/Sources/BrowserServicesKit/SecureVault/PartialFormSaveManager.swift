//
//  PartialFormSaveManager.swift
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
import Common

final class PartialFormSaveManager {
    typealias WebsiteAccount = SecureVaultModels.WebsiteAccount

    private static var accounts: [String: WebsiteAccount] = .init()

    private let tld: TLD

    init(tld: TLD) {
        self.tld = tld
    }

    func partialAccount(forDomain domain: String) -> WebsiteAccount? {
        guard let tldPlus1 = tld.eTLDplus1(domain) else {
            return nil
        }
        guard let account = Self.accounts[tldPlus1] else {
            return nil
        }

        guard account.lastUpdated.isLessThan(minutesAgo: 3) else {
            Self.accounts.removeValue(forKey: domain)
            return nil
        }

        return account
    }

    func store(partialAccount: WebsiteAccount, for domain: String) {
        guard let tldPlus1 = tld.eTLDplus1(domain) else {
            return
        }
        Self.accounts[tldPlus1] = partialAccount
    }

    func removePartialAccount(for domain: String) {
        guard let tldPlus1 = tld.eTLDplus1(domain) else {
            return
        }
        Self.accounts.removeValue(forKey: tldPlus1)
    }
}
