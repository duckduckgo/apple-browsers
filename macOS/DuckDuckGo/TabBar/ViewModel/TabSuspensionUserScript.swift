//
//  TabSuspensionUserScript.swift
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

import Common
import FoundationExtensions
import Foundation
import UserScript
import WebKit

protocol TabSuspensionUserScriptDelegate: AnyObject {
    @MainActor
    func tabSuspensionUserScript(_ script: TabSuspensionUserScript, didReceiveCanBeSuspended canBeSuspended: Bool)
}

/// A subfeature that handles tab suspension eligibility notifications from Content Scope Scripts.
final class TabSuspensionUserScript: NSObject, Subfeature {

    struct CanBeSuspendedPayload: Codable {
        let canBeSuspended: Bool
    }

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "tabSuspension"

    weak var broker: UserScriptMessageBroker?
    weak var delegate: TabSuspensionUserScriptDelegate?

    override init() {
        super.init()
    }

    enum MessageNames: String, CaseIterable {
        case canBeSuspended
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .canBeSuspended:
            return { [weak self] in try await self?.handleCanBeSuspended(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func handleCanBeSuspended(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload: CanBeSuspendedPayload = DecodableHelper.decode(from: params) else { return nil }
        delegate?.tabSuspensionUserScript(self, didReceiveCanBeSuspended: payload.canBeSuspended)
        return nil
    }
}
