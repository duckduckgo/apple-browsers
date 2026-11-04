//
//  AIChatBonusFactsProviding.swift
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

import Foundation

/// The information Duck.ai needs to determine whether to show the bonus limit extension offer.
public protocol AIChatBonusFactsProviding {
    /// `true` for a first install within the install window; `false` for a returning user or when the install date isn't known yet.
    var isNewInstall: Bool { get }

    /// `true` when the user has Duck.ai turned on in the browser settings.
    var isAIChatEnabled: Bool { get }
}
