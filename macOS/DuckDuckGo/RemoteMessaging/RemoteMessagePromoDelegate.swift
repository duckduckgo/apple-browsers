//
//  RemoteMessagePromoDelegate.swift
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

import Combine
import Foundation
import RemoteMessaging

/// Promo delegate for remote messages on a specific surface (NTP or tab bar).
/// Observes ActiveRemoteMessageModel and publishes visibility to PromoService.
/// External promo: PromoService subscribes to isVisiblePublisher and applies fixed result on dismiss.
final class RemoteMessagePromoDelegate: ExternalPromoDelegate {

    private let activeRemoteMessageModel: ActiveRemoteMessageModel
    private let surface: RemoteMessageSurfaceType

    private let visibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.eraseToAnyPublisher() }

    /// When the remote message is dismissed, treat as temporarily dismissed (eligible again when RMF shows another message).
    var resultWhenHidden: PromoResult { .ignored(cooldown: 0) }

    init(activeRemoteMessageModel: ActiveRemoteMessageModel, surface: RemoteMessageSurfaceType) {
        self.activeRemoteMessageModel = activeRemoteMessageModel
        self.surface = surface
        self.visibilitySubject = CurrentValueSubject(false)

        let messagePublisher: AnyPublisher<RemoteMessageModel?, Never> = {
            switch surface {
            case .newTabPage:
                return activeRemoteMessageModel.$newTabPageRemoteMessage.eraseToAnyPublisher()
            case .tabBar:
                return activeRemoteMessageModel.$tabBarRemoteMessage.eraseToAnyPublisher()
            default:
                return Just(nil).eraseToAnyPublisher()
            }
        }()

        messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessageChange(message)
            }
            .store(in: &cancellables)

        handleMessageChange(currentMessage)
    }

    private var currentMessage: RemoteMessageModel? {
        switch surface {
        case .newTabPage:
            return activeRemoteMessageModel.newTabPageRemoteMessage
        case .tabBar:
            return activeRemoteMessageModel.tabBarRemoteMessage
        default:
            return nil
        }
    }

    private func handleMessageChange(_ message: RemoteMessageModel?) {
        let visible = message != nil && (message?.content?.isSupported == true)
        visibilitySubject.send(visible)
    }
}
