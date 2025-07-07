//
//  NewTabPageRecentActivityClient.swift
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

import Combine
import Common
import os.log
import UserScriptActionsManager
import WebKit

public final class NewTabPageRecentActivityClient: NewTabPageUserScriptClient {

    private let model: NewTabPageRecentActivityModel
    private var cancellables: Set<AnyCancellable> = []

    enum MessageName: String, CaseIterable {
        case getData = "activity_getData"
        case onBurnComplete = "activity_onBurnComplete"
        case onDataUpdate = "activity_onDataUpdate"
        case addFavorite = "activity_addFavorite"
        case removeFavorite = "activity_removeFavorite"
        case removeItem = "activity_removeItem"
        case confirmBurn = "activity_confirmBurn"
        case open = "activity_open"
    }

    public init(model: NewTabPageRecentActivityModel) {
        self.model = model
        super.init()

        model.activityProvider.activityPublisher
            .sink { [weak self] activity in
                Task { @MainActor in
                    self?.notifyDataUpdated(activity)
                }
            }
            .store(in: &cancellables)

        model.actionsHandler.burnDidCompletePublisher
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.notifyBurnDidComplete()
                }
            }
            .store(in: &cancellables)
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getData.rawValue: { [weak self] in try await self?.getData(params: $0, original: $1) },
            MessageName.addFavorite.rawValue: { [weak self] in try await self?.addFavorite(params: $0, original: $1) },
            MessageName.removeFavorite.rawValue: { [weak self] in try await self?.removeFavorite(params: $0, original: $1) },
            MessageName.confirmBurn.rawValue: { [weak self] in try await self?.confirmBurn(params: $0, original: $1) },
            MessageName.open.rawValue: { [weak self] in try await self?.open(params: $0, original: $1) }
        ])
    }

    @MainActor
    private func getData(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        return NewTabPageDataModel.ActivityData(activity: model.activityProvider.refreshActivity())
    }

    @MainActor
    private func notifyDataUpdated(_ activity: [NewTabPageDataModel.DomainActivity]) {
        pushMessage(named: MessageName.onDataUpdate.rawValue, params: NewTabPageDataModel.ActivityData(activity: activity))
    }

    @MainActor
    private func notifyBurnDidComplete() {
        pushMessage(named: MessageName.onBurnComplete.rawValue, params: nil)
    }

    @MainActor
    private func addFavorite(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.ActivityItemAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        model.addFavorite(action.url)
        return nil
    }

    @MainActor
    private func removeFavorite(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.ActivityItemAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        model.removeFavorite(action.url)
        return nil
    }

    @MainActor
    private func confirmBurn(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.ActivityItemAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        let confirmed = await model.confirmBurn(action.url)
        return NewTabPageDataModel.ConfirmBurnResponse(action: confirmed ? .burn : .none)
    }

    @MainActor
    private func open(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let openAction: NewTabPageDataModel.ActivityOpenAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        model.open(openAction.url, sender: .userScript, target: LinkOpenTarget(openAction.target), sourceWindow: original.webView?.window)
        return nil
    }
}
