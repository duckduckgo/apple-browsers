//
//  NewTabPageWinBackOfferClient.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import UserScriptActionsManager
import WebKit

public protocol NewTabPageWinBackOfferBannerProviding {

    var bannerMessage: NewTabPageDataModel.WinBackOfferBannerMessage? { get }

    var bannerMessagePublisher: AnyPublisher<NewTabPageDataModel.WinBackOfferBannerMessage?, Never> { get }

    func dismiss() async

    func action() async
}

public final class NewTabPageWinBackOfferClient: NewTabPageUserScriptClient {

    let winBackOfferBannerProvider: NewTabPageWinBackOfferBannerProviding

    private var cancellables = Set<AnyCancellable>()

    public init(provider: NewTabPageWinBackOfferBannerProviding) {
        self.winBackOfferBannerProvider = provider
        super.init()

        winBackOfferBannerProvider.bannerMessagePublisher
            .sink { [weak self] message in
                self?.notifyMessageDidChange(message)
            }
            .store(in: &cancellables)
    }

    enum MessageName: String, CaseIterable {
        case getData = "winBackOffer_getData"
        case onDataUpdate = "winBackOffer_onDataUpdate"
        case dismiss = "winBackOffer_dismiss"
        case action = "winBackOffer_action"
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getData.rawValue: { [weak self] in try await self?.getData(params: $0, original: $1) },
            MessageName.dismiss.rawValue: { [weak self] in try await self?.dismiss(params: $0, original: $1) },
            MessageName.action.rawValue: { [weak self] in try await self?.action(params: $0, original: $1) },
        ])
    }

    @MainActor
    private func getData(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let message = winBackOfferBannerProvider.bannerMessage else {
            return NewTabPageDataModel.WinBackOfferBannerMessageData(content: nil)
        }

        return NewTabPageDataModel.WinBackOfferBannerMessageData(content: message)
    }

    private func dismiss(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        await winBackOfferBannerProvider.dismiss()
        return nil
    }

    private func action(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        await winBackOfferBannerProvider.action()
        return nil
    }

    private func notifyMessageDidChange(_ message: NewTabPageDataModel.WinBackOfferBannerMessage?) {
        pushMessage(named: MessageName.onDataUpdate.rawValue, params: NewTabPageDataModel.WinBackOfferBannerMessageData(content: message))
    }
}
