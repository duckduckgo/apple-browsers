//
//  Application.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import Foundation
import Combine

@objc(Application)
final class Application: NSApplication {

    public static var appDelegate: AppDelegate! // swiftlint:disable:this weak_delegate
    private var fireWindowPreferenceCancellable: AnyCancellable?

    override init() {
        super.init()

        // swizzle `startAccessingSecurityScopedResource` and `stopAccessingSecurityScopedResource`
        // methods to accurately reflect the current number of start and stop calls
        // stored in the associated `NSURL.sandboxExtensionRetainCount` value.
        //
        // See SecurityScopedFileURLController.swift
        NSURL.swizzleStartStopAccessingSecurityScopedResourceOnce()

#if DEBUG
        if [.unitTests, .integrationTests].contains(AppVersion.runType) {
            (NSClassFromString("TestRunHelper") as? NSObject.Type)!.perform(NSSelectorFromString("sharedInstance"))
        }
#endif

        let delegate = AppDelegate()
        self.delegate = delegate
        Application.appDelegate = delegate

        let mainMenu = MainMenu(
            featureFlagger: delegate.featureFlagger,
            bookmarkManager: delegate.bookmarkManager,
            historyCoordinator: delegate.historyCoordinator,
            faviconManager: delegate.faviconManager,
            aiChatMenuConfig: delegate.aiChatMenuConfiguration,
            internalUserDecider: delegate.internalUserDecider,
            appearancePreferences: delegate.appearancePreferences,
            privacyConfigurationManager: delegate.privacyFeatures.contentBlocking.privacyConfigurationManager,
            isFireWindowDefault: delegate.visualizeFireSettingsDecider.isOpenFireWindowByDefaultEnabled,
            configurationURLProvider: delegate.configurationURLProvider
        )
        self.mainMenu = mainMenu

        // Subscribe to Fire Window preference changes to update menu dynamically
        fireWindowPreferenceCancellable = delegate.dataClearingPreferences.$shouldOpenFireWindowbyDefault
            .dropFirst()
            .sink { [weak mainMenu] isFireWindowDefault in
                mainMenu?.updateMenuItemsPositionForFireWindowDefault(isFireWindowDefault)
                mainMenu?.updateMenuShortcutsFor(isFireWindowDefault)
            }

        // Makes sure Spotlight search is part of Help menu
        self.helpMenu = mainMenu.helpMenu
        self.windowsMenu = mainMenu.windowsMenu
        self.servicesMenu = mainMenu.servicesMenu
    }

    required init?(coder: NSCoder) {
        fatalError("\(Self.self): Bad initializer")
    }

    @objc(_crashOnException:)
    func crash(on exception: NSException) {
        NSGetUncaughtExceptionHandler()?(exception)
    }

#if DEBUG
    var testIgnoredEvents: [NSEvent.EventType] = {
        var testIgnoredEvents: [NSEvent.EventType] = [
            .mouseMoved, .mouseExited, .mouseExited, .mouseEntered,
            .leftMouseUp, .leftMouseUp, .leftMouseDown, .leftMouseDragged,
            .rightMouseUp, .rightMouseUp, .rightMouseDown, .rightMouseDragged,
            .otherMouseUp, .otherMouseUp, .otherMouseDown, .otherMouseDragged,
            .keyDown, .keyUp, .flagsChanged,
            .scrollWheel, .magnify, .rotate, .swipe,
            .directTouch, .gesture, .beginGesture,
            .tabletPoint, .tabletProximity,
            .pressure,
        ]
        if #available(macOS 26.0, *) {
            testIgnoredEvents.append(.init(rawValue: 40)! /* .mouseCancelled */)
        }
        return testIgnoredEvents
    }()
    override func sendEvent(_ event: NSEvent) {
        // Ignore user events when running Tests
        if [.unitTests, .integrationTests].contains(AppVersion.runType),
           testIgnoredEvents.contains(event.type),
           (NSClassFromString("TestRunHelper") as? NSObject.Type)!.value(forKey: "allowAppSendUserEvents") as? Bool != true {
            return
        }
        super.sendEvent(event)
    }
#endif
}
