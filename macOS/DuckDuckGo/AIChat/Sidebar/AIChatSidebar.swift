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
import AIChat

/// A wrapper class that represents the AI Chat sidebar contents and its displayed view controller.

final class AIChatSidebar: NSObject {

    /// The initial AI chat URL to be loaded.
    private let initialAIChatURL: URL

    private let burnerMode: BurnerMode

    /// The AI chat URL that was active in the sidebar.
    private(set)  var aiChatURL: URL?

    /// The AI chat restoration data that was active in the sidebar.
    private(set) var restorationData: AIChatRestorationData?

    /// Indicates whether the sidebar is currently presented in the UI.
    /// This is separate from whether a view controller exists, as view controllers can be created
    /// during state restoration before the sidebar is actually shown.
    private(set) var isPresented: Bool = false

    /// The date when the sidebar was last hidden, if applicable.
    private(set) var hiddenAt: Date?

    /// The view controller that displays the sidebar contents.
    /// This property is set by the AIChatSidebarProvider when the view controller is created.
    var sidebarViewController: AIChatSidebarViewController?

    /// The current AI chat URL being displayed.
    public var currentAIChatURL: URL {
        get {
            if let sidebarViewController {
                return sidebarViewController.currentAIChatURL
            } else {
                return aiChatURL ?? initialAIChatURL
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

    /// Marks the sidebar as presented in the UI.
    /// Call this when the sidebar is actually shown to the user.
    public func setRevealed() {
        isPresented = true
        hiddenAt = nil
    }

    /// Marks the sidebar as hidden/not presented in the UI.
    /// Call this when the sidebar is hidden from the user.
    public func setHidden(at date: Date = Date()) {
        isPresented = false
        if hiddenAt == nil {
            hiddenAt = date
        }
    }

    /// Unloads the sidebar view controller after reading and updating the current AI chat URL and restoration data.
    /// This method ensures the current URL state and restoration data are captured before the view controller is unloaded.
    /// Also marks the sidebar as hidden since the view controller is being unloaded.
    public func unloadViewController(persistingState: Bool) {
        if let sidebarViewController {
            if persistingState {
                aiChatURL = sidebarViewController.currentAIChatURL
                if let restorationData = sidebarViewController.currentAIChatRestorationData {
                    self.restorationData = restorationData
                }
            }
            sidebarViewController.stopLoading()
            sidebarViewController.removeCompletely()
            self.sidebarViewController = nil
        }

        setHidden()
    }

#if DEBUG
    /// Test-only method to set the hiddenAt date for testing session timeout scenarios
    func updateHiddenAt(_ date: Date?) {
        hiddenAt = date
    }
#endif
}

// MARK: - NSSecureCoding

extension AIChatSidebar: NSSecureCoding {

    private enum CodingKeys {
        static let initialAIChatURL = "initialAIChatURL"
        static let isPresented = "isPresented"
    }

    convenience init?(coder: NSCoder) {
        let initialAIChatURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.initialAIChatURL) as URL?
        self.init(initialAIChatURL: initialAIChatURL, burnerMode: .regular)
        self.isPresented = coder.decodeIfPresent(at: CodingKeys.isPresented) ?? true
    }

    func encode(with coder: NSCoder) {
        coder.encode(currentAIChatURL as NSURL, forKey: CodingKeys.initialAIChatURL)
        coder.encode(isPresented, forKey: CodingKeys.isPresented)
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
