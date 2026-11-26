//
//  AIChatToolPermissionPresenter.swift
//  DuckDuckGo
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

import AIChat
import Combine
import PrivacyConfig
import SwiftUI
import UIKit

@MainActor
protocol AIChatNativePermissionPresenting: AnyObject {
    var isSurfaceAvailable: Bool { get }
    var isPresentingPermission: Bool { get }
    var preservesPermissionOnSurfaceChange: Bool { get }
    func owns(_ viewController: UIViewController) -> Bool
    func present(_ prompt: ClientToolPermissionPrompt, decision: @escaping @MainActor (ClientToolPermissionDecision) -> Void) -> Bool
    func withdraw(requestID: String, completion: @escaping @MainActor () -> Void)
    func withdrawActive(completion: @escaping @MainActor () -> Void)
}

extension AIChatNativePermissionPresenting {
    var preservesPermissionOnSurfaceChange: Bool { false }
}

@MainActor
final class AIChatToolPermissionPresenter: AIChatNativePermissionPresenting {

    enum ToolKind {
        case readTabContent
        case searchHistory
        case searchBookmarks
        case listOpenTabs
        case findInPage
        case switchToTab
        case openTab
        case closeTabs

        init?(name: String) {
            switch AIChatBrowserToolsSubfeature(rawValue: name) {
            case .readTabContent: self = .readTabContent
            case .searchHistory: self = .searchHistory
            case .searchBookmarks: self = .searchBookmarks
            case .listOpenTabs: self = .listOpenTabs
            case .findInPage: self = .findInPage
            case .switchToTab: self = .switchToTab
            case .openTab: self = .openTab
            case .closeTabs: self = .closeTabs
            default: return nil
            }
        }
    }

    struct Surface {
        let controller: UIViewController
        let isChanging: AnyPublisher<Bool, Never>?

        init(_ controller: UIViewController, isChanging: AnyPublisher<Bool, Never>? = nil) {
            self.controller = controller
            self.isChanging = isChanging
        }
    }

    @MainActor
    final class SurfaceState: ObservableObject {
        @Published var isChangingSurface = false
    }

    @MainActor
    private final class Presentation {
        let requestID: String
        let window: UIWindow
        let surfaceState = SurfaceState()
        weak var browserWindow: UIWindow?
        weak var owner: UIViewController?
        let previousModalInPresentation: Bool
        var surfaceChanges: AnyCancellable?
        var focusChanges: AnyCancellable?

        init(requestID: String, window: UIWindow, browserWindow: UIWindow, owner: UIViewController) {
            self.requestID = requestID
            self.window = window
            self.browserWindow = browserWindow
            self.owner = owner
            previousModalInPresentation = owner.isModalInPresentation
        }

