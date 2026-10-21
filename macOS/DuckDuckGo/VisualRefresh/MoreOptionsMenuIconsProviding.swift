//
//  MoreOptionsMenuIconsProviding.swift
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

import AppKit
import DesignResourcesKitIcons

protocol MoreOptionsMenuIconsProviding {
    var sendFeedbackIcon: NSImage { get }
    var addToDockIcon: NSImage { get }
    var setAsDefaultBrowserIcon: NSImage { get }
    var newTabIcon: NSImage { get }
    var newWindowIcon: NSImage { get }
    var newFireWindowIcon: NSImage { get }
    var newAIChatIcon: NSImage { get }
    var zoomIcon: NSImage { get }
    var zoomInIcon: NSImage { get }
    var zoomOutIcon: NSImage { get }
    var enterFullscreenIcon: NSImage { get }
    var changeDefaultZoomIcon: NSImage { get }
    var bookmarksIcon: NSImage { get }
    var downloadsIcon: NSImage { get }
    var historyIcon: NSImage { get }
    var passwordsIcon: NSImage { get }
    var syncIcon: NSImage { get }
    var deleteBrowsingDataIcon: NSImage { get }
    var emailProtectionIcon: NSImage { get }
    var subscriptionIcon: NSImage { get }
    var fireproofSiteIcon: NSImage { get }
    var removeFireproofIcon: NSImage { get }
    var findInPageIcon: NSImage { get }
    var shareIcon: NSImage { get }
    var printIcon: NSImage { get }
    var helpIcon: NSImage { get }
    var settingsIcon: NSImage { get }

    /// Send Feedback Sub-Menu
    var browserFeedbackIcon: NSImage { get }
    var reportBrokenSiteIcon: NSImage { get }
    var sendSubscriptionFeedbackIcon: NSImage { get }

    /// Password & Autofill Sub-Menu
    var passwordsSubMenuIcon: NSImage { get }
    var identitiesIcon: NSImage { get }
    var creditCardsIcon: NSImage { get }

    /// PrivacyPro Sub-Menu
    var vpnIcon: NSImage? { get }
    var personalInformationRemovalIcon: NSImage { get }
    var paidAIChat: NSImage { get }
    var identityTheftRestorationIcon: NSImage { get }

    /// Email Protection Sub-Menu
    var emailGenerateAddressIcon: NSImage { get }
    var emailManageAccount: NSImage { get }
    var emailProtectionTurnOffIcon: NSImage { get }
    var emailProtectionTurnOnIcon: NSImage { get }

    /// Bookmarks Sub-Menu
    var favoritesIcon: NSImage { get }
}

final class LegacyMoreOptionsMenuIcons: MoreOptionsMenuIconsProviding {
    let sendFeedbackIcon: NSImage = NSImage(resource: .sendFeedback)
    let addToDockIcon: NSImage = NSImage(resource: .addToDockMenuItem)
    let setAsDefaultBrowserIcon: NSImage = NSImage(resource: .defaultBrowserMenuItem)
    let newTabIcon: NSImage = NSImage(resource: .add)
    let newWindowIcon: NSImage = NSImage(resource: .newWindow)
    let newFireWindowIcon: NSImage = NSImage(resource: .newBurnerWindow)
    let newAIChatIcon: NSImage = NSImage(resource: .aiChat)
    let zoomIcon: NSImage = NSImage(resource: .zoomIn)
    let zoomInIcon: NSImage = NSImage(resource: .zoomIn)
    let zoomOutIcon: NSImage = NSImage(resource: .zoomOut)
    let enterFullscreenIcon: NSImage = NSImage(resource: .zoomFullScreen)
    let changeDefaultZoomIcon: NSImage = NSImage(resource: .zoomChangeDefault)
    let bookmarksIcon: NSImage = NSImage(resource: .bookmarks)
    let downloadsIcon: NSImage = NSImage(resource: .downloads)
    let historyIcon: NSImage = NSImage(resource: .history)
    let passwordsIcon: NSImage = NSImage(resource: .passwordManagement)
    let deleteBrowsingDataIcon: NSImage = NSImage(resource: .burn)
    let emailProtectionIcon: NSImage = NSImage(resource: .optionsButtonMenuEmail)
    let subscriptionIcon: NSImage = NSImage(resource: .subscriptionIcon)
    let fireproofSiteIcon: NSImage = NSImage(resource: .fireproof)
    let removeFireproofIcon: NSImage = NSImage(resource: .burn)
    let findInPageIcon: NSImage = NSImage(resource: .findSearch)
    let shareIcon: NSImage = NSImage(resource: .share)
    let printIcon: NSImage = NSImage(resource: .print)
    let helpIcon: NSImage = NSImage(resource: .helpMenuItemIcon)
    let settingsIcon: NSImage = NSImage(resource: .preferences)
    let browserFeedbackIcon: NSImage = NSImage(resource: .browserFeedback)
    let reportBrokenSiteIcon: NSImage = NSImage(resource: .siteBreakage)
    let sendSubscriptionFeedbackIcon: NSImage = NSImage(resource: .pProFeedback)
    let passwordsSubMenuIcon: NSImage = NSImage(resource: .loginGlyph)
    var syncIcon: NSImage = DesignSystemImages.Glyphs.Size16.sync
    let identitiesIcon: NSImage = NSImage(resource: .identityGlyph)
    let creditCardsIcon: NSImage = NSImage(resource: .creditCardGlyph)
    let vpnIcon: NSImage? = .image(for: .vpnIcon)
    let personalInformationRemovalIcon: NSImage = NSImage(resource: .dbpIcon)
    let paidAIChat: NSImage = NSImage(resource: .aiChat)
    let identityTheftRestorationIcon: NSImage = NSImage(resource: .itrIcon)
    let emailGenerateAddressIcon: NSImage = NSImage(resource: .optionsButtonMenuEmailGenerateAddress)
    let emailManageAccount: NSImage = NSImage(resource: .identity16)
    let emailProtectionTurnOffIcon: NSImage = NSImage(resource: .emailDisabled16)
    let emailProtectionTurnOnIcon: NSImage = NSImage(resource: .optionsButtonMenuEmail)
    let favoritesIcon: NSImage = NSImage(resource: .favorite)
}

