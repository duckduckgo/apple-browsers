//
//  AIChatSidebar.swift
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

/// A wrapper class that represents the AI Chat sidebar contents and its displayed view controller.

final class AIChatSidebar: NSObject {

    /// The initial AI chat URL to be loaded.
    private let initialAIChatURL: URL

    /// The view controller that displays the sidebar contents.
    /// This property is lazily created when first accessed.
    var sidebarViewController: AIChatSidebarViewController {
        get {
            guard let sidebarViewController = _sidebarViewController else {
                let sidebarViewController = AIChatSidebarViewController(currentAIChatURL: currentAIChatURL)
                _sidebarViewController = sidebarViewController
                return sidebarViewController
            }
            return sidebarViewController
        }
    }

    // swiftlint:disable identifier_name
    private var _sidebarViewController: AIChatSidebarViewController?

    /// The current AI chat URL being displayed.
    private var currentAIChatURL: URL {
        get {
            if let _sidebarViewController {
                return _sidebarViewController.currentAIChatURL
            } else {
                return initialAIChatURL
            }
        }
    }
    // swiftlint:enable identifier_name

    private let aiChatRemoteSettings = AIChatRemoteSettings()

    /// Creates a sidebar wrapper with the specified initial AI chat URL.
    /// - Parameter initialAIChatURL: The initial AI chat URL to load. If nil, defaults to the URL from AIChatRemoteSettings.
    init(initialAIChatURL: URL? = nil) {
        self.initialAIChatURL = initialAIChatURL ?? aiChatRemoteSettings.aiChatURL.forSidebar()
    }
}

// MARK: - NSSecureCoding

extension AIChatSidebar: NSSecureCoding {

    private enum CodingKeys {
        static let initialAIChatURL = "initialAIChatURL"
    }

    convenience init?(coder: NSCoder) {
        let initialAIChatURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.initialAIChatURL) as URL?
        self.init(initialAIChatURL: initialAIChatURL)
    }

    func encode(with coder: NSCoder) {
        coder.encode(currentAIChatURL as NSURL, forKey: CodingKeys.initialAIChatURL)
    }

    static var supportsSecureCoding: Bool {
        return true
    }
}

fileprivate extension URL {

    enum PlacementParameter {
        static let name = "placement"
        static let sidebar = "sidebar"
    }

    func forSidebar() -> URL {
        self.appendingParameter(name: PlacementParameter.name, value: PlacementParameter.sidebar)
    }

}

extension URL {

    public func removingPlacementParameter() -> URL {
        self.removingParameters(named: [PlacementParameter.name])
    }
}
