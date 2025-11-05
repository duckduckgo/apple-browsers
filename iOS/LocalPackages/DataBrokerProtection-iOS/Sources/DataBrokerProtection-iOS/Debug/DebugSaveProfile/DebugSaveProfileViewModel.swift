//
//  DebugSaveProfileViewModel.swift
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
import SecureStorage
import DataBrokerProtectionCore
import PixelKit

struct UserData: Codable {
    let firstName: String
    let lastName: String
    let middleName: String?
    let state: String
    let email: String?
    let city: String
    let age: Int
}

struct ProfileUrl: Codable {
    let profileUrl: String
    let identifier: String
}

struct AlertUI {
    var title: String = ""
    var description: String = ""

    static func savedProfile() -> AlertUI {
        AlertUI(title: "Profile saved successfully", description: "You can check the DB browser to see it")
    }

    static func saveProfileError() -> AlertUI {
        AlertUI(title: "Error saving profile", description: "This shouldn't happen")
    }
}

final class NameUI: ObservableObject {
    let id = UUID()
    @Published var first: String
    @Published var middle: String
    @Published var last: String

    init(first: String, middle: String = "", last: String) {
        self.first = first
        self.middle = middle
        self.last = last
    }

    static func empty() -> NameUI {
        .init(first: "", middle: "", last: "")
    }

    func toModel() -> DataBrokerProtectionProfile.Name {
        .init(firstName: first, lastName: last, middleName: middle.isEmpty ? nil : middle)
    }
}

final class AddressUI: ObservableObject {
    let id = UUID()
    @Published var city: String
    @Published var state: String

    init(city: String, state: String) {
        self.city = city
        self.state = state
    }

    static func empty() -> AddressUI {
        .init(city: "", state: "")
    }

    func toModel() -> DataBrokerProtectionProfile.Address {
        .init(city: city, state: state)
    }
}

final class DebugSaveProfileViewModel: ObservableObject {

    @Published var showAlert = false
    var alert: AlertUI?

    @Published var birthYear: String = ""
    @Published var names = [NameUI.empty()]
    @Published var addresses = [AddressUI.empty()]

    private weak var databaseDelegate: DBPIOSInterface.DatabaseDelegate?

    internal init(databaseDelegate: DBPIOSInterface.DatabaseDelegate?) {
        self.databaseDelegate = databaseDelegate
    }

    private func createBrokerProfileQueryData(for broker: DataBroker) -> [BrokerProfileQueryData] {
        let profile: DataBrokerProtectionProfile =
            .init(
                names: names.map { $0.toModel() },
                addresses: addresses.map { $0.toModel() },
                phones: [String](),
                birthYear: Int(birthYear) ?? 1990
            )
        let profileQueries = profile.profileQueries
        var brokerProfileQueryData = [BrokerProfileQueryData]()

        var profileQueryIndex: Int64 = 1
        for profileQuery in profileQueries {
            let fakeScanJobData = ScanJobData(brokerId: 0, profileQueryId: profileQueryIndex, historyEvents: [HistoryEvent]())
            brokerProfileQueryData.append(
                .init(dataBroker: broker, profileQuery: profileQuery.with(id: profileQueryIndex), scanJobData: fakeScanJobData)
            )

            profileQueryIndex += 1
        }

        return brokerProfileQueryData
    }

    func saveProfile() {
        let profile: DataBrokerProtectionProfile =
            .init(
                names: names.map { $0.toModel() },
                addresses: addresses.map { $0.toModel() },
                phones: [String](),
                birthYear: Int(birthYear) ?? 1990
            )
        Task {
            do {
                try await databaseDelegate?.saveProfile(profile)
                Task { @MainActor in
                    self.alert = AlertUI.savedProfile()
                    self.showAlert = true
                }
            } catch {
                assertionFailure()
                Task { @MainActor in
                    self.alert = AlertUI.saveProfileError()
                    self.showAlert = true
                }
            }
        }
    }
}
