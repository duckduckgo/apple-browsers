//
//  AutoconsentTabExtension.swift
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

import Navigation
import Foundation
import Combine
import WebKit
import BrowserServicesKit
import AutoconsentStats
import Common
import os.log

protocol AutoconsentUserScriptProvider {
    var autoconsentUserScript: UserScriptWithAutoconsent { get }
}
extension UserScripts: AutoconsentUserScriptProvider {}

final class AutoconsentTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private var userScriptCancellables = Set<AnyCancellable>()
    private let autoconsentStats: AutoconsentStatsCollecting
    private let featureFlagger: FeatureFlagger
    private let popupManagedSubject = PassthroughSubject<AutoconsentUserScript.AutoconsentDoneMessage, Never>()

    private(set) weak var autoconsentUserScript: UserScriptWithAutoconsent? {
        didSet {
            subscribeToUserScript()
        }
    }

    init(scriptsPublisher: some Publisher<some AutoconsentUserScriptProvider, Never>,
         autoconsentStats: AutoconsentStatsCollecting,
         featureFlagger: FeatureFlagger) {

        self.autoconsentStats = autoconsentStats
        self.featureFlagger = featureFlagger

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.autoconsentUserScript = scripts.autoconsentUserScript
            }
        }.store(in: &cancellables)
    }

    private func subscribeToUserScript() {
        userScriptCancellables.removeAll()
        guard let autoconsentUserScript = autoconsentUserScript as? AutoconsentUserScript else {
            return
        }

        autoconsentUserScript.popupManagedPublisher
            .sink { [weak self] event in
                self?.handlePopupManaged(event)
                self?.popupManagedSubject.send(event)
            }
            .store(in: &userScriptCancellables)
    }

    private func handlePopupManaged(_ message: AutoconsentUserScript.AutoconsentDoneMessage) {
        guard featureFlagger.isFeatureOn(.newTabPageAutoconsentStats) else { return }

        Task {
            let durationInSeconds: TimeInterval = message.duration / 1000.0
            await autoconsentStats.recordAutoconsentAction(clicksMade: Int64(message.totalClicks), timeSpent: durationInSeconds)
        }
    }
}

protocol AutoconsentProtocol: AnyObject {
    var autoconsentUserScript: UserScriptWithAutoconsent? { get }
    var popupManagedPublisher: AnyPublisher<AutoconsentUserScript.AutoconsentDoneMessage, Never> { get }
}

extension AutoconsentTabExtension: AutoconsentProtocol, TabExtension {
    func getPublicProtocol() -> AutoconsentProtocol { self }

    var popupManagedPublisher: AnyPublisher<AutoconsentUserScript.AutoconsentDoneMessage, Never> {
        popupManagedSubject.eraseToAnyPublisher()
    }
}

extension TabExtensions {
    var autoconsent: AutoconsentProtocol? { resolve(AutoconsentTabExtension.self) }
}
