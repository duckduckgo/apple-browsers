//
//  ContentBlockingRulesLookupTask.swift
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

import Foundation
import WebKit
import TrackerRadarKit

extension ContentBlockerRulesManager {

    final class LookupRulesTask {

        private let sourceManagers: [ContentBlockerRulesSourceManager]

        init(sourceManagers: [ContentBlockerRulesSourceManager]) {
            self.sourceManagers = sourceManagers
        }

        func lookupCachedRulesLists() throws -> [CompilationResult]  {

            let models = sourceManagers.compactMap { $0.makeModel() }
            if models.count != sourceManagers.count {
                // We should only load rule lists, in case we can match every one of the expected ones
                throw WKError(.contentRuleListStoreLookUpFailed)
            }

            var result = [CompilationResult]()
            let group = DispatchGroup()

            for model in models {
                group.enter()

                DispatchQueue.main.async {
                    // This needs to be called from the main thread.
                    WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: model.rulesIdentifier.stringValue) { ruleList, error in
                        guard let ruleList, error == nil else {
                            group.leave()
                            return
                        }

                        result.append(CompilationResult(compiledRulesList: ruleList,
                                                        model: model,
                                                        resultType: .cacheLookup,
                                                        performanceInfo: nil))
                        group.leave()
                    }
                }

            }

            let operationResult = group.wait(timeout: .now() + 6)

            guard operationResult == .success, result.count == models.count else {
                throw WKError(.contentRuleListStoreLookUpFailed)
            }

            return result
        }
    }
}
