//
//  NewTabPageConfigurationClient.swift
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

import AppKit
import Combine
import Common
import os.log
import UserScriptActionsManager
import WebKit

public protocol NewTabPageSectionsAvailabilityProviding: AnyObject {
    var isOmnibarAvailable: Bool { get }
}

public protocol NewTabPageSectionsVisibilityProviding: AnyObject {
    var isOmnibarVisible: Bool { get set }
    var isFavoritesVisible: Bool { get set }
    var isProtectionsReportVisible: Bool { get set }

    var isOmnibarVisiblePublisher: AnyPublisher<Bool, Never> { get }
    var isFavoritesVisiblePublisher: AnyPublisher<Bool, Never> { get }
    var isProtectionsReportVisiblePublisher: AnyPublisher<Bool, Never> { get }
}

public protocol NewTabPageLinkOpening {
    func openLink(_ target: NewTabPageDataModel.OpenAction.Target) async
}

public enum NewTabPageConfigurationEvent: Equatable {
    case newTabPageError(message: String)
}

public final class NewTabPageConfigurationClient: NewTabPageUserScriptClient {

    private var cancellables = Set<AnyCancellable>()
    private let sectionsAvailabilityProvider: NewTabPageSectionsAvailabilityProviding
    private let sectionsVisibilityProvider: NewTabPageSectionsVisibilityProviding
    private let omnibarConfigProvider: NewTabPageOmnibarConfigProviding
    private let customBackgroundProvider: NewTabPageCustomBackgroundProviding
    private let contextMenuPresenter: NewTabPageContextMenuPresenting
    private let linkOpener: NewTabPageLinkOpening
    private let eventMapper: EventMapping<NewTabPageConfigurationEvent>?

    public init(
        sectionsAvailabilityProvider: NewTabPageSectionsAvailabilityProviding,
        sectionsVisibilityProvider: NewTabPageSectionsVisibilityProviding,
        omnibarConfigProvider: NewTabPageOmnibarConfigProviding,
        customBackgroundProvider: NewTabPageCustomBackgroundProviding,
        contextMenuPresenter: NewTabPageContextMenuPresenting = DefaultNewTabPageContextMenuPresenter(),
        linkOpener: NewTabPageLinkOpening,
        eventMapper: EventMapping<NewTabPageConfigurationEvent>?
    ) {
        self.sectionsAvailabilityProvider = sectionsAvailabilityProvider
        self.sectionsVisibilityProvider = sectionsVisibilityProvider
        self.omnibarConfigProvider = omnibarConfigProvider
        self.customBackgroundProvider = customBackgroundProvider
        self.contextMenuPresenter = contextMenuPresenter
        self.linkOpener = linkOpener
        self.eventMapper = eventMapper
        super.init()

        Publishers.Merge3(
            sectionsVisibilityProvider.isOmnibarVisiblePublisher,
            sectionsVisibilityProvider.isFavoritesVisiblePublisher,
            sectionsVisibilityProvider.isProtectionsReportVisiblePublisher,
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.notifyWidgetConfigsDidChange()
            }
            .store(in: &cancellables)
    }

