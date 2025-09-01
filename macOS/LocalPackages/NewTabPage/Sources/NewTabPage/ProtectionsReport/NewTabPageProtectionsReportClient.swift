//
//  NewTabPageProtectionsReportClient.swift
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

public final class NewTabPageProtectionsReportClient: NewTabPageUserScriptClient {

    private let model: NewTabPageProtectionsReportModel
    private var cancellables: Set<AnyCancellable> = []

    enum MessageName: String, CaseIterable {
        case getConfig = "protections_getConfig"
        case getData = "protections_getData"
        case onConfigUpdate = "protections_onConfigUpdate"
        case onDataUpdate = "protections_onDataUpdate"
        case setConfig = "protections_setConfig"
    }

    public init(model: NewTabPageProtectionsReportModel) {
        self.model = model
        super.init()

        Publishers.CombineLatest(model.$isViewExpanded.dropFirst(), model.$activeFeed.dropFirst())
            .map { isExpanded, activeFeed in
                let expansion: NewTabPageUserScript.WidgetConfig.Expansion = isExpanded ? .expanded : .collapsed
                return NewTabPageDataModel.ProtectionsConfig(expansion: expansion, feed: activeFeed, showBurnAnimation: model.shouldShowBurnAnimation)
            }
            .removeDuplicates()
            .sink { [weak self] config in
                Task { @MainActor in
                    self?.notifyConfigUpdated(config)
                }
            }
            .store(in: &cancellables)

        model.statsUpdatePublisher
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.notifyDataUpdated()
                }
            }
            .store(in: &cancellables)

        /// This is not part of the combined publisher above given that sometimes those publishes do not emit
        /// which will that changes to the burn animation to never trigger.
        model.$shouldShowBurnAnimation
            .sink { [weak self] shouldShowBurnAnimation in
                Task { @MainActor in
                    let expansion: NewTabPageUserScript.WidgetConfig.Expansion = model.isViewExpanded ? .expanded : .collapsed
                    let config = NewTabPageDataModel.ProtectionsConfig(expansion: expansion,
                                                                       feed: model.activeFeed,
                                                                       showBurnAnimation: shouldShowBurnAnimation)
                    self?.notifyConfigUpdated(config)
                }
            }
            .store(in: &cancellables)
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getConfig.rawValue: { [weak self] in try await self?.getConfig(params: $0, original: $1) },
            MessageName.getData.rawValue: { [weak self] in try await self?.getData(params: $0, original: $1) },
            MessageName.setConfig.rawValue: { [weak self] in try await self?.setConfig(params: $0, original: $1) }
        ])
    }

    @MainActor
    private func getConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let expansion: NewTabPageUserScript.WidgetConfig.Expansion = model.isViewExpanded ? .expanded : .collapsed
        return NewTabPageDataModel.ProtectionsConfig(expansion: expansion, feed: model.activeFeed, showBurnAnimation: model.shouldShowBurnAnimation)
    }

    @MainActor
    private func notifyConfigUpdated(_ config: NewTabPageDataModel.ProtectionsConfig) {
        pushMessage(named: MessageName.onConfigUpdate.rawValue, params: config)
    }

    @MainActor
    private func setConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let config: NewTabPageDataModel.ProtectionsConfig = CodableHelper.decode(from: params) else {
            return nil
        }
        model.isViewExpanded = config.expansion == .expanded
        model.activeFeed = config.feed
        return nil
    }

    @MainActor
    private func notifyDataUpdated() async {
        pushMessage(
            named: MessageName.onDataUpdate.rawValue,
            params: NewTabPageDataModel.ProtectionsData(
                totalCount: await model.calculateTotalCount()
            )
        )
    }

    @MainActor
    private func getData(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        NewTabPageDataModel.ProtectionsData(totalCount: await model.calculateTotalCount())
    }
}
