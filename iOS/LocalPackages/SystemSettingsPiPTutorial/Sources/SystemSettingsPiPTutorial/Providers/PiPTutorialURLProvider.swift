//
//  PiPTutorialURLProvider.swift
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

/// Errors that can occur when providing PiP video tutorial URLs.
public enum PiPTutorialURLProviderError: Error, Equatable {
    /// The tutorial URL could not be found or is unavailable.
    case urlNotFound
}

/// An entity that can provide a URL for PiP tutorials.
public protocol PiPTutorialURLProvider: AnyObject {
    /// Returns a URL for the PiP tutorial.
    ///
    /// - Returns: A valid URL pointing to the PiP tutorial video.
    /// - Throws: `PiPTutorialURLProviderError.urlNotFound` if the tutorial URL cannot be determined or is unavailable.
    func pipTutorialURL() throws(PiPTutorialURLProviderError) -> URL
}
