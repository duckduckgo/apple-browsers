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

    private let burnerMode: BurnerMode

    /// The most recent AI chat URL that was active in the sidebar.
    private(set)  var mostRecentAIChatURL: URL?

    /// The view controller that displays the sidebar contents.
    /// This property is set by the AIChatSidebarProvider when the view controller is created.
    var sidebarViewController: AIChatSidebarViewController?

    /// The current AI chat URL being displayed.
    private var currentAIChatURL: URL {
        get {
            if let sidebarViewController {
                return sidebarViewController.currentAIChatURL
            } else {
                return mostRecentAIChatURL ?? initialAIChatURL
            }
        }
    }

    private let aiChatRemoteSettings = AIChatRemoteSettings()

    /// Creates a sidebar wrapper with the specified initial AI chat URL.
    /// - Parameter initialAIChatURL: The initial AI chat URL to load. If nil, defaults to the URL from AIChatRemoteSettings.
    init(initialAIChatURL: URL? = nil, burnerMode: BurnerMode) {
        self.initialAIChatURL = initialAIChatURL ?? aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        self.burnerMode = burnerMode
    }

    /// Unloads the sidebar view controller after reading and updating the current AI chat URL.
    /// This method ensures the current URL state is captured before the view controller is unloaded.
    public func unloadViewController(){
        if let sidebarViewController {
            mostRecentAIChatURL = sidebarViewController.currentAIChatURL
            sidebarViewController.stopLoading()
            sidebarViewController.removeCompletely()
            self.sidebarViewController = nil
        }
    }

    override var debugDescription: String {
        return "initialAIChatURL: \(initialAIChatURL), mostRecentAIChatURL: \(mostRecentAIChatURL?.absoluteString ?? "nil"), sidebarViewController: \(sidebarViewController != nil ? "YES" : "NO")"
    }
}

// MARK: - NSSecureCoding

extension AIChatSidebar: NSSecureCoding {

    private enum CodingKeys {
        static let initialAIChatURL = "initialAIChatURL"
    }

    convenience init?(coder: NSCoder) {
        let initialAIChatURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.initialAIChatURL) as URL?
        self.init(initialAIChatURL: initialAIChatURL, burnerMode: .regular)
    }

    func encode(with coder: NSCoder) {
        coder.encode(currentAIChatURL as NSURL, forKey: CodingKeys.initialAIChatURL)
    }

    static var supportsSecureCoding: Bool {
        return true
    }
}

extension URL {

    enum AIChatPlacementParameter {
        public static let name = "placement"
        public static let sidebar = "sidebar"
    }

    public func forAIChatSidebar() -> URL {
        appendingParameter(name: AIChatPlacementParameter.name, value: AIChatPlacementParameter.sidebar)
    }

    public func removingAIChatPlacementParameter() -> URL {
        removingParameters(named: [AIChatPlacementParameter.name])
    }

    public var hasAIChatSidebarPlacementParameter: Bool {
        guard let parameter = self.getParameter(named: AIChatPlacementParameter.name) else {
            return false
        }
        return parameter == AIChatPlacementParameter.sidebar
    }
}