final class CurrentMoreOptionsMenuIcons: MoreOptionsMenuIconsProviding {
    let sendFeedbackIcon: NSImage = DesignSystemImages.Glyphs.Size12.feedback
    let addToDockIcon: NSImage = DesignSystemImages.Glyphs.Size12.addToTaskbar
    let setAsDefaultBrowserIcon: NSImage = DesignSystemImages.Glyphs.Size12.browserDefault
    let newTabIcon: NSImage = DesignSystemImages.Glyphs.Size12.add
    let newWindowIcon: NSImage = DesignSystemImages.Glyphs.Size12.windowNew
    let newFireWindowIcon: NSImage = DesignSystemImages.Glyphs.Size12.fireWindow
    let newAIChatIcon: NSImage = DesignSystemImages.Glyphs.Size12.aiChat
    let zoomIcon: NSImage = DesignSystemImages.Glyphs.Size12.zoomIn
    let zoomInIcon: NSImage = DesignSystemImages.Glyphs.Size12.zoomIn
    let zoomOutIcon: NSImage = DesignSystemImages.Glyphs.Size12.zoomOut
    let enterFullscreenIcon: NSImage = DesignSystemImages.Glyphs.Size12.expand
    let changeDefaultZoomIcon: NSImage = DesignSystemImages.Glyphs.Size12.accessibility
    let bookmarksIcon: NSImage = DesignSystemImages.Glyphs.Size12.bookmarks
    let downloadsIcon: NSImage = DesignSystemImages.Glyphs.Size12.download
    let historyIcon: NSImage = DesignSystemImages.Glyphs.Size12.history
    let passwordsIcon: NSImage = DesignSystemImages.Glyphs.Size12.keyLogin
    var syncIcon: NSImage = DesignSystemImages.Glyphs.Size12.sync
    let deleteBrowsingDataIcon: NSImage = DesignSystemImages.Glyphs.Size12.fire
    let emailProtectionIcon: NSImage = DesignSystemImages.Glyphs.Size12.email
    let subscriptionIcon: NSImage = DesignSystemImages.Glyphs.Size12.subscription
    let fireproofSiteIcon: NSImage = DesignSystemImages.Glyphs.Size12.fireproof
    let removeFireproofIcon: NSImage = DesignSystemImages.Glyphs.Size12.fire
    let findInPageIcon: NSImage = DesignSystemImages.Glyphs.Size12.searchFind
    let shareIcon: NSImage = DesignSystemImages.Glyphs.Size12.shareApple
    let printIcon: NSImage = DesignSystemImages.Glyphs.Size12.print
    let helpIcon: NSImage = DesignSystemImages.Glyphs.Size12.help
    let settingsIcon: NSImage = DesignSystemImages.Glyphs.Size12.settings
    let browserFeedbackIcon: NSImage = DesignSystemImages.Glyphs.Size12.feedbackAlert
    let reportBrokenSiteIcon: NSImage = DesignSystemImages.Glyphs.Size12.siteBreakage
    let sendSubscriptionFeedbackIcon: NSImage = DesignSystemImages.Glyphs.Size12.subscription
    let passwordsSubMenuIcon: NSImage = DesignSystemImages.Glyphs.Size12.keyLogin
    let identitiesIcon: NSImage = DesignSystemImages.Glyphs.Size12.profile
    let creditCardsIcon: NSImage = DesignSystemImages.Glyphs.Size12.creditCard
    let vpnIcon: NSImage? = DesignSystemImages.Glyphs.Size12.vpnOn
    let personalInformationRemovalIcon: NSImage = DesignSystemImages.Glyphs.Size12.profileBlocked
    let paidAIChat: NSImage = DesignSystemImages.Glyphs.Size12.duckAi
    let identityTheftRestorationIcon: NSImage = DesignSystemImages.Glyphs.Size12.identityTheftRestoration
    let emailGenerateAddressIcon: NSImage = DesignSystemImages.Glyphs.Size12.wand
    let emailManageAccount: NSImage = DesignSystemImages.Glyphs.Size12.profile
    let emailProtectionTurnOffIcon: NSImage = DesignSystemImages.Glyphs.Size12.emailDisabled
    let emailProtectionTurnOnIcon: NSImage = DesignSystemImages.Glyphs.Size12.email
    let favoritesIcon: NSImage = DesignSystemImages.Glyphs.Size12.favorite
}
