//
//  PasswordManagementItemListModelTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import FeatureFlags
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PasswordManagementItemListModelTests: XCTestCase {

    var oldSelection: SecureVaultItem?
    var newSelection: SecureVaultItem?

    func testWhenAccountIsSelectedThenModelReflectsThat() {
        let accounts = (0 ..< 10).map { makeAccount(id: $0, domain: "domain\($0)") }
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: accounts)
        model.select(item: accounts[0])
        XCTAssertNotNil(model.selected)

        model.select(item: accounts[8])
        XCTAssertEqual(model.selected?.id, String(describing: accounts[8]))

        model.clearSelection()
        XCTAssertNil(model.selected)

        model.selectFirst()
        XCTAssertEqual(model.selected?.id, String(describing: accounts[0]))

    }

    func testWhenFilterAppliedThenDisplayedAccountsOnlyContainFilteredMatches() {

        let createdAccounts = (0 ..< 10).map { makeAccount(id: $0, domain: "domain\($0)") }
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: createdAccounts)
        model.filter = "domain5"

        XCTAssertEqual(model.displayedSections.count, 1)

        let filteredAccounts = accounts(from: model.displayedSections)
        XCTAssertEqual(filteredAccounts[0].domain, "domain5")

        model.filter = ""

        let unfilteredAccounts = accounts(from: model.displayedSections)
        XCTAssertEqual(unfilteredAccounts.count, 10)
        XCTAssertEqual(unfilteredAccounts[0].domain, "domain0")
        XCTAssertEqual(unfilteredAccounts[9].domain, "domain9")
    }

    func testWhenAccountIsSelectedThenCallbackReceivesOldAndNewVersion() {
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)
        let account = makeAccount(id: 1)

        model.update(items: [account])
        model.select(item: account)

        XCTAssertNil(oldSelection)
        XCTAssertNotNil(newSelection)
    }

    func testWhenGettingEmptyState_AndViewModelIsNewlyCreated_ThenEmptyStateIsNone() {
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)
        XCTAssertEqual(model.emptyState, .none)
    }

    func testWhenGettingEmptyState_AndViewModelGetsGivenEmptyDataSet_ThenEmptyStateIsNoData() {
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)
        model.update(items: [])

        XCTAssertEqual(model.emptyState, .noData)
    }

    func testWhenGettingEmptyState_AndViewModelHasData_AndCategoryIsAllItems_AndViewModelIsFiltered_ThenEmptyStateIsNone() {
        let accounts = (0 ..< 10).map { makeAccount(id: $0, domain: "domain\($0)") }
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: accounts)
        XCTAssertEqual(model.emptyState, .none)

        model.filter = "domain"
        XCTAssertEqual(model.emptyState, .none)

        model.filter = "filter that won't match"
        XCTAssertEqual(model.emptyState, .none)
    }

    func testWhenGettingEmptyState_AndViewModelHasData_AndCategoryIsLogins_AndViewModelIsFiltered_ThenEmptyStateIsLogins() {
        let accounts = (0 ..< 10).map { makeAccount(id: $0, domain: "domain\($0)") }
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: accounts)
        model.sortDescriptor.category = .logins
        XCTAssertEqual(model.emptyState, .none)

        model.filter = "domain"
        XCTAssertEqual(model.emptyState, .none)

        model.filter = "filter that won't match"
        XCTAssertEqual(model.emptyState, .logins)
    }

    func testWhenGettingSelectedItem_AndViewModelHasNoMatchingDomains_ThenFirstItemSelected() {
        let account1 = makeAccount(id: 1, domain: "adomain.com")
        let account2 = makeAccount(id: 2, domain: "anotherdomain.com")
        let account3 = makeAccount(id: 3, domain: "otherdomain.com")
        let accounts = [account1, account2, account3]

        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: accounts)
        model.selectLoginWithDomainOrFirst(domain: "dummy.com")

        XCTAssertNotNil(model.selected)
        XCTAssertEqual(model.selected?.id, String(describing: accounts[0]))
    }

    func testWhenGettingSelectedItem_AndViewModelHasMatchingDomain_ThenMatchingDomainSelected() {
        let account1 = makeAccount(id: 1, domain: "adomain.com")
        let account2 = makeAccount(id: 2, domain: "example.com")
        let account3 = makeAccount(id: 3, domain: "otherdomain.com")
        let accounts = [account1, account2, account3]

        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: accounts)
        model.selectLoginWithDomainOrFirst(domain: "example.com")

        XCTAssertNotNil(model.selected)
        XCTAssertEqual(model.selected?.id, String(describing: accounts[1]))
    }

    func testWhenGettingSelectedItem_AndViewModelHasMatchingSubdomains_ThenMatchingSubdomainSelected() {
        let account1 = makeAccount(id: 1, domain: "example.com")
        let account2 = makeAccount(id: 2, domain: "sub.example.com")
        let account3 = makeAccount(id: 3, domain: "www.example.com")
        let accounts = [account1, account2, account3]

        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected, onAddItemSelected: onAddItemSelected)

        model.update(items: accounts)
        model.selectLoginWithDomainOrFirst(domain: "sub.example.com")

        XCTAssertNotNil(model.selected)
        XCTAssertEqual(model.selected?.id, String(describing: accounts[1]))

        model.selectLoginWithDomainOrFirst(domain: "example.com")

        XCTAssertNotNil(model.selected)
        XCTAssertEqual(model.selected?.id, String(describing: accounts[0]))
    }

    func testWhenFeatureFlagEnabledAndFilterMatchesDomain_ThenFirstDomainMatchIsSelected() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enableFeatures([.autofillPasswordSearchPrioritizeDomain])

        let account1 = makeAccount(id: 1, title: nil, username: "user1", domain: "example.com")
        let account2 = makeAccount(id: 2, title: nil, username: "example", domain: "test.com")
        let account3 = makeAccount(id: 3, title: nil, username: "user3", domain: "example.org")
        let accounts = [account1, account2, account3]

        let model = makeModel(with: featureFlagger, accounts: accounts, category: .allItems, filter: "example")
        model.selectFirst()

        XCTAssertEqual(model.selected?.id, String(describing: account1))
    }

    func testWhenFeatureFlagEnabledAndFilterMatchesDomainInLoginsCategory_ThenFirstDomainMatchIsSelected() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enableFeatures([.autofillPasswordSearchPrioritizeDomain])

        let account1 = makeAccount(id: 1, title: nil, username: "user1", domain: "example.com")
        let account2 = makeAccount(id: 2, title: nil, username: "example", domain: "test.com")
        let account3 = makeAccount(id: 3, title: nil, username: "user3", domain: "example.org")
        let accounts = [account1, account2, account3]

        let model = makeModel(with: featureFlagger, accounts: accounts, category: .logins, filter: "example")
        model.selectFirst()

        XCTAssertEqual(model.selected?.id, String(describing: account1))
    }

    func testWhenFeatureFlagEnabledAndNoDomainMatch_ThenFirstItemIsSelected() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enableFeatures([.autofillPasswordSearchPrioritizeDomain])

        let account1 = makeAccount(id: 1, title: nil, username: "user1", domain: "example.com")
        let account2 = makeAccount(id: 2, title: nil, username: "example", domain: "test.com")
        let account3 = makeAccount(id: 3, title: nil, username: "user3", domain: "other.org")
        let accounts = [account1, account2, account3]

        let model = makeModel(with: featureFlagger, accounts: accounts, category: .allItems, filter: "user")
        model.selectFirst()

        XCTAssertNotNil(model.selected)
        let filteredAccounts = self.accounts(from: model.displayedSections)
        XCTAssertEqual(filteredAccounts.count, 2, "Should have 2 accounts matching 'user' in username")
        assertSelectedMatchesFirstFilteredAccount(model: model, filteredAccounts: filteredAccounts)
    }

    func testWhenFeatureFlagDisabledAndFilterMatchesDomain_ThenFirstItemIsSelected() {
        let featureFlagger = MockFeatureFlagger()
        // Feature flag is not enabled

        let account1 = makeAccount(id: 1, title: nil, username: "user1", domain: "example.com")
        let account2 = makeAccount(id: 2, title: nil, username: "example", domain: "test.com")
        let account3 = makeAccount(id: 3, title: nil, username: "user3", domain: "example.org")
        let accounts = [account1, account2, account3]

        let model = makeModel(with: featureFlagger, accounts: accounts, category: .allItems, filter: "example")
        model.selectFirst()

        XCTAssertNotNil(model.selected)
        let filteredAccounts = self.accounts(from: model.displayedSections)
        assertSelectedMatchesFirstFilteredAccount(model: model, filteredAccounts: filteredAccounts)
    }

    func makeAccount(id: Int64, title: String? = nil, username: String = "username", domain: String = "domain") -> SecureVaultItem {
        let account = SecureVaultModels.WebsiteAccount(id: String(id),
                                                title: title,
                                                username: username,
                                                domain: domain)
        return .account(account)
    }

    func onItemSelected(old: SecureVaultItem?, new: SecureVaultItem?) {
        oldSelection = old
        newSelection = new
    }

    func onAddItemSelected(category: SecureVaultSorting.Category) {}

    private func accounts(from sections: [PasswordManagementListSection]) -> [SecureVaultModels.WebsiteAccount] {
        var accounts = [SecureVaultModels.WebsiteAccount]()

        for section in sections {
            let accountsFromItems: [SecureVaultModels.WebsiteAccount] = section.items.compactMap {
                switch $0 {
                case .account(let account): return account
                default: return nil
                }
            }

            accounts.append(contentsOf: accountsFromItems)
        }

        return accounts
    }

    private func makeModel(with featureFlagger: FeatureFlagger?,
                           accounts: [SecureVaultItem],
                           category: SecureVaultSorting.Category,
                           filter: String) -> PasswordManagementItemListModel {
        let model = PasswordManagementItemListModel(onItemSelected: onItemSelected,
                                                    onAddItemSelected: onAddItemSelected,
                                                    featureFlagger: featureFlagger)
        model.update(items: accounts)
        model.sortDescriptor.category = category
        model.filter = filter
        return model
    }

    private func assertSelectedMatchesFirstFilteredAccount(model: PasswordManagementItemListModel,
                                                           filteredAccounts: [SecureVaultModels.WebsiteAccount]) {
        guard let firstAccountId = filteredAccounts.first?.id,
              let expectedId = Int64(firstAccountId) else {
            XCTFail("Failed to get account ID for comparison")
            return
        }
        XCTAssertEqual(model.selected?.secureVaultID, expectedId)
    }

}

extension PasswordManagementItemListModel {

    convenience init(onItemSelected: @escaping (_ old: SecureVaultItem?, _ new: SecureVaultItem?) -> Void,
                     onAddItemSelected: @escaping (_ category: SecureVaultSorting.Category) -> Void,
                     featureFlagger: FeatureFlagger? = nil) {
        self.init(passwordManagerCoordinator: PasswordManagerCoordinatingMock(), syncPromoManager: SyncPromoManager(),
                  featureFlagger: featureFlagger,
                  onItemSelected: onItemSelected,
                  onAddItemSelected: onAddItemSelected)
    }

}