    enum MessageName: String, CaseIterable {
        case contextMenu
        case initialSetup
        case open
        case reportInitException
        case reportPageException
        case widgetsSetConfig = "widgets_setConfig"
        case widgetsOnConfigUpdated = "widgets_onConfigUpdated"
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.contextMenu.rawValue: { [weak self] in try await self?.showContextMenu(params: $0, original: $1) },
            MessageName.initialSetup.rawValue: { [weak self] in try await self?.initialSetup(params: $0, original: $1) },
            MessageName.open.rawValue: { [weak self] in try await self?.open(params: $0, original: $1) },
            MessageName.reportInitException.rawValue: { [weak self] in try await self?.reportException(params: $0, original: $1) },
            MessageName.reportPageException.rawValue: { [weak self] in try await self?.reportException(params: $0, original: $1) },
            MessageName.widgetsSetConfig.rawValue: { [weak self] in try await self?.widgetsSetConfig(params: $0, original: $1) }
        ])
    }

    private func fetchWidgets() -> [NewTabPageDataModel.NewTabPageConfiguration.Widget] {
        var widgets: [NewTabPageDataModel.NewTabPageConfiguration.Widget] = [
            .init(id: .rmf),
            .init(id: .freemiumPIRBanner),
            .init(id: .nextSteps),
            .init(id: .favorites),
            .init(id: .protections)
        ]

        if sectionsAvailabilityProvider.isOmnibarAvailable {
            widgets.insert(.init(id: .omnibar), at: 2)
        }

        return widgets
    }

    private func fetchWidgetConfigs() -> [NewTabPageDataModel.NewTabPageConfiguration.WidgetConfig] {
        var configs: [NewTabPageDataModel.NewTabPageConfiguration.WidgetConfig] = [
            .init(id: .favorites, isVisible: sectionsVisibilityProvider.isFavoritesVisible),
            .init(id: .protections, isVisible: sectionsVisibilityProvider.isProtectionsReportVisible)
        ]

        if sectionsAvailabilityProvider.isOmnibarAvailable {
            configs.append(.init(id: .omnibar, isVisible: sectionsVisibilityProvider.isOmnibarVisible))
        }

        return configs
    }

    private func notifyWidgetConfigsDidChange() {
        let widgetConfigs = fetchWidgetConfigs()
        pushMessage(named: MessageName.widgetsOnConfigUpdated.rawValue, params: widgetConfigs)
    }

    @MainActor
    private func showContextMenu(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let menu = NSMenu {
            // Show only when the search box is available
            if sectionsAvailabilityProvider.isOmnibarAvailable {
                NSMenuItem(title: UserText.newTabPageContextMenuSearch,
                           action: #selector(self.toggleVisibility(_:)),
                           target: self,
                           representedObject: NewTabPageDataModel.WidgetId.omnibar,
                           state: sectionsVisibilityProvider.isOmnibarVisible ? .on : .off)
                .withAccessibilityIdentifier("HomePage.Views.Menu.Search")
            }

            NSMenuItem(title: UserText.newTabPageContextMenuFavorites,
                       action: #selector(self.toggleVisibility(_:)),
                       target: self,
                       representedObject: NewTabPageDataModel.WidgetId.favorites,
                       state: sectionsVisibilityProvider.isFavoritesVisible ? .on: .off)
            .withAccessibilityIdentifier("HomePage.Views.Menu.Favorites")

            NSMenuItem(title: UserText.newTabPageContextMenuProtectionsReport,
                       action: #selector(self.toggleVisibility(_:)),
                       target: self,
                       representedObject: NewTabPageDataModel.WidgetId.protections,
                       state: sectionsVisibilityProvider.isProtectionsReportVisible ? .on: .off)
            .withAccessibilityIdentifier("HomePage.Views.Menu.ProtectionsReport")

            // The separator won't be presented if it's the last menu item
            NSMenuItem.separator()

            // Show only when the search box is available and Duck.ai settings are visible
            if sectionsAvailabilityProvider.isOmnibarAvailable && omnibarConfigProvider.isAIChatSettingVisible {

                // Show only when the Search box is visible
                if sectionsVisibilityProvider.isOmnibarVisible {
                    NSMenuItem(title: UserText.newTabPageContextMenuShowDuckAI,
                               action: #selector(self.toggleDuckAI(_:)),
                               target: self,
                               representedObject: 0,
                               state: omnibarConfigProvider.isAIChatShortcutEnabled ? .on : .off)
                    .withAccessibilityIdentifier("HomePage.Views.Menu.ShowDuckAI")
                }

                NSMenuItem(title: UserText.newTabPageContextMenuOpenDuckAISettings,
                           action: #selector(self.openDuckAISettings(_:)),
                           target: self,
                           representedObject: 0)
                .withAccessibilityIdentifier("HomePage.Views.Menu.OpenDuckAISettings")
            }
        }

        if !menu.items.isEmpty {
            contextMenuPresenter.showContextMenu(menu)
        }

        return nil
    }

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        switch sender.representedObject as? NewTabPageDataModel.WidgetId {
        case .omnibar:
            sectionsVisibilityProvider.isOmnibarVisible.toggle()
        case .favorites:
            sectionsVisibilityProvider.isFavoritesVisible.toggle()
        case .protections:
            sectionsVisibilityProvider.isProtectionsReportVisible.toggle()
        default:
            break
        }
    }

    @objc private func toggleDuckAI(_ sender: NSMenuItem) {
        omnibarConfigProvider.isAIChatShortcutEnabled.toggle()
    }

    @objc private func openDuckAISettings(_ sender: NSMenuItem) {
        Task { @MainActor [weak self] in
            await self?.linkOpener.openLink(.duckAISettings)
        }
    }

    @MainActor
    private func initialSetup(params: Any, original: WKScriptMessage) async throws -> Encodable? {
#if DEBUG || REVIEW
        let env = "development"
#else
        let env = "production"
#endif

        let widgets = fetchWidgets()
        let widgetConfigs = fetchWidgetConfigs()
        let customizerData = customBackgroundProvider.customizerData
        let config = NewTabPageDataModel.NewTabPageConfiguration(
            widgets: widgets,
            widgetConfigs: widgetConfigs,
            env: env,
            locale: Bundle.main.preferredLocalizations.first ?? "en",
            platform: .init(name: "macos"),
            settings: .init(customizerDrawer: .init(state: .enabled)),
            customizer: customizerData
        )
        return config
    }

    @MainActor
    private func widgetsSetConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let widgetConfigs: [NewTabPageDataModel.NewTabPageConfiguration.WidgetConfig] = DecodableHelper.decode(from: params) else {
            return nil
        }
        for widgetConfig in widgetConfigs {
            switch widgetConfig.id {
            case .omnibar:
                sectionsVisibilityProvider.isOmnibarVisible = widgetConfig.visibility.isVisible
            case .favorites:
                sectionsVisibilityProvider.isFavoritesVisible = widgetConfig.visibility.isVisible
            case .protections:
                sectionsVisibilityProvider.isProtectionsReportVisible = widgetConfig.visibility.isVisible
            default:
                break
            }
        }
        return nil
    }

    private func open(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let openAction: NewTabPageDataModel.OpenAction = DecodableHelper.decode(from: params) else {
            return nil
        }
        await linkOpener.openLink(openAction.target)
        return nil
    }

    private func reportException(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let exception: NewTabPageDataModel.Exception = DecodableHelper.decode(from: params) else {
            return nil
        }
        eventMapper?.fire(.newTabPageError(message: exception.message))
        Logger.general.error("New Tab Page error: \("\(exception.message)", privacy: .public)")
        return nil
    }
}
