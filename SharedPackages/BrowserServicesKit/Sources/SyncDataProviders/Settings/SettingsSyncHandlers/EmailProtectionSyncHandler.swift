//
//  EmailProtectionSyncHandler.swift
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
import BrowserServicesKit
import Combine
import DDGSync
import Persistence

public protocol EmailManagerSyncSupporting: AnyObject {
    func getUsername() throws -> String?
    func getToken() throws -> String?

    func signIn(username: String, token: String) throws
    func signOut(isForced: Bool) throws

    var userDidToggleEmailProtectionPublisher: AnyPublisher<Void, Never> { get }
}

extension SettingsProvider.Setting {
    static let emailProtectionGeneration = SettingsProvider.Setting(key: "email_protection_generation")
}

public final class EmailProtectionSyncHandler: SettingSyncHandler {

    struct Payload: Codable {
        let username: String
        let personalAccessToken: String
    }

    public override var setting: SettingsProvider.Setting {
        .emailProtectionGeneration
    }

    public override func getValue() throws -> String? {
        guard let user = try emailManager.getUsername() else {
            return nil
        }
        guard let token = try emailManager.getToken() else {
            throw SyncError.emailProtectionUsernamePresentButTokenMissing
        }
        let data = try JSONEncoder.snakeCaseKeys.encode(Payload(username: user, personalAccessToken: token))
        return String(bytes: data, encoding: .utf8)
    }

    public override func setValue(_ value: String?, shouldDetectOverride: Bool) throws {

        guard let value, let valueData = value.data(using: .utf8) else {
            if shouldDetectOverride, try emailManager.getUsername() != nil {
                metricsEvents?.fire(.overrideEmailProtectionSettings)
            }
            try emailManager.signOut(isForced: false)
            return
        }

        let payload = try JSONDecoder.snakeCaseKeys.decode(Payload.self, from: valueData)

        if shouldDetectOverride, let username = try emailManager.getUsername(), payload.username != username {
            metricsEvents?.fire(.overrideEmailProtectionSettings)
        }

        try emailManager.signIn(username: payload.username, token: payload.personalAccessToken)
    }

    public override var valueDidChangePublisher: AnyPublisher<Void, Never> {
        emailManager.userDidToggleEmailProtectionPublisher
    }

    public init(emailManager: EmailManagerSyncSupporting) {
        self.emailManager = emailManager
        super.init()
    }

    private let emailManager: EmailManagerSyncSupporting
}
