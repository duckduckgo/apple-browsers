//
//  URLOpener.swift
//  DuckDuckGo
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

import UIKit

/// A limited number of URL opening strategies.
public enum URLOpenerStrategy {

    case newTab
    case external

}

/// Fire and forget methods for opening URLs
public protocol URLOpener: AnyObject {

    /// Open a URL using the specified strategy
    func open(_ url: URL, withStrategy: URLOpenerStrategy)
}
