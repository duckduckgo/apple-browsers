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

protocol AutoconsentUserScriptProvider {
    var autoconsentUserScript: UserScriptWithAutoconsent { get }
}
extension UserScripts: AutoconsentUserScriptProvider {}

/// Provides access to the autoconsent user script for a tab.
/// Event processing (stats, history) is handled centrally by AutoconsentEventCoordinator.
final class AutoconsentTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private(set) weak var autoconsentUserScript: UserScriptWithAutoconsent?

    init(scriptsPublisher: some Publisher<some AutoconsentUserScriptProvider, Never>) {
        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.autoconsentUserScript = scripts.autoconsentUserScript
            }
        }.store(in: &cancellables)
    }
}

// MARK: - AutoconsentProtocol

protocol AutoconsentProtocol: AnyObject {
    var autoconsentUserScript: UserScriptWithAutoconsent? { get }
}

extension AutoconsentTabExtension: AutoconsentProtocol, TabExtension {
    func getPublicProtocol() -> AutoconsentProtocol { self }
}

extension TabExtensions {
    var autoconsent: AutoconsentProtocol? { resolve(AutoconsentTabExtension.self) }
}
