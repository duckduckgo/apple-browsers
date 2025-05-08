//
//  DBPService.swift
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

import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import Core

final class DBPService: NSObject {

    private let dbpIOSManager: DataBrokerProtectionIOSManager?

    init(appDependencies: DependencyProvider) {
#if DEBUG || ALPHA
        let dbpSubscriptionManager = DataBrokerProtectionSubscriptionManager(subscriptionManager: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
                                                                          runTypeProvider: appDependencies.dbpSettings,
                                                                          isAuthV2Enabled: appDependencies.isAuthV2Enabled)
        let authManager = DataBrokerProtectionAuthenticationManager(subscriptionManager: dbpSubscriptionManager)
        self.dbpIOSManager = DataBrokerProtectionIOSManagerProvider.iOSManager(authenticationManager: authManager,
                                                                          privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
        DataBrokerProtectionIOSManager.shared = self.dbpIOSManager
#else
        self.dbpIOSManager = nil
#endif
        super.init()
    }

    func onBackground() {
        dbpIOSManager?.scheduleBGProcessingTask()
    }
}
