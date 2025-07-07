# NewTabPage

Table of contents:
* [Introduction](#introduction)
    * [Useful links](#useful-links)
    * [New Tab Page in the macOS browser](#new-tab-page-in-the-macos-browser)
    * [NTP requirements and performance considerations](#ntp-requirements-and-performance-considerations)
* [NewTabPageActionsManager and script clients](#newtabpageactionsmanager-and-script-clients)
    * [NewTabPageActionsManager initialization](#newtabpageactionsmanager-initialization)
* [Module structure](#module-structure)
* [New Tab Page Feature structure](#new-tab-page-feature-structure)
    * [User script client](#user-script-client)
        * [User script messages](#user-script-messages)
        * [Message handlers](#message-handlers)
        * [Sending messages from native to FE](#sending-messages-from-native-to-fe)
    * [User script client's model](#user-script-clients-model)
* [User script clients overview](#user-script-clients-overview)
    * [Configuration client](#configuration-client)
    * [Protections Report client](#protections-report-client)
* [How to add new user script client](#how-to-add-new-user-script-client)
    * [If the widget availability needs to be configurable](#if-the-widget-availability-needs-to-be-configurable)

## Introduction

This module provides resources used for communication between the New Tab Page user script and the native code of the macOS browser app.

### Useful links
* [Content Scope Scripts (C-S-S) repository](https://github.com/duckduckgo/content-scope-scripts)
* [Frontend API documentation for New Tab Page](https://duckduckgo.github.io/content-scope-scripts/documents/New_Tab_Page.html)

### New Tab Page in the macOS browser
macOS New Tab Page (NTP) is a special page in the macOS browser. It's an HTML website served from [C-S-S](#https://github.com/duckduckgo/content-scope-scripts). It's composed of _widgets_ that display various data, such as remote messages, favorites, privacy protection stats, "Next Steps" onboarding, etc. It uses native<>FE messaging for displaying data and passing actions to the native side.

### NTP requirements and performance considerations
* There can be multiple NTP tabs open in the app, in one or multiple windows.
* NTP data needs to be synchronized across all open NTP tabs. For instance, adding a favorite on NTP should update all NTP tabs at the same time. Visiting a website should update protection stats on all open NTP tabs.
    * Some state, however, is specific to a current instance of the NTP tab. For instance, opening Customization panel (to adjust NTP background) shouldn't update all tabs.
* NTP user script, because it's accessing various user data, shouldn't be exposed to any websites other than the New Tab Page.
* Because NTP user script combines multiple widgets, it exposes a large number of messages. Handling it in a single Swift class would make it difficult to maintain going forward.

## NewTabPageActionsManager and script clients

To ensure that multiple NTP tabs stay in sync and don't affect browser performance, the following solutions are in place:
* New Tab Page uses a dedicated web view, other than the regular browsing web view. That web view uses a custom configuration with just 1 user script loaded (`NewTabPageUserScript`). The browser displays NTP web view when on NTP, but whenever navigating away from NTP it switches to the regular browsing web view.
    * There is a single web view per window, and as many NTP web views per app as there are open windows.
* All NTP user scripts (of which there are as many as NTP web views) are connected to a single data source, called `NewTabPageActionsManager`.

To ensure code maintainability, `NewTabPageUserScript` messages are handled by multiple _user script clients_ that subclass `NewTabPageUserScriptClient` class. User script clients are organized per feature, i.e. favorites client, protection stats client, remote messaging client, customization client, etc.

`NewTabPageActionsManager` is an aggregator of multiple `NewTabPageUserScriptClient` instances that connect to multiple `NewTabPageUserScript` instances. It is a subclass of `UserScriptActionsManager` (available from `UserScriptActionsManager` module), that abstracts this behavior for reuse in other special pages, as needed (e.g. settings page, whenever that gets implemented in HTML). Each user script can forward actions to the respective user script client, and each client is able to push data to all user scripts, or just one user script if needed.

At any given time in a running application there is:
* 1 instance of `NewTabPageActionsManager` in the application,
* 1 set of `NewTabPageUserScriptClient` instances (1 instance per feature),
* as many `NewTabPageUserScript` instances as there are windows – all user scripts are registered with the actions manager.

### NewTabPageActionsManager initialization
_(The code described here exists in the app target)_

`NewTabPageActionsManager` is owned by `NewTabPageCoordinator` that is lazily instantiated in `AppDelegate`. The coordinator's job is only to own the actions manager and to send a daily "new tab page shown" pixel when NTP comes on screen.

The actions manager is then used in `BrowserTabViewController` that instantiates and owns a `NewTabPageWebViewModel` instance.

The model manages a web view for displaying NTP, initializes `NewTabPageUserScript`, configures the web view and adds the user script to it. As an extra security measure, the model sets up web view so that navigations outside of the new tab page are blocked (they are performed in a browsing view anyway).

The de facto initializer for `NewTabPageActionsManager` is implemented in `NewTabPageActionsManagerExtension.swift`. It takes a number of app-owned objects as parameters, sets up user script clients and calls the designated `.init(scriptClients:)` initializer.

## Module structure

The `NewTabPage` Swift module is organized into feature subdirectories, e.g. `CustomBackground`, `Favorites`, `NextStepCards`, etc.

Each of the directories contains these files:
* user script client (e.g. `NewTabPageFavoritesClient.swift`),
* the model providing data for the client (e.g. `NewTabPageFavoritesModel.swift`),
* a feature-specific extension of `NewTabPageDataModel` enum (e.g. `NewTabPageDataModel+Favorites.swift`). This contains the definitions of data structures that are used by the user script client (types received from FE in WebKit messages and types expected by FE in message responses),
* additional files as needed.

## New Tab Page Feature structure

### User script client
User script client code is overall very easy and repetitive between various clients. Its features are:
* It must subclass `NewTabPageUserScriptClient`,
* It must define messages supported by this script client,
* It must override `registerMessageHandlers(for:)` and define handlers for each message as private functions.
User script client is typically initialized with the model, and can accept other feature-specific parameters (such as  configuration parameters).

#### User script messages
Messages are typically defined in a `MessageName` enum within the script client type. Message names specific to a given feature are usually prefixed by a feature name and an underscore, e.g. `activity_getData`.

There are three types of messages (the distinction follows https://www.jsonrpc.org/specification):
* _requests_ – message is sent from FE to native and requires a response,
* _notifications_ – message is sent from FE to native and does not expect a response,
* _subscriptions_ – message is sent from native to FE.

**Important:** _Message_ name refers to all 3 types of messages that are exchanged with the website, but of course only requests and notifications need to have handlers registered. This means that not all cases of the enum will be used in `registerMessageHandlers(for:)`.

Example implementation:
```swift
public final class NewTabPagePrivacyStatsClient: NewTabPageUserScriptClient {

    // ... other definitions

    enum MessageName: String, CaseIterable {
        case getData = "stats_getData"
        case onDataUpdate = "stats_onDataUpdate"
        case showLess = "stats_showLess"
        case showMore = "stats_showMore"
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getData.rawValue: { [weak self] in try await self?.getData(params: $0, original: $1) },
            MessageName.showLess.rawValue: { [weak self] in try await self?.showLess(params: $0, original: $1) },
            MessageName.showMore.rawValue: { [weak self] in try await self?.showMore(params: $0, original: $1) }
        ])
    }

```

#### Message handlers
Message handlers typically call the model to perform actions (for _notification_ messages), or query it for data to be returned to FE (for _request_ messages). Sometimes they wrap/unwrap business logic data structures in request/response data structures used by the messaging layer.

Example:
```swift
@MainActor
private func getConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
    let expansion: NewTabPageUserScript.WidgetConfig.Expansion = favoritesModel.isViewExpanded ? .expanded : .collapsed
    return NewTabPageUserScript.WidgetConfig(animation: .viewTransitions, expansion: expansion)
}

@MainActor
private func setConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
    guard let config: NewTabPageUserScript.WidgetConfig = DecodableHelper.decode(from: params) else {
        return nil
    }
    favoritesModel.isViewExpanded = config.expansion == .expanded
    return nil
}
```

Note the use of `DecodableHelper` (from BSK's Common module) to conveniently convert `params` into a data structure conforming to `Decodable` protocol.

#### Sending messages from native to FE
If the script client supports receiving notifications from the native layer, it may set up subscriptions to send messages to FE in response to events. Usually that's done by subscribing to Combine publishers exposed by the model.

Example:
```swift
public init(favoritesModel: NewTabPageFavoritesModel<FavoriteType, ActionHandler>, preferredFaviconSize: Int) {
    self.favoritesModel = favoritesModel
    self.preferredFaviconSize = preferredFaviconSize
    super.init()

    favoritesModel.$favorites.dropFirst()
        .sink { [weak self] favorites in
            Task { @MainActor in
                self?.notifyDataUpdated(favorites)
            }
        }
        .store(in: &cancellables)
}

@MainActor
private func notifyDataUpdated(_ favorites: [NewTabPageFavorite]) {
    let favorites = favoritesModel.favorites.map {
        NewTabPageDataModel.Favorite($0, preferredFaviconSize: preferredFaviconSize)
    }
    pushMessage(named: MessageName.onDataUpdate.rawValue, params: NewTabPageDataModel.FavoritesData(favorites: favorites))
}
```

### User script client's model

The model is a class that interacts with the actual app logic. Its structure is feature-specific and depends on the set of functionalities supported by the NTP widget. Usually a model is initialized with one or more parameters of protocol types that provide functionalities, for example:
* a protocol that provides data from the native app,
* a protocol that provides widget settings storage (e.g. widget visibility),
* a protocol that forwards actions to be handled by the native app.

These protocols are implemented in the browser app code where the model is initialized and fed into `NewTabPageActionsManager`.

Example:
```swift
public protocol NewTabPageRecentActivityProviding: AnyObject {
    func refreshActivity() -> [NewTabPageDataModel.DomainActivity]
    var activityPublisher: AnyPublisher<[NewTabPageDataModel.DomainActivity], Never> { get }
}

public protocol NewTabPageRecentActivityVisibilityProviding: AnyObject {
    var isRecentActivityVisible: Bool { get }
}

public final class NewTabPageRecentActivityModel {

    let activityProvider: NewTabPageRecentActivityProviding
    let actionsHandler: RecentActivityActionsHandling

    public init(activityProvider: NewTabPageRecentActivityProviding, actionsHandler: RecentActivityActionsHandling) {
        self.activityProvider = activityProvider
        self.actionsHandler = actionsHandler
    }
}
```

## User script clients overview

Most of the New Tab Page script clients represent individual NTP widgets, but there are some exceptions. The available user scripts clients are:
* Configuration - for NTP configuration,
* CustomBackground – for managing NTP background and browser theme settings,
* Favorites - for the favorites widget,
* FreemiumDBP - for the Freemium PIR promotion banner,
* NextStepsCards – for Next Steps onboarding,
* Omnibar - for the Search / Duck.ai Omnibar (_WIP_),
* PrivacyStats - for the Privacy Stats widget (Protections Report summary),
* ProtectionsReport - for the Protections Report widget,
* RecentActivity - for the Recent Activity widget (Protections Report details),
* RMF - for remote messages.

### Configuration client

Configuration client does not represent any widget, and instead it provides API to configure New Tab Page:
* declare NTP widgets supported by the native app,
* adjust configuration of widgets that support being configured,
    * currently the configuration is limited only to managing visibility for some widgets (Omnibar, Favorites and Protections Report).
* trigger generic NTP context menu,
    * that menu allows for managing widgets visibility,
    * other context menus in the NTP (e.g. for favorites) are handled in their respective features' clients.
* report diagnostic messages to the native layer, like JS exceptions.

### Protections Report client

Protections Report widget is composed of two sub-widgets. Its own UI is the tracker blocking summary and a segmented control. The control allows to switch between Privacy Stats (called _Summary_ in the UI) and Recent Activity (called _Details_), where each of them has a separate user script client.

## How to add new user script client

1. Create a new subdirectory in the `Sources/NewTabPage` directory of the package called after the feature you're adding (e.g. Favorites).
2. Add `NewTabPage<Feature>Client.swift` replacing `<Feature>` with the feature name.
3. Implement `NewTabPage<Feature>Client` class, subclassing `NewTabPageUserScriptClient`. See [New Tab Page Feature structure](#new-tab-page-feature-structure) for details.
4. If your client represents NTP's top-level widget, you need to register it in the Configuration client.
    * Add the new widget type to `NewTabPageDataModel.WidgetId` (`NewTabPageDataModel+Configuration.swift`).
    * Update the array returned from `NewTabPageConfigurationClient.fetchWidgets()` to include the new widget.
        * The ordering of that array is not important, but by convention the widgets should be listed in order in which they appear on the New Tab Page.
5. If your client widget supports adjustable visibility:
    * Update `NewTabPageSectionsVisibilityProviding` protocol and add  `is<Widget>Visible` and `is<Widget>VisiblePublisher` API, similar to how it's done for Favorites and Protections Report.
    * In `NewTabPageConfigurationClient`:
        * Update subscription in the initializer that calls `notifyWidgetConfigsDidChange()` to include the newly defined publisher.
        * Update the array returned from `fetchWidgetConfigs()` to return configuration for the new widget (similar to Favorites and Protections Report).
        * Update `showContextMenu()` to include the menu option for the new widget (follow definitions for existing widgets).
        * Update `toggleVisibility()` to support toggling visibility of the new widget from the context menu.
        * Update `widgetsSetConfig()` to support toggling visibility of the new widget from the customization sidebar.

### If the widget availability needs to be configurable

If the widget is only meant to be available to some users (e.g. it's kept behind a feature flag, or there's a logic external to NTP that decides the availability), you need to define a new protocol called `NewTabPageSectionsAvailabilityProviding`. This protocol has previously been in use but it was deleted since it wasn't needed anymore. See [this commit in the monorepo](https://github.com/duckduckgo/apple-browsers/blob/06bcac0a5bcbdfad69ee64ace4973e5b19485375/macOS/LocalPackages/NewTabPage/Sources/NewTabPage/Configuration/NewTabPageConfigurationClient.swift) for reference.

The `NewTabPageSectionsAvailabilityProviding` protocol should define a read-only boolean property called `is<Widget>Available`.

Update `NewTabPageConfigurationClient` the following way:
1. Add `private let sectionsAvailabilityProvider: NewTabPageSectionsAvailabilityProviding` and inject it via the initializer.
2. Update `fetchWidgets()` to declare a variable widgets array and conditionally append your widget to the array based on the availability returned by the availability provider.
3. Update `fetchWidgetConfigs()` in a similar way – conditionally append your widget config to the array based on the availability returned by the availability provider.

As the last step, implement the availability provider on the app side and feed it to the Configuration client.
