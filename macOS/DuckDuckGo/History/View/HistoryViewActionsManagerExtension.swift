//
//  HistoryViewActionsManagerExtension.swift
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

import BrowserServicesKit
import Common
import History
import HistoryView

extension HistoryViewActionsManager {

    convenience init(
        historyCoordinator: HistoryDataSource,
        bookmarksHandler: HistoryViewBookmarksHandling,
        featureFlagger: FeatureFlagger,
        themeManager: ThemeManaging,
        fireproofStatusProvider: DomainFireproofStatusProviding,
        tld: TLD,
        fire: @escaping () async -> FireProtocol
    ) {
        let dataProvider = HistoryViewDataProvider(
            historyDataSource: historyCoordinator,
            historyBurner: FireHistoryBurner(fireproofDomains: fireproofStatusProvider, fire: fire),
            featureFlagger: featureFlagger,
            tld: tld
        )
        let styleProvider = ScriptStyleProvider(themeManager: themeManager)

        self.init(scriptClients: [
            DataClient(
                dataProvider: dataProvider,
                styleProvider: styleProvider,
                actionsHandler: HistoryViewActionsHandler(dataProvider: dataProvider, bookmarksHandler: bookmarksHandler),
                errorHandler: HistoryViewErrorHandler()
            ),
            StyleClient(styleProviding: styleProvider)
        ])
    }
}
