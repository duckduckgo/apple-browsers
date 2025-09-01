//
//  SystemSettingsPiPTutorialEventMapper.swift
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

/// A type that can map PiP events for monitoring feature performance.
public protocol SystemSettingsPiPTutorialEventMapper {
    /// Fires an event when the PiP tutorial video fails to load.
    ///
    /// - Parameters:
    ///   - error: The error that occurred during tutorial loading, if available.
    ///   - urlPath: The URL path of the tutorial resource that failed to load, if known.
    func fireFailedToLoadPiPTutorialEvent(error: Error?, urlPath: String?)
}
