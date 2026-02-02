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
import Combine
import Common
import FeatureFlags
import Foundation
import PrivacyConfig

@objc(Application)
final class Application: NSApplication, WarnBeforeQuitManagerDelegate {

    public static var appDelegate: AppDelegate! // swiftlint:disable:this weak_delegate
    private var fireWindowPreferenceCancellable: AnyCancellable?
    private var featureFlagger: FeatureFlagger { delegateTyped.featureFlagger }

    /// Event interceptor hook for WarnBeforeQuitManager
    /// Returns nil to consume event, or the event to pass through
    private var eventInterceptor: (token: UUID, interceptor: ((NSEvent) -> NSEvent?))?

    public var eventInterceptorToken: UUID? {
        eventInterceptor?.token
    }

    override init() {
        super.init()

        // swizzle `startAccessingSecurityScopedResource` and `stopAccessingSecurityScopedResource`
        // methods to accurately reflect the current number of start and stop calls
        // stored in the associated `NSURL.sandboxExtensionRetainCount` value.
        //
        // See SecurityScopedFileURLController.swift
        NSURL.swizzleStartStopAccessingSecurityScopedResourceOnce()

        let delegate = AppDelegate()
        self.delegate = delegate
        Application.appDelegate = delegate

        let mainMenu = MainMenu(
            featureFlagger: delegate.featureFlagger,
            bookmarkManager: delegate.bookmarkManager,
            historyCoordinator: delegate.historyCoordinator,
            recentlyClosedCoordinator: delegate.recentlyClosedCoordinator,
            faviconManager: delegate.faviconManager,
            defaultBrowserPreferences: delegate.defaultBrowserPreferences,
            aiChatMenuConfig: delegate.aiChatMenuConfiguration,
            internalUserDecider: delegate.internalUserDecider,
            appearancePreferences: delegate.appearancePreferences,
            privacyConfigurationManager: delegate.privacyFeatures.contentBlocking.privacyConfigurationManager,
            isFireWindowDefault: delegate.visualizeFireSettingsDecider.isOpenFireWindowByDefaultEnabled,
            configurationURLProvider: delegate.configurationURLProvider,
            contentScopePreferences: delegate.contentScopePreferences,
            quitSurveyPersistor: QuitSurveyUserDefaultsPersistor(keyValueStore: delegate.keyValueStore)
        )
        self.mainMenu = mainMenu

        // Subscribe to Fire Window preference changes to update menu dynamically
        fireWindowPreferenceCancellable = delegate.dataClearingPreferences.$shouldOpenFireWindowByDefault
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
#endif

    /// This is used to reset the click count to 1 for the next incoming mouse event of the given type.
    /// The hack is used to allow quickly closing tabs by clicking on the close button multiple times
    /// or middle-clicking multiple times to close tabs.
    /// https://app.asana.com/1/137249556945/project/1177771139624306/task/1202049975066624?focus=true
    /// https://app.asana.com/1/137249556945/project/1201048563534612/task/1209477403052191?focus=true
    @MainActor
    var shouldResetClickCountForNextEventOfTypes: Set<NSEvent.EventType>?

    public func installEventInterceptor(token: UUID, interceptor: @escaping (NSEvent) -> NSEvent?) {
        eventInterceptor = (token: token, interceptor: interceptor)
    }

    public func resetEventInterceptor(token: UUID?) {
        guard token == nil || eventInterceptor?.token == token else { return }
        eventInterceptor = nil
    }

    override func sendEvent(_ event: NSEvent) {
#if DEBUG
        // Ignore user events when running Tests
        if [.unitTests, .integrationTests].contains(AppVersion.runType),
           testIgnoredEvents.contains(event.type),
           (NSClassFromString("TestRunHelper") as? NSObject.Type)!.value(forKey: "allowAppSendUserEvents") as? Bool != true {
            return
        }
#endif

        // Check event interceptor hook (for WarnBeforeQuitManager)
        var event = event
        if let interceptor = eventInterceptor?.interceptor {
            guard let interceptedEvent = interceptor(event) else { return } // Event consumed
            // Event passed through, continue processing
            event = interceptedEvent
        }

        // Handle the hack to reset the click count to 1 for the next incoming mouse event of the given type.
        if let expectedEventType = shouldResetClickCountForNextEventOfTypes, expectedEventType.contains(event.type),
           featureFlagger.isFeatureOn(.tabClosingEventRecreation) {
            if event.clickCount > 1 {
                event = {
                    guard let cg = event.cgEvent?.copy() else { return event }
                    cg.setIntegerValueField(.mouseEventClickState, value: 1) // Reset clickCount to 1 to consequently close tabs
                    return NSEvent(cgEvent: cg) ?? event
                }()
            }
            shouldResetClickCountForNextEventOfTypes = nil
        }
        super.sendEvent(event)
    }

}
