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
    var privacyProIcon: NSImage { get }
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
    var sendPrivacyProFeedbackIcon: NSImage { get }

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
    let sendFeedbackIcon: NSImage = .sendFeedback
    let addToDockIcon: NSImage = .addToDockMenuItem
    let setAsDefaultBrowserIcon: NSImage = .defaultBrowserMenuItem
    let newTabIcon: NSImage = .add
    let newWindowIcon: NSImage = .newWindow
    let newFireWindowIcon: NSImage = .newBurnerWindow
    let newAIChatIcon: NSImage = .aiChat
    let zoomIcon: NSImage = .zoomIn
    let zoomInIcon: NSImage = .zoomIn
    let zoomOutIcon: NSImage = .zoomOut
    let enterFullscreenIcon: NSImage = .zoomFullScreen
    let changeDefaultZoomIcon: NSImage = .zoomChangeDefault
    let bookmarksIcon: NSImage = .bookmarks
    let downloadsIcon: NSImage = .downloads
    let historyIcon: NSImage = .history
    let passwordsIcon: NSImage = .passwordManagement
    let deleteBrowsingDataIcon: NSImage = .burn
    let emailProtectionIcon: NSImage = .optionsButtonMenuEmail
    let privacyProIcon: NSImage = .subscriptionIcon
    let fireproofSiteIcon: NSImage = .fireproof
    let removeFireproofIcon: NSImage = .burn
    let findInPageIcon: NSImage = .findSearch
    let shareIcon: NSImage = .share
    let printIcon: NSImage = .print
    let helpIcon: NSImage = .helpMenuItemIcon
    let settingsIcon: NSImage = .preferences
    let browserFeedbackIcon: NSImage = .browserFeedback
    let reportBrokenSiteIcon: NSImage = .siteBreakage
    let sendPrivacyProFeedbackIcon: NSImage = .pProFeedback
    let passwordsSubMenuIcon: NSImage = .loginGlyph
    var syncIcon: NSImage = DesignSystemImages.Glyphs.Size16.sync
    let identitiesIcon: NSImage = .identityGlyph
    let creditCardsIcon: NSImage = .creditCardGlyph
    let vpnIcon: NSImage? = .image(for: .vpnIcon)
    let personalInformationRemovalIcon: NSImage = .dbpIcon
    let paidAIChat: NSImage = .aiChat
    let identityTheftRestorationIcon: NSImage = .itrIcon
    let emailGenerateAddressIcon: NSImage = .optionsButtonMenuEmailGenerateAddress
    let emailManageAccount: NSImage = .identity16
    let emailProtectionTurnOffIcon: NSImage = .emailDisabled16
    let emailProtectionTurnOnIcon: NSImage = .optionsButtonMenuEmail
    let favoritesIcon: NSImage = .favorite
}

final class CurrentMoreOptionsMenuIcons: MoreOptionsMenuIconsProviding {
    let sendFeedbackIcon: NSImage = DesignSystemImages.Glyphs.Size16.feedback
    let addToDockIcon: NSImage = DesignSystemImages.Glyphs.Size16.addToHome
    let setAsDefaultBrowserIcon: NSImage = DesignSystemImages.Glyphs.Size16.setAsDefault
    let newTabIcon: NSImage = DesignSystemImages.Glyphs.Size16.add
    let newWindowIcon: NSImage = DesignSystemImages.Glyphs.Size16.windowNew
    let newFireWindowIcon: NSImage = DesignSystemImages.Glyphs.Size16.fireWindow
    let newAIChatIcon: NSImage = DesignSystemImages.Glyphs.Size16.aiChat
    let zoomIcon: NSImage = DesignSystemImages.Glyphs.Size16.zoomIn
    let zoomInIcon: NSImage = DesignSystemImages.Glyphs.Size16.zoomIn
    let zoomOutIcon: NSImage = DesignSystemImages.Glyphs.Size16.zoomOut
    let enterFullscreenIcon: NSImage = DesignSystemImages.Glyphs.Size16.expand
    let changeDefaultZoomIcon: NSImage = DesignSystemImages.Glyphs.Size16.accessibility
    let bookmarksIcon: NSImage = DesignSystemImages.Glyphs.Size16.bookmarks
    let downloadsIcon: NSImage = DesignSystemImages.Glyphs.Size16.downloads
    let historyIcon: NSImage = DesignSystemImages.Glyphs.Size16.history
    let passwordsIcon: NSImage = DesignSystemImages.Glyphs.Size16.keyLogin
    var syncIcon: NSImage = DesignSystemImages.Glyphs.Size16.sync
    let deleteBrowsingDataIcon: NSImage = DesignSystemImages.Glyphs.Size16.fire
    let emailProtectionIcon: NSImage = DesignSystemImages.Glyphs.Size16.email
    let privacyProIcon: NSImage = DesignSystemImages.Glyphs.Size16.subscription
    let fireproofSiteIcon: NSImage = DesignSystemImages.Glyphs.Size16.fireproof
    let removeFireproofIcon: NSImage = DesignSystemImages.Glyphs.Size16.fire
    let findInPageIcon: NSImage = DesignSystemImages.Glyphs.Size16.findSearch
    let shareIcon: NSImage = DesignSystemImages.Glyphs.Size16.shareApple
    let printIcon: NSImage = DesignSystemImages.Glyphs.Size16.print
    let helpIcon: NSImage = DesignSystemImages.Glyphs.Size16.help
    let settingsIcon: NSImage = DesignSystemImages.Glyphs.Size16.settings
    let browserFeedbackIcon: NSImage = DesignSystemImages.Glyphs.Size16.browser
    let reportBrokenSiteIcon: NSImage = DesignSystemImages.Glyphs.Size16.siteBreakage
    let sendPrivacyProFeedbackIcon: NSImage = DesignSystemImages.Glyphs.Size16.subscription
    let passwordsSubMenuIcon: NSImage = DesignSystemImages.Glyphs.Size16.keyLogin
    let identitiesIcon: NSImage = DesignSystemImages.Glyphs.Size16.profile
    let creditCardsIcon: NSImage = DesignSystemImages.Glyphs.Size16.creditCard
    let vpnIcon: NSImage? = DesignSystemImages.Glyphs.Size16.vpnOn
    let personalInformationRemovalIcon: NSImage = DesignSystemImages.Glyphs.Size16.profileBlocked
    let paidAIChat: NSImage = DesignSystemImages.Glyphs.Size16.aiChat
    let identityTheftRestorationIcon: NSImage = DesignSystemImages.Glyphs.Size16.identityTheftRestoration
    let emailGenerateAddressIcon: NSImage = DesignSystemImages.Glyphs.Size16.wand
    let emailManageAccount: NSImage = DesignSystemImages.Glyphs.Size16.profile
    let emailProtectionTurnOffIcon: NSImage = DesignSystemImages.Glyphs.Size16.emailDisabled
    let emailProtectionTurnOnIcon: NSImage = DesignSystemImages.Glyphs.Size16.email
    let favoritesIcon: NSImage = DesignSystemImages.Glyphs.Size16.favorite
}
