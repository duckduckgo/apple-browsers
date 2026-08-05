//
//  PageContextCollectionResult.swift
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

/// What a `collectionResult` message from the page-context user script carried. Failures are
/// distinguished so a collection that answered with an error isn't measured as one that never answered.
public enum PageContextCollectionResult: Equatable {

    case collected(AIChatPageContextData)

    /// The script replied with its error envelope, which carries no serialized page data.
    case scriptError

    /// Serialized page data arrived but could not be decoded.
    case decodeFailed

    /// The collected context, or `nil` for either failure.
    public var pageContext: AIChatPageContextData? {
        guard case .collected(let pageContext) = self else { return nil }
        return pageContext
    }
}
