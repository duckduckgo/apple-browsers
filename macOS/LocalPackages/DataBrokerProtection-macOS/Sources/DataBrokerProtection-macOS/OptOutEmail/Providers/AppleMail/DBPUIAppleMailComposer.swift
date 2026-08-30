//
//  DBPUIAppleMailComposer.swift
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

import AppKit
import DataBrokerProtectionCore

protocol DBPUIAppleMailComposing {
    @MainActor
    func open(_ payload: DBPUIOptOutEmail) -> DBPUIOptOutEmailOpenResult
}

final class DBPUIAppleMailComposer: DBPUIAppleMailComposing {
    @MainActor
    func open(_ payload: DBPUIOptOutEmail) -> DBPUIOptOutEmailOpenResult {
        let items = [payload.body]

        guard let emailService = NSSharingService(named: .composeEmail),
              emailService.canPerform(withItems: items) else {
            return .failed(providerName: "Apple Mail", failure: .appleMailComposeUnavailable)
        }

        emailService.recipients = [payload.to]
        emailService.subject = payload.subject
        emailService.perform(withItems: items)

        return .opened(providerName: "Apple Mail")
    }
}
