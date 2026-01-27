//
//  Tab.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Core
import AIChat

/// Type representing the type of tab, e.g. `web` or `aiChat`
enum TabType {
    case web
    case aiChat
}

protocol TabObserver: AnyObject {
 
    func didChange(tab: Tab)
    
}

public class Tab: NSObject, NSCoding {

    struct WeaklyHeldTabObserver {
        weak var observer: TabObserver?
    }
    
    struct NSCodingKeys {
        static let uid = "uid"
        static let link = "link"
        static let viewed = "viewed"
        static let desktop = "desktop"
        static let lastViewedDate = "lastViewedDate"
        static let daxEasterEggLogoURL = "daxEasterEggLogoURL"
        static let contextualChatURL = "contextualChatURL"
        static let type = "type"
        static let supportsTabHistory = "supportsTabHistory"
    }

    private var observersHolder = [WeaklyHeldTabObserver]()
    
    let uid: String

    /// The date last time this tab was displayed.
    ///
    /// - Warning: This value **must not** be used for any other purpose than for inactive tabs buckets aggregation
    /// into a daily pixel in `TabSwitcherOpenDailyPixel`. If you plan to do something else,
    /// read through https://app.asana.com/0/69071770703008/1208795393823862/f and reopen if necessary.
    private(set) var lastViewedDate: Date?

    var isDesktop: Bool = false {
        didSet {
            notifyObservers()
        }
    }
    
    var link: Link? {
        didSet {
            notifyObservers()
        }
    }
    
    var viewed: Bool = false {
        didSet {
            if viewed {
                lastViewedDate = Date()
            }
            notifyObservers()
        }
    }
    
    /// Returns true if the tab is a `aiChat` tab
    var isAITab: Bool {
        type == .aiChat
    }
    
    /// URL of the Dax Easter Egg logo for this tab, displayed in the privacy icon and used for full-screen presentation.
    var daxEasterEggLogoURL: String? {
        didSet {
            Logger.daxEasterEgg.debug("Tab model - Setting logo URL: \(self.daxEasterEggLogoURL ?? "nil") for tab [\(self.uid)]")
        }
    }

    /// URL of the contextual AI chat session for this tab, used to restore chat state across app restarts.
    var contextualChatURL: String?

    /// Indicates whether this tab was created after tab history tracking was implemented.
    /// Legacy tabs (created before this feature) will have incomplete history and should not support tab burning.
    /// - `true`: Tab was created with history tracking enabled (supports tab burning)
    /// - `false`: Legacy tab without complete history (does not support tab burning)
    let supportsTabHistory: Bool

    /// Type of tab: web or AI Chat, derived from the current URL
    private var type: TabType {
        if let link, link.url.isDuckAIURL(debugSettings: aichatDebugSettings) {
            return .aiChat
        }
        return .web
    }
    
    private let aichatDebugSettings: AIChatDebugSettingsHandling

    public init(uid: String? = nil,
                link: Link? = nil,
                viewed: Bool = false,
                desktop: Bool = AppWidthObserver.shared.isLargeWidth,
                lastViewedDate: Date? = nil,
                daxEasterEggLogoURL: String? = nil,
                contextualChatURL: String? = nil,
                supportsTabHistory: Bool = true,
                aichatDebugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings()) {
        self.uid = uid ?? UUID().uuidString
        self.link = link
        self.viewed = viewed
        self.isDesktop = desktop
        self.lastViewedDate = lastViewedDate
        self.daxEasterEggLogoURL = daxEasterEggLogoURL
        self.contextualChatURL = contextualChatURL
        self.supportsTabHistory = supportsTabHistory
        self.aichatDebugSettings = aichatDebugSettings
    }

