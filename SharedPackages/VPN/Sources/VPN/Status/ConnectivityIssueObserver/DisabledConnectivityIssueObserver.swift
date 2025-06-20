//
//  DisabledConnectivityIssueObserver.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

/// This is a convenience temporary disabler for the connectivity issues observer.  Will always report no issues.
///
/// This is useful since we decided to momentarily disable connection issue reporting in the UI:
///     ref: https://app.asana.com/0/0/1206071632962016/1206144227620065/f
///
public final class DisabledConnectivityIssueObserver: ConnectivityIssueObserver {
    public var publisher: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
    public var recentValue = false

    public init() {}
}
