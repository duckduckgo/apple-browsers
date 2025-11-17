//
//  MockWhatsNewDisplayModelMapper.swift
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

final class MockWhatsNewDisplayModelMapper: WhatsNewDisplayModelMapping {
    private(set) var didCallMakeDisplayModel = false
    private(set) var capturedMessage: RemoteMessageModel?
    private(set) var capturedOnMessageAppear: (() -> Void)?
    private(set) var capturedOnItemAppear: ((_ itemId: String) -> Void)?
    private(set) var capturedOnItemAction: ((_ action: RemoteAction, _ itemId: String) async -> Void)?
    private(set) var capturedOnPrimaryAction: ((RemoteAction) async -> Void)?
    private(set) var capturedOnDismiss: (() -> Void)?

    // MARK: - Return Value
    var displayModelToReturn: RemoteMessagingUI.CardsListDisplayModel?

    func makeDisplayModel(
        from message: RemoteMessageModel,
        onMessageAppear: @escaping () -> Void,
        onItemAppear: @escaping (_ itemId: String) -> Void,
        onItemAction: @escaping (_ action: RemoteAction, _ itemId: String) async -> Void,
        onPrimaryAction: @escaping (RemoteAction) async -> Void,
        onDismiss: @escaping () -> Void
    ) -> RemoteMessagingUI.CardsListDisplayModel? {
        didCallMakeDisplayModel = true
        capturedMessage = message
        capturedOnMessageAppear = onMessageAppear
        capturedOnItemAppear = onItemAppear
        capturedOnItemAction = onItemAction
        capturedOnPrimaryAction = onPrimaryAction
        capturedOnDismiss = onDismiss

        return displayModelToReturn
    }
}