        func dismiss() {
            surfaceChanges = nil
            focusChanges = nil
            owner?.isModalInPresentation = previousModalInPresentation

            let wasKey = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKey, let browserWindow, !browserWindow.isHidden {
                browserWindow.makeKey()
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
    }

    private let surface: @MainActor () -> Surface?
    private var active: Presentation?
    private var pendingRequestID: String?

    init(surface: @escaping @MainActor () -> Surface?) {
        self.surface = surface
    }

    deinit {
        if let active {
            Task { @MainActor in active.dismiss() }
        }
    }

    var isSurfaceAvailable: Bool { Self.canPresent(from: surface()?.controller) }

    var isPresentingPermission: Bool { active != nil }

    var preservesPermissionOnSurfaceChange: Bool { active != nil }

    func owns(_ viewController: UIViewController) -> Bool {
        active?.window.rootViewController === viewController
    }

    func present(_ prompt: ClientToolPermissionPrompt,
                 decision: @escaping @MainActor (ClientToolPermissionDecision) -> Void) -> Bool {
        guard let cardPrompt = AIChatToolPermissionView.Prompt(prompt) else { return false }
        return presentCard(requestID: prompt.requestID, prompt: cardPrompt, decision: decision)
    }

#if DEBUG || ALPHA
    func previewAccessPrompt(toolNames: [String]) -> Bool {
        guard let prompt = AIChatToolPermissionView.Prompt(mockToolNames: toolNames) else { return false }
        return presentCard(requestID: UUID().uuidString, prompt: prompt) { _ in }
    }
#endif

    private static func canPresent(from owner: UIViewController?) -> Bool {
        guard let owner, owner.viewIfLoaded?.window != nil else { return false }
        var branch: UIViewController? = owner
        var child: UIViewController?
        while let controller = branch {
            guard !controller.isBeingDismissed, !controller.isBeingPresented else { return false }
            if let presented = controller.presentedViewController, presented !== child { return false }
            child = controller
            branch = controller.parent ?? controller.presentingViewController
        }
        return true
    }

    private func presentCard(requestID: String,
                             prompt: AIChatToolPermissionView.Prompt,
                             waitsForKeyboard: Bool = true,
                             decision: @escaping @MainActor (ClientToolPermissionDecision) -> Void) -> Bool {
        guard !isPresentingPermission, pendingRequestID == nil,
              let surface = surface(), Self.canPresent(from: surface.controller),
              let window = surface.controller.viewIfLoaded?.window, let scene = window.windowScene else { return false }

        let overlayLevel = UIWindow.Level(rawValue: window.windowLevel.rawValue + 1)
        guard canTakeFocus(from: window, at: overlayLevel) else {
            guard waitsForKeyboard, !window.isHidden, scene.activationState == .foregroundActive,
                  window.keyboardLayoutGuide.layoutFrame.height > window.safeAreaInsets.bottom else { return false }

            pendingRequestID = requestID
            let wait = NewTabKeyboardHideWait(pixelFiring: nil) { [weak self] in
                guard let self, pendingRequestID == requestID else { return }
                pendingRequestID = nil
                if !presentCard(requestID: requestID, prompt: prompt, waitsForKeyboard: false, decision: decision) {
                    decision(.dismiss)
                }
            }
            wait.start()
            window.endEditing(true)
            return true
        }

        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = overlayLevel
        let presentation = Presentation(requestID: requestID, window: overlay,
                                        browserWindow: window, owner: surface.controller)
        let content = AIChatToolPermissionView(prompt: prompt,
                                               surfaceState: presentation.surfaceState) { [weak self, weak presentation] choice in
            guard let self, let presentation, active === presentation,
                  !presentation.surfaceState.isChangingSurface else { return }
            hideOverlay(presentation)
            decision(choice)
        }
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        controller.view.accessibilityViewIsModal = true
        overlay.backgroundColor = .clear
        overlay.overrideUserInterfaceStyle = window.overrideUserInterfaceStyle
        overlay.rootViewController = controller
        active = presentation

        surface.controller.isModalInPresentation = true
        presentation.surfaceChanges = surface.isChanging?.removeDuplicates().sink { [weak state = presentation.surfaceState] isChanging in
            state?.isChangingSurface = isChanging
        }
        observeBrowserWindowRestoration(for: presentation, browserWindow: window, scene: scene)
        window.endEditing(true)
        overlay.makeKeyAndVisible()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        return true
    }

    func withdraw(requestID: String, completion: @escaping @MainActor () -> Void) {
        if pendingRequestID == requestID { pendingRequestID = nil }
        guard let active, active.requestID == requestID else {
            completion()
            return
        }
        hideOverlay(active)
        completion()
    }

    func withdrawActive(completion: @escaping @MainActor () -> Void) {
        pendingRequestID = nil
        guard let active else {
            completion()
            return
        }
        hideOverlay(active)
        completion()
    }

    private func observeBrowserWindowRestoration(for presentation: Presentation, browserWindow: UIWindow, scene: UIWindowScene) {
        let notifications = NotificationCenter.default
        presentation.focusChanges = notifications.publisher(for: UIWindow.didBecomeKeyNotification, object: browserWindow)
            .merge(with: notifications.publisher(for: UIWindow.didBecomeHiddenNotification))
            .merge(with: notifications.publisher(for: UIScene.didActivateNotification, object: scene))
            .merge(with: notifications.publisher(for: UIResponder.keyboardDidHideNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak presentation, weak browserWindow] _ in
                guard let self, let presentation, let browserWindow, active === presentation,
                      isSurfaceAvailable, canTakeFocus(from: browserWindow, at: presentation.window.windowLevel) else { return }
                presentation.window.makeKey()
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
    }

    private func canTakeFocus(from browserWindow: UIWindow, at level: UIWindow.Level) -> Bool {
        guard !browserWindow.isHidden, browserWindow.isKeyWindow,
              let scene = browserWindow.windowScene, scene.activationState == .foregroundActive else { return false }
        return !scene.windows.contains { !$0.isHidden && $0.windowLevel.rawValue > level.rawValue }
    }

    private func hideOverlay(_ presentation: Presentation) {
        active = nil
        presentation.dismiss()
    }
}
