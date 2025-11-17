//
//  MockRemoteMessagingActionHandler.swift
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

import Foundation
import RemoteMessaging
@testable import DuckDuckGo

final class MockRemoteMessagingActionHandler: RemoteMessagingActionHandling {
    private(set) var didCallHandleAction = false
    private(set) var capturedRemoteAction: RemoteAction?
    private(set) var capturedPresenter: RemoteMessagingPresenter?
    private(set) var capturedPresentationContext: PresentationContext?

    func handleAction(_ remoteAction: RemoteAction, context: PresentationContext) async {
        didCallHandleAction = true
        capturedRemoteAction = remoteAction
        capturedPresentationContext = context
    }
}
