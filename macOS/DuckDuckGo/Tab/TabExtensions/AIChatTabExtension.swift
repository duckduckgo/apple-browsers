//
//  AIChatTabExtension.swift
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

import Navigation
import Foundation
import Combine
import WebKit
import AIChat

protocol AIChatUserScriptProvider {
    var aiChatUserScript: AIChatUserScript? { get }
}
extension UserScripts: AIChatUserScriptProvider {}

final class AIChatTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private let isLoadedInSidebar: Bool

    private(set) weak var aiChatUserScript: AIChatUserScript?

    init(scriptsPublisher: some Publisher<some AIChatUserScriptProvider, Never>,
         isLoadedInSidebar: Bool) {
        self.isLoadedInSidebar = isLoadedInSidebar
        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.aiChatUserScript = scripts.aiChatUserScript

                // Pass the handoff payload in case it was provided before the user script was loaded
                if let payload = self?.temporaryAIChatNativeHandoffData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
                    self?.temporaryAIChatNativeHandoffData = nil
                }

                if let data = self?.temporaryAIChatRestorationData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
                    self?.temporaryAIChatRestorationData = nil
                }

            }
        }.store(in: &cancellables)
    }

    private var temporaryAIChatNativeHandoffData: AIChatPayload?
    func setAIChatNativeHandoffData(payload: AIChatPayload) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativeHandoffData = payload
            return
        }

        aiChatUserScript.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
    }

    private var temporaryAIChatRestorationData: AIChatRestorationData?
    func setAIChatRestorationData(data: AIChatRestorationData) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatRestorationData = data
            return
        }

        aiChatUserScript.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
    }
}

extension AIChatTabExtension: NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        guard isLoadedInSidebar,
              !navigationAction.navigationType.isSameDocumentNavigation,
              navigationAction.isUserInitiated,
              let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController
        else {
            return .next
        }

        let tabCollectionViewModel = parentWindowController.mainViewController.tabCollectionViewModel
        tabCollectionViewModel.insertOrAppendNewTab(.url(navigationAction.url, source: .link))
        return .cancel
    }
}

protocol AIChatProtocol: AnyObject, NavigationResponder {
    var aiChatUserScript: AIChatUserScript? { get }
    func setAIChatNativeHandoffData(payload: AIChatPayload)
    func setAIChatRestorationData(data: AIChatRestorationData)
}

extension AIChatTabExtension: AIChatProtocol, TabExtension {
    func getPublicProtocol() -> AIChatProtocol { self }
}

extension TabExtensions {
    var aiChat: AIChatProtocol? { resolve(AIChatTabExtension.self) }
}
