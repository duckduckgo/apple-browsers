//
//  BWManagement.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation

public protocol BWManagement: AnyObject {
    var status: BWStatus { get }
    var statusPublisher: Published<BWStatus>.Publisher { get }
    var installationService: BWInstallationService { get }

    func initCommunication()
    func cancelCommunication()
    func openBitwarden()
    func sendHandshake()
    func refreshStatusIfNeeded()

    func retrieveCredentials(for url: URL, completion: @escaping ([BWCredential], BWError?) -> Void)
    func create(credential: BWCredential, completion: @escaping (BWError?) -> Void)
    func update(credential: BWCredential, completion: @escaping (BWError?) -> Void)
}

public protocol BWManagementFactory {
    static func makeManager(isBitwardenPasswordManagerProvider: @escaping () -> Bool,
                            showRestartBitwardenAlert: @escaping (/*restartConfirmed:*/ @escaping () -> Void) -> Void) -> BWManagement
}

/// Shared factory namespace implemented by the concrete BWManagement target.
/// App code references this symbol via `BWManagementFactory` to avoid importing `BWManager` directly.
public enum BWIntegrationFactory {}
