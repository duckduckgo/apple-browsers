//
//  DBPUIOptOutEmailOpener.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

final class DBPUIOptOutEmailOpener: DBPUIOptOutEmailOpening {
    private let workspace: DBPUIOptOutEmailWorkspace
    private let providers: [DBPUIOptOutEmailProvider]

    init(workspace: DBPUIOptOutEmailWorkspace = DBPUIOptOutEmailNSWorkspace(),
         appleMailComposer: DBPUIAppleMailComposing = DBPUIAppleMailComposer()) {
        self.workspace = workspace
        self.providers = [
            DBPUIAppleMailOptOutEmailProvider(composer: appleMailComposer),
            DBPUIGmailOptOutEmailProvider(),
            DBPUIOutlookOptOutEmailProvider()
        ]
    }

    init(workspace: DBPUIOptOutEmailWorkspace, providers: [DBPUIOptOutEmailProvider]) {
        self.workspace = workspace
        self.providers = providers
    }

    @MainActor
    func open(_ payload: DBPUIOptOutEmail) -> DBPUIOptOutEmailOpenResult {
        guard let bundleIdentifier = workspace.defaultMailAppBundleIdentifier() else {
            return .failed(providerName: "none", failure: .noMailHandler)
        }

        guard let provider = providers.first(where: { $0.canHandle(mailHandlerBundleIdentifier: bundleIdentifier) }) else {
            return .failed(providerName: "unsupported", failure: .unsupportedMailHandler(bundleIdentifier))
        }

        return provider.open(payload, using: workspace)
    }
}
