//
//  AIChatState.swift
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
import AIChat

enum AIChatPresentationMode: String {
    case hidden
    case sidebar
    case floating
}

/// Pure per-tab data model for AI Chat. Contains only persisted state --
/// no view controller references, no Combine plumbing, no AppKit.
/// Transient UI lifecycle is managed by `AIChatSession`.
final class AIChatState: NSObject {

    /// The initial AI chat URL to be loaded.
    private let initialAIChatURL: URL

    /// The AI chat URL that was last active (snapshotted from the VC on teardown).
    var aiChatURL: URL?

    /// Restoration data for resuming the chat session.
    var restorationData: AIChatRestorationData?

    /// The current presentation mode of the AI Chat for this tab.
    private(set) var presentationMode: AIChatPresentationMode = .hidden

    /// The date when the chat was last hidden, if applicable.
    private(set) var hiddenAt: Date?

    /// The user-chosen sidebar width for this tab, or `nil` to use the default.
    var sidebarWidth: CGFloat?

    /// Last known floating window frame for this tab, if chat was detached.
    var floatingWindowFrame: NSRect?

    /// The persisted AI chat URL (falls back to the initial URL).
    var currentAIChatURL: URL {
        aiChatURL ?? initialAIChatURL
    }

    private let aiChatRemoteSettings = AIChatRemoteSettings()

    init(initialAIChatURL: URL? = nil) {
        self.initialAIChatURL = initialAIChatURL ?? aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
    }

    /// Marks the chat as visible in the sidebar.
    func setSidebar() {
        presentationMode = .sidebar
        hiddenAt = nil
    }

    /// Marks the chat as presented in a floating window.
    func setFloating() {
        presentationMode = .floating
        hiddenAt = nil
    }

    /// Marks the chat as hidden.
    func setHidden(at date: Date = Date()) {
        presentationMode = .hidden
        if hiddenAt == nil {
            hiddenAt = date
        }
    }

    /// Returns true if the session has expired based on the configured timeout.
    var isSessionExpired: Bool {
        guard let hiddenAt else { return false }
        return hiddenAt.minutesSinceNow() > aiChatRemoteSettings.sessionTimeoutMinutes
    }

#if DEBUG
    func updateHiddenAt(_ date: Date?) {
        hiddenAt = date
    }
#endif
}

// MARK: - NSSecureCoding

extension AIChatState: NSSecureCoding {

    enum CodingKeys {
        static let initialAIChatURL = "initialAIChatURL"
        static let presentationMode = "presentationMode"
        static let hiddenAt = "hiddenAt"
        static let sidebarWidth = "sidebarWidth"
        static let floatingWindowFrame = "floatingWindowFrame"
        // Legacy key used by old archives before presentationMode enum was introduced.
        static let isPresented = "isPresented"
    }

    convenience init?(coder: NSCoder) {
        let initialAIChatURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.initialAIChatURL) as URL?
        self.init(initialAIChatURL: initialAIChatURL)
        self.presentationMode = Self.decodePresentationMode(from: coder)
        self.hiddenAt = coder.decodeObject(of: NSDate.self, forKey: CodingKeys.hiddenAt) as Date?
        if presentationMode != .hidden {
            self.hiddenAt = nil
        }
        self.sidebarWidth = coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.sidebarWidth).map { CGFloat($0.doubleValue) }
        self.floatingWindowFrame = coder.decodeObject(of: NSValue.self, forKey: CodingKeys.floatingWindowFrame)?.rectValue
    }

    func encode(with coder: NSCoder) {
        coder.encode(currentAIChatURL as NSURL, forKey: CodingKeys.initialAIChatURL)
        coder.encode(presentationMode.rawValue as NSString, forKey: CodingKeys.presentationMode)
        coder.encode(hiddenAt as NSDate?, forKey: CodingKeys.hiddenAt)
        if let sidebarWidth {
            coder.encode(NSNumber(value: sidebarWidth), forKey: CodingKeys.sidebarWidth)
        }
        if let floatingWindowFrame {
            coder.encode(NSValue(rect: floatingWindowFrame), forKey: CodingKeys.floatingWindowFrame)
        }
    }

    static var supportsSecureCoding: Bool {
        return true
    }

    static func decodePresentationMode(from coder: NSCoder) -> AIChatPresentationMode {
        if let raw = coder.decodeObject(of: NSString.self, forKey: CodingKeys.presentationMode) as? String {
            return AIChatPresentationMode(rawValue: raw) ?? .hidden
        }

        let wasPresented: Bool = coder.decodeIfPresent(at: CodingKeys.isPresented) ?? false
        return wasPresented ? .sidebar : .hidden
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
