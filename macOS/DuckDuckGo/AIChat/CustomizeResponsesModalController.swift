//
//  CustomizeResponsesModalController.swift
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

import Cocoa
import Combine
import WebKit
import AIChat
import BrowserServicesKit
import Carbon.HIToolbox

/// Hosts the Duck.ai Customize Responses card in a modal over the browser window: a borderless
/// window with a dimming scrim and a centered Duck.ai web view at `?placement=native-customize-modal`.
@MainActor
final class CustomizeResponsesModalController: NSObject {

    var onClose: (() -> Void)?

    private enum Constants {
        static let width: CGFloat = 620
        static let height: CGFloat = 680
    }

    private let tab: Tab
    private var modalWindow: NSWindow?
    private var webViewContainer: WebViewContainerView?
    private weak var parentWindow: NSWindow?
    private var closeCancellable: AnyCancellable?
    private var parentCancellables = Set<AnyCancellable>()
    private var escMonitor: Any?

    deinit {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
        // Safety net if released without dismiss(): detach and hide the child overlay so it (and its
        // web view) doesn't outlive the controller.
        if let modalWindow {
            parentWindow?.removeChildWindow(modalWindow)
            modalWindow.orderOut(nil)
        }
    }

    init(burnerMode: BurnerMode) {
        let url = AIChatURLParameters.nativeCustomizeModalURL(from: AIChatRemoteSettings().aiChatURL)
        // NOT a sidebar tab: isLoadedInSidebar makes the FE report a sidebar host and render the full chat.
        // Match the presenting window's burnerMode so the native-storage bridge shares the menu row's
        // handler (persistent for regular, the burner-scoped in-memory store in a Fire window).
        tab = Tab(content: .url(url, source: .ui), burnerMode: burnerMode, isLoadedInSidebar: false)
        super.init()
    }

    func present(over parentWindow: NSWindow) {
        self.parentWindow = parentWindow

        // One window (scrim background + centered card) avoids the z-order glitch a separate scrim window caused.
        let coverFrame = parentWindow.frame
        let window = CustomizeResponsesModalWindow(contentRect: coverFrame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let scrim = CustomizeResponsesScrimView(frame: NSRect(origin: .zero, size: coverFrame.size))
        scrim.autoresizingMask = [.width, .height]
        scrim.onBackdropClick = { [weak self] in self?.dismiss() }
        window.contentView = scrim

        let card = WebViewContainerView(tab: tab, webView: tab.webView, frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        scrim.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: scrim.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: scrim.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: Constants.width),
            card.heightAnchor.constraint(equalToConstant: Constants.height)
        ])
        tab.webView.allowsMagnification = false
        tab.setDelegate(self)
        modalWindow = window
        webViewContainer = card

        closeCancellable = NotificationCenter.default.publisher(for: .aiChatCustomizeResponsesModalClosed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, (note.object as AnyObject?) === self.tab.webView else { return }
                self.dismiss()
            }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.modalWindow?.isKeyWindow == true, Int(event.keyCode) == kVK_Escape else { return event }
            self.dismiss()
            return nil
        }

        // Tie the modal's lifetime to the parent: dismiss when it closes; re-cover it on resize
        // (moves are handled automatically by the child-window attachment below).
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: parentWindow)
            .sink { [weak self] _ in self?.dismiss() }
            .store(in: &parentCancellables)
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: parentWindow)
            .sink { [weak self] _ in
                guard let self, let parentWindow = self.parentWindow else { return }
                self.modalWindow?.setFrame(parentWindow.frame, display: true)
            }
            .store(in: &parentCancellables)

        window.setFrame(coverFrame, display: true)
        // Attach as a child window so it stays ordered above the parent — otherwise, on app
        // re-activation part of the parent composites in front of the scrim (un-dimmed band) — and
        // follows the parent as it moves.
        parentWindow.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        teardown()
    }

    private func teardown() {
        guard let window = modalWindow else { return } // idempotent

        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        closeCancellable = nil
        parentCancellables.removeAll()
        tab.webView.stopLoading()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        webViewContainer?.removeFromSuperview()
        webViewContainer = nil
        parentWindow?.removeChildWindow(window)
        window.orderOut(nil)
        modalWindow = nil

        onClose?()
        onClose = nil
    }
}

/// Borderless window that can still become key so the hosted web view accepts input.
private final class CustomizeResponsesModalWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Dimming backdrop; clicking outside the centered card dismisses the modal.
private final class CustomizeResponsesScrimView: NSView {
    var onBackdropClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onBackdropClick?()
    }
}

extension CustomizeResponsesModalController: TabDelegate {

    var isInPopUpWindow: Bool { true }

    func tab(_ tab: Tab, createdChild childTab: Tab, of kind: NewWindowPolicy) {
        // Route FE-opened links to a normal browser tab.
        guard let windowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        windowController.mainViewController.tabCollectionViewModel.insertOrAppend(tab: childTab, selected: true)
    }

    func tabWillStartNavigation(_ tab: Tab, isUserInitiated: Bool) {}
    func tabDidStartNavigation(_ tab: Tab) {}
    func tabPageDOMLoaded(_ tab: Tab) {}
    func closeTab(_ tab: Tab) { dismiss() }
    func websiteAutofillUserScriptCloseOverlay(_ websiteAutofillUserScript: BrowserServicesKit.WebsiteAutofillUserScript?) {}
    func websiteAutofillUserScript(_ websiteAutofillUserScript: BrowserServicesKit.WebsiteAutofillUserScript, willDisplayOverlayAtClick: CGPoint?, serializedInputContext: String, inputPosition: CGRect) {}
}
