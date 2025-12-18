//
//  ContentBlockingService.swift
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

import ContentBlocking
import BrowserServicesKit
import Core
import DDGSync

final class ContentBlockingService {

    public let common: ContentBlocking
    public let updating: ContentBlockingUpdating
    public let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies

    init(appSettings: AppSettings,
         contentBlocking: ContentBlocking,
         sync: DDGSyncing,
         fireproofing: Fireproofing,
         contentScopeExperimentsManager: ContentScopeExperimentsManaging) {

        common = contentBlocking

        userScriptsDependencies = DefaultScriptSourceProvider.Dependencies(appSettings: appSettings,
                                                                           sync: sync,
                                                                           privacyConfigurationManager: common.privacyConfigurationManager,
                                                                           contentBlockingManager: common.contentBlockingManager,
                                                                           fireproofing: fireproofing,
                                                                           contentScopeExperimentsManager: contentScopeExperimentsManager)

        updating = ContentBlockingUpdating(userScriptsDependencies: userScriptsDependencies)
    }
}
