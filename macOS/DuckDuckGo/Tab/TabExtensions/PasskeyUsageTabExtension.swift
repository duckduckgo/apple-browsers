//
//  PasskeyUsageTabExtension.swift
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

import BrowserServicesKit
import Combine
import Foundation
import UserScript

/// Handles passkey detection's messages in tabs without web notifications.
///
/// Passkey detection's messages belong to content-scope-scripts' `webCompat` feature, and a tab takes one handler per
/// feature. With web notifications on, `WebNotificationsHandler` is that handler and passes passkey messages on, so
/// this extension is only added when they're off.
final class PasskeyUsageTabExtension {

    let subfeature: PasskeyUsageSubfeature
    private var cancellables = Set<AnyCancellable>()

    init(contentScopeUserScriptPublisher: some Publisher<ContentScopeUserScript, Never>,
         reporter: PasskeyUsagePixelReporter = PasskeyUsagePixelReporter()) {
        let subfeature = PasskeyUsageSubfeature(reporter: reporter)
        self.subfeature = subfeature

        contentScopeUserScriptPublisher.sink { contentScopeUserScript in
            contentScopeUserScript.registerSubfeature(delegate: subfeature)
        }.store(in: &cancellables)
    }
}

/// The `webCompat` handler this extension registers. It only handles passkey detection's messages.
final class PasskeyUsageSubfeature: NSObject, Subfeature {

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "webCompat"
    weak var broker: UserScriptMessageBroker?

    private let reporter: PasskeyUsagePixelReporter

    init(reporter: PasskeyUsagePixelReporter) {
        self.reporter = reporter
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        reporter.handler(forMethodNamed: methodName)
    }
}

protocol PasskeyUsageTabExtensionProtocol: AnyObject {}

extension PasskeyUsageTabExtension: TabExtension, PasskeyUsageTabExtensionProtocol {
    typealias PublicProtocol = PasskeyUsageTabExtensionProtocol
    func getPublicProtocol() -> PublicProtocol { self }
}