    public convenience required init?(coder decoder: NSCoder) {
        let uid = decoder.decodeObject(forKey: NSCodingKeys.uid) as? String
        let link = decoder.decodeObject(forKey: NSCodingKeys.link) as? Link
        let viewed = decoder.containsValue(forKey: NSCodingKeys.viewed) ? decoder.decodeBool(forKey: NSCodingKeys.viewed) : true
        let desktop = decoder.containsValue(forKey: NSCodingKeys.desktop) ? decoder.decodeBool(forKey: NSCodingKeys.desktop) : false
        let lastViewedDate = decoder.containsValue(forKey: NSCodingKeys.lastViewedDate) ? decoder.decodeObject(forKey: NSCodingKeys.lastViewedDate) as? Date : nil
        let daxEasterEggLogoURL = decoder.decodeObject(forKey: NSCodingKeys.daxEasterEggLogoURL) as? String
        let contextualChatURL = decoder.decodeObject(forKey: NSCodingKeys.contextualChatURL) as? String
        // Legacy tabs created before tab history tracking will not have this key, so default to false
        let supportsTabHistory = decoder.containsValue(forKey: NSCodingKeys.supportsTabHistory) ? decoder.decodeBool(forKey: NSCodingKeys.supportsTabHistory) : false

        Logger.daxEasterEgg.debug("Tab decode - Restoring logo URL: \(daxEasterEggLogoURL ?? "nil") for tab [\(uid ?? "no-uid")]")

        self.init(uid: uid, link: link, viewed: viewed, desktop: desktop, lastViewedDate: lastViewedDate, daxEasterEggLogoURL: daxEasterEggLogoURL, contextualChatURL: contextualChatURL, supportsTabHistory: supportsTabHistory)
    }

    public func encode(with coder: NSCoder) {
        Logger.daxEasterEgg.debug("Tab encode - Saving logo URL: \(self.daxEasterEggLogoURL ?? "nil") for tab [\(self.uid)]")

        coder.encode(uid, forKey: NSCodingKeys.uid)
        coder.encode(link, forKey: NSCodingKeys.link)
        coder.encode(viewed, forKey: NSCodingKeys.viewed)
        coder.encode(isDesktop, forKey: NSCodingKeys.desktop)
        coder.encode(lastViewedDate, forKey: NSCodingKeys.lastViewedDate)
        coder.encode(daxEasterEggLogoURL, forKey: NSCodingKeys.daxEasterEggLogoURL)
        coder.encode(contextualChatURL, forKey: NSCodingKeys.contextualChatURL)
        coder.encode(supportsTabHistory, forKey: NSCodingKeys.supportsTabHistory)
        // Note: type is not encoded as it's now a computed property based on the link URL
    }

    public override func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? Tab else { return false }
        return link == other.link
    }
    
    func toggleDesktopMode() {
        isDesktop = !isDesktop
    }
    
    func didUpdatePreview() {
        notifyObservers()
    }
    
    func didUpdateFavicon() {
        notifyObservers()
    }
    
    func addObserver(_ observer: TabObserver) {
        guard indexOf(observer) == nil else { return }
        observersHolder.append(WeaklyHeldTabObserver(observer: observer))
    }
    
    func removeObserver(_ observer: TabObserver) {
        guard let index = indexOf(observer) else { return }
        observersHolder.remove(at: index)
    }
    
    private func indexOf(_ observer: TabObserver) -> Int? {
        pruneHolders()
        return observersHolder.firstIndex(where: { $0.observer === observer })
    }
    
    private func notifyObservers() {
        observersHolder.forEach { $0.observer?.didChange(tab: self) }
        pruneHolders()
    }

    private func pruneHolders() {
        observersHolder = observersHolder.filter { $0.observer != nil }
    }

}

// MARK: - URL+AIChat Debug Support

private extension URL {
    /// Returns `true` if the URL is a Duck AI URL or matches the custom debug domain.
    ///
    /// - Matching is based on the host only, not the full URL.
    /// - If `debugSettings.customURL` is `nil`, empty, or invalid, returns the standard `isDuckAIURL` result.
    func isDuckAIURL(debugSettings: AIChatDebugSettingsHandling) -> Bool {
        if isDuckAIURL { return true }
        guard let customURLString = debugSettings.customURL,
              !customURLString.isEmpty,
              let customURL = URL(string: customURLString),
              let customHost = customURL.host,
              let host = self.host else { return false }
        return host.lowercased() == customHost.lowercased()
    }
}
