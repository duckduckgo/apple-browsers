//
//  SystemSettingsPiPTutorialURLManaging.swift
//  DuckDuckGo
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

import Foundation

// An entity that can register PiP tutorial URL providers for a specific `SystemSettingsPiPTutorialDestination`.
@MainActor
public protocol SystemSettingsPiPTutorialProviderRegistering {
    /// Registers a URL provider for a the specified destination.
    ///
    /// - Parameters:
    ///   - provider: The `PiPTutorialURLProvider` to register for the destination.
    ///   - destination: The destination that the provider should handle.
    func register(_ provider: PiPTutorialURLProvider, for destination: SystemSettingsPiPTutorialDestination)
}

/// An entity that can retrieve PiP tutorial URLs for specific `SystemSettingsPiPTutorialDestination`.
@MainActor
protocol SystemSettingsPiPTutorialURLProviding {
    // Returns a PiP tutorial URL for the specified destination.
    ///
    /// - Parameter destination: The  destination for which to retrieve a tutorial URL.
    /// - Returns: A  URL pointing to the appropriate PiP video tutorial content.
    /// - Throws: `SystemSettingsPiPTutorialURLProviderError.noProviderAvailable` if no provider is registered for the destination,
    ///           or `SystemSettingsPiPTutorialURLProviderError.providerError` if the underlying provider encounters an error.
    func url(for destination: SystemSettingsPiPTutorialDestination) throws(SystemSettingsPiPTutorialURLProviderError) -> URL
}

typealias SystemSettingsPiPTutorialURLManaging = SystemSettingsPiPTutorialURLProviding & SystemSettingsPiPTutorialProviderRegistering
