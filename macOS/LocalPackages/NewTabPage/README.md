# NewTabPage

## Purpose
This module provides resources used for communication between the New Tab Page user script and the native code of the macOS browser app.

## New Tab Page in the macOS browser
macOS New Tab Page (NTP) is a special page in the macOS browser. It's an HTML website served from C-S-S. It's composed of _widgets_ that display various data, such as remote messages, favorites, privacy protection stats, "Next Steps" onboarding, etc. It uses native<>FE messaging for displaying data and passing actions to the native side.

### NTP requirements and performance considerations
* There can be multiple NTP tabs open in the app, in one or multiple windows.
* NTP data needs to be synchronized across all open NTP tabs. For instance, adding a favorite on NTP should update all NTP tabs at the same time. Visiting a website should update protection stats on all open NTP tabs.
    * Some state, however, is specific to a current instance of the NTP tab. For instance, opening Customization panel (to adjust NTP background) shouldn't update all tabs.
* NTP user script, because it's accessing various user data, shouldn't be exposed to any websites other than the New Tab Page.
* Because NTP user script combines multiple widgets, it exposes a large number of messages. Handling it in a single Swift class would make it difficult to maintain going forward.

## NewTabPageActionsManager and NewTabPageUserScriptClients

To ensure that multiple NTP tabs stay in sync and don't affect browser performance, the following solutions are in place:

* New Tab Page uses a dedicated web view, other than the regular browsing web view. That web view uses a custom configuration with just 1 user script loaded (`NewTabPageUserScript`). The browser displays NTP web view when on NTP, but whenever navigating away from NTP it switches to the regular browsing web view.
    * There is a single web view per window, and as many NTP web views per app as there are open windows.
* All NTP user scripts (of which there are as many as NTP web views) are connected to a single data source, called `NewTabPageActionsManager`.

To ensure code maintainability, `NewTabPageUserScript` messages are handled by multiple _user script clients_ that subclass `NewTabPageUserScriptClient` class. User script clients are organized per feature, i.e. favorites client, protection stats client, remote messaging client, customization client, etc.

`NewTabPageActionsManager` is an aggregator of multiple `NewTabPageUserScriptClient` instances that connect to multiple `NewTabPageUserScript` instances. It is a subclass of `UserScriptActionsManager` (available from `UserScriptActionsManager` module), that abstracts this behavior for reuse in other special pages, as needed (e.g. settings page, whenever that gets implemented in HTML). Each user script can forward actions to the respective user script client, and each client is able to push data to all user scripts, or just one user script if needed.

At any given time in a running application there is:
* 1 instance of `NewTabPageActionsManager` in the application
* 1 set of `NewTabPageUserScriptClient` instances (1 instance per feature)
* as many `NewTabPageUserScript` instances as there are windows – all user scripts are registered with the actions manager.

## NewTabPageActionsManager initialization

_(The code described here exists in the app target)_

`NewTabPageActionsManager` is owned by `NewTabPageCoordinator` that is lazily instantiated in `AppDelegate`. The coordinator's job is only to own the actions manager and to send a daily "new tab page shown" pixel when NTP comes on screen.

The actions manager is then used in `BrowserTabViewController` that instantiates and owns a `NewTabPageWebViewModel` instance.

The model manages a web view for displaying NTP, initializes `NewTabPageUserScript`, configures the web view and adds the user script to it. As an extra security measure, the model sets up web view so that navigations outside of the new tab page are blocked (they are performed in a browsing view anyway).

The de facto initializer for `NewTabPageActionsManager` is implemented in `NewTabPageActionsManagerExtension.swift`. It takes a number of app-owned objects as parameters, sets up user script clients and calls the designated `.init(scriptClients:)` initializer.

## Module structure

The `NewTabPage` Swift module is organized into feature subdirectories, e.g. `CustomBackground`, `Favorites`, `NextStepCards`, etc.