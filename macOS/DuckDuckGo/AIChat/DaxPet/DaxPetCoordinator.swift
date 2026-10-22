//
//  DaxPetCoordinator.swift
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
import AppKit
import Combine
import ConcurrencyExtensions
import PrivacyConfig
import SwiftUI

/// Puts Dax on the desktop while the setting is on, and keeps him standing where he was left.
@MainActor
final class DaxPetCoordinator: NSObject {

    private let preferences: DaxPetPreferences
    private var persistor: DaxPetPreferencesPersistor
    private let submitter: DaxPetPromptSubmitting
    private let browsing: DaxPetBrowsing?
    private let browserToolActivity: AnyPublisher<AIChatBrowserToolActivity, Never>?
    private var browserToolActivityCancellable: AnyCancellable?

    private var window: DaxPetWindow?
    private var model: DaxPetViewModel?
    private var enabledCancellable: AnyCancellable?
    private var pointerTimer: Timer?
    private var isPointerOverCharacter = false
    /// When the pointer came to rest on Dax, for the page glance, and whether this rest already asked for one.
    private var pointerRestStartTime: Date?
    private var hasGlancedThisRest = false
    static let glanceRestDuration: TimeInterval = 1.5
    private let notificationCenter: NotificationCenter
    private let isBrowserActive: @MainActor () -> Bool
    private var responseStateCancellable: AnyCancellable?
    private var dayChangeCancellable: AnyCancellable?
    private let now: () -> Date
    private let isInternalUser: () -> Bool
    private lazy var intelligence: DaxPetIntelligence = DaxPetIntelligenceFactory.make()
    private var answers = DaxAnswerTracker()

    init(preferences: DaxPetPreferences,
         persistor: DaxPetPreferencesPersistor,
         submitter: DaxPetPromptSubmitting,
         browsing: DaxPetBrowsing? = nil,
         browserToolActivity: AnyPublisher<AIChatBrowserToolActivity, Never>? = nil,
         notificationCenter: NotificationCenter = .default,
         isBrowserActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
         now: @escaping () -> Date = Date.init,
         isInternalUser: @escaping () -> Bool = { false }) {
        self.preferences = preferences
        self.persistor = persistor
        self.submitter = submitter
        self.browsing = browsing
        self.browserToolActivity = browserToolActivity
        self.notificationCenter = notificationCenter
        self.isBrowserActive = isBrowserActive
        self.now = now
        self.isInternalUser = isInternalUser
    }

    func start() {
        enabledCancellable = preferences.isEffectivelyEnabledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.show()
                } else {
                    self?.dismiss()
                }
            }
    }

    private func show() {
        guard window == nil else { return }

        let model = DaxPetViewModel(submitter: submitter,
                                    intelligence: intelligence,
                                    screenLooker: DaxPetScreenLooker(),
                                    canSeeForegroundApp: { [preferences] in preferences.canSeeForegroundApp },
                                    browsing: browsing,
                                    historyConsent: preferences)
        let window = DaxPetWindow(contentRect: NSRect(origin: .zero, size: DaxPetView.Metrics.windowSize))
        window.contentView = NSHostingView(rootView: DaxPetView(model: model))
        window.delegate = self
        window.onCancel = { [weak model] in model?.endComposing() }
        window.onMouseDown = { [weak model] event in
            guard let character = model?.character,
                  DaxPetView.Metrics.characterFrame().offsetBy(dx: character.strollOffset, dy: 0).contains(event.locationInWindow) else {
                return false
            }
            if event.type == .rightMouseDown {
                character.rightMouseDown(with: event)
            } else {
                character.mouseDown(with: event)
            }
            return true
        }

        model.onHide = { [weak self] in self?.preferences.isEnabled = false }
        model.onNeedsKeyboard = { [weak window] in window?.makeKey() }
        model.caretLocation = { [weak window] promptWidth in
            guard let frame = window?.frame else { return nil }
            let fieldWidth = DaxPetView.Metrics.composingWidth
            let fieldMinX = frame.midX - fieldWidth / 2
            let fieldMidY = frame.minY + DaxPetView.Metrics.padding + DaxPetView.Metrics.controlsHeight / 2
            return NSPoint(x: fieldMinX + DaxPetView.Metrics.promptLeadingInset + min(promptWidth, fieldWidth - 60), y: fieldMidY)
        }
        model.character.onClick = { [weak model] in model?.characterClicked() }
        model.character.onRightClick = { [weak self] event in self?.showMenu(for: event) }
        model.character.onDrop = { [weak model] pasteboard in
            let items = DaxPetDroppedItem.items(from: pasteboard)
            Task { await model?.receive(items) }
        }
        // He strolls within his window, out to where the prompt field would end.
        model.character.strollRoom = (DaxPetView.Metrics.composingWidth - DaxCharacterView.preferredSize.width) / 2
        model.character.onDragEnded = { [weak self] in
            self?.keepOnScreen()
            self?.savePosition()
        }

        self.window = window
        self.model = model
        observeAnswers()
        dressForToday()

        let position = initialPosition()
        window.setFrameOrigin(NSPoint(x: (position.x - DaxPetView.Metrics.windowSize.width / 2).rounded(), y: position.y))
        window.orderFrontRegardless()
        startTrackingPointer()
        model.sayHello()
        Task { [weak model] in await model?.prepareLineVariations() }
    }

    private func dismiss() {
        responseStateCancellable = nil
        browserToolActivityCancellable = nil
        dayChangeCancellable = nil
        answers = DaxAnswerTracker()
        model?.endComposing()
        window?.orderOut(nil)
        window?.close()
        window = nil
        model = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    // MARK: - Quick actions

    private func showMenu(for event: NSEvent) {
        guard let model, let view = window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let summarize = NSMenuItem(title: UserText.daxPetMenuSummarize, action: #selector(summarizePage), keyEquivalent: "")
        summarize.isEnabled = model.canSummarizeCurrentPage
        menu.addItem(summarize)
        menu.addItem(NSMenuItem(title: UserText.daxPetMenuContinueChat, action: #selector(continueLastChat), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(outfitMenuItem())
        if isInternalUser() {
            menu.addItem(debugMenuItem())
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: UserText.daxPetOpenDuckAI, action: #selector(openDuckAI), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: UserText.daxPetHide, action: #selector(hide), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func outfitMenuItem() -> NSMenuItem {
        let current = persistor.wardrobe
        let submenu = NSMenu()
        func add(_ title: String, _ wardrobe: DaxWardrobe) {
            let item = NSMenuItem(title: title, action: #selector(chooseOutfit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = wardrobe.rawValue
            item.state = wardrobe == current ? .on : .off
            submenu.addItem(item)
        }
        add(UserText.daxPetOutfitSeasonal, .seasonal)
        submenu.addItem(.separator())
        DaxOutfit.allCases.forEach { add($0.title, .outfit($0)) }
        submenu.addItem(.separator())
        add(UserText.daxPetOutfitNone, .none)

        let item = NSMenuItem(title: UserText.daxPetMenuOutfit, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// Internal only: every pose on demand.
    private func debugMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for (index, action) in DaxPetViewModel.DebugAction.allCases.enumerated() {
            let item = NSMenuItem(title: action.title, action: #selector(playDebugAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Debug: Poses", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func playDebugAction(_ sender: NSMenuItem) {
        let actions = DaxPetViewModel.DebugAction.allCases
        guard actions.indices.contains(sender.tag) else { return }
        model?.debugPlay(actions[sender.tag])
    }

    @objc private func chooseOutfit(_ sender: NSMenuItem) {
        persistor.wardrobe = DaxWardrobe(rawValue: sender.representedObject as? String)
        dressForToday()
        model?.character.hop()
    }

    /// Puts on what the wardrobe says for today, and again whenever the day changes.
    private func dressForToday() {
        model?.character.outfit = persistor.wardrobe.outfit(on: now())
        if dayChangeCancellable == nil {
            dayChangeCancellable = notificationCenter.publisher(for: .NSCalendarDayChanged)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.dressForToday() }
        }
    }

    @objc private func summarizePage() {
        Task { await model?.summarizePage() }
    }

    @objc private func continueLastChat() {
        Task { await model?.continueLastChat() }
    }

    @objc private func openDuckAI() {
        model?.openDuckAI()
    }

    @objc private func hide() {
        model?.hide()
    }

    // MARK: - Duck.ai answers

    private func observeAnswers() {
        responseStateCancellable = notificationCenter.publisher(for: .aiChatResponseStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let status = notification.userInfo?[AIChatNotificationUserInfoKey.responseStatus] as? AIChatStatusValue else { return }
                self?.responseStateChanged(to: status, on: notification.object as AnyObject?)
            }
        browserToolActivityCancellable = browserToolActivity?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity in self?.model?.browserToolActivity(activity) }
    }

    private func responseStateChanged(to status: AIChatStatusValue, on page: AnyObject?) {
        switch answers.update(status, on: page) {
        case .started:
            model?.answerStarted()
        case .finished(let succeeded):
            model?.answerFinished(succeeded: succeeded, isBrowserActive: isBrowserActive())
        case nil:
            break
        }
    }

    /// The window is mostly empty space: it only takes clicks over Dax, his controls and his speech bubble.
    private func startTrackingPointer() {
        let timer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeMainThread { self?.updatePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        updatePointer()
    }

    private func updatePointer() {
        guard let window, let model else { return }
        let mouse = NSEvent.mouseLocation
        let point = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)

        let characterFrame = DaxPetView.Metrics.characterFrame().offsetBy(dx: model.character.strollOffset, dy: 0)
        let isOverCharacter = characterFrame.contains(point)
        var interactiveFrames = [characterFrame, DaxPetView.Metrics.controlsFrame(isComposing: model.isComposing)]
        if model.speech != nil || !model.suggestions.isEmpty || model.glance != nil || model.findings != nil {
            interactiveFrames.append(DaxPetView.Metrics.bubbleFrame())
        }
        // A press in progress (e.g. dragging Dax) keeps its window.
        let isInteractive = NSEvent.pressedMouseButtons != 0 && !window.ignoresMouseEvents
            || interactiveFrames.contains { $0.contains(point) }
        if window.ignoresMouseEvents == isInteractive {
            window.ignoresMouseEvents = !isInteractive
        }

        if isOverCharacter, !isPointerOverCharacter {
            model.characterHovered()
        }
        isPointerOverCharacter = isOverCharacter
        updatePointerRest(isOverCharacter: isOverCharacter, model: model)
    }

    /// A pointer resting on Dax, not petting or pressing, asks him for a glance at the page.
    private func updatePointerRest(isOverCharacter: Bool, model: DaxPetViewModel) {
        guard isOverCharacter, NSEvent.pressedMouseButtons == 0, !model.character.isBeingPetted else {
            pointerRestStartTime = nil
            hasGlancedThisRest = false
            return
        }
        let restStart = pointerRestStartTime ?? now()
        pointerRestStartTime = restStart
        guard !hasGlancedThisRest, now().timeIntervalSince(restStart) >= Self.glanceRestDuration else { return }
        hasGlancedThisRest = true
        Task { [weak model] in await model?.glanceAtPage() }
    }

    /// Dropped hanging off a screen, he slides back onto it.
    private func keepOnScreen() {
        guard let window else { return }
        let origin = Self.origin(keepingCharacterOnScreenFor: window.frame.origin,
                                 visibleFrames: NSScreen.screens.map(\.visibleFrame))
        guard origin != window.frame.origin else { return }
        window.setFrame(NSRect(origin: origin, size: window.frame.size), display: true, animate: true)
    }

    /// Where the window must stand for Dax to be wholly on the screen he's mostly on.
    static func origin(keepingCharacterOnScreenFor origin: NSPoint, visibleFrames: [NSRect]) -> NSPoint {
        let character = DaxPetView.Metrics.characterFrame().offsetBy(dx: origin.x, dy: origin.y)
        func overlap(_ screen: NSRect) -> CGFloat {
            let intersection = screen.intersection(character)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let screen = visibleFrames.max { overlap($0) < overlap($1) }
        guard let screen, !screen.contains(character) else { return origin }
        let dx = character.minX < screen.minX ? screen.minX - character.minX
            : character.maxX > screen.maxX ? screen.maxX - character.maxX : 0
        let dy = character.minY < screen.minY ? screen.minY - character.minY
            : character.maxY > screen.maxY ? screen.maxY - character.maxY : 0
        return NSPoint(x: origin.x + dx, y: origin.y + dy)
    }

    private func savePosition() {
        guard let frame = window?.frame else { return }
        persistor.position = CGPoint(x: frame.midX, y: frame.minY)
    }

    /// Where he was left, as long as that's still on a screen; otherwise the bottom-right corner.
    private func initialPosition() -> CGPoint {
        if let saved = persistor.position,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(saved) }) {
            return saved
        }
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visibleFrame.maxX - 120, y: visibleFrame.minY + 24)
    }
}

extension DaxPetCoordinator: NSWindowDelegate {

    func windowDidResignKey(_ notification: Notification) {
        model?.keyboardFocusLost()
    }
}

/// Turns Duck.ai pages' response states into one answer at a time: started when the first page starts
/// answering, finished when the last one is done. A page reporting it's ready without having answered
/// (e.g. on load) is ignored.
struct DaxAnswerTracker {

    enum Event: Equatable {
        case started
        case finished(succeeded: Bool)
    }

    private var answeringPages = Set<ObjectIdentifier>()

    mutating func update(_ status: AIChatStatusValue, on page: AnyObject?) -> Event? {
        let id = page.map(ObjectIdentifier.init) ?? ObjectIdentifier(NSNull.self)
        switch status {
        case .startStreamNewPrompt, .startStreamRestartStream, .loading, .streaming:
            let wasIdle = answeringPages.isEmpty
            answeringPages.insert(id)
            return wasIdle ? .started : nil
        case .ready, .error, .blocked:
            guard answeringPages.remove(id) != nil, answeringPages.isEmpty else { return nil }
            return .finished(succeeded: status == .ready)
        case .unknown:
            return nil
        }
    }
}

/// Floats above everything, on every Space, without ever activating the browser by itself.
final class DaxPetWindow: NSPanel {

    var onCancel: (() -> Void)?
    /// Offered every mouse-down first; returns `true` when it took it. Without this, the first click on an
    /// inactive panel only selects it, so Dax couldn't be dragged in one go.
    var onMouseDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown, onMouseDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class DaxPetPromptSubmitter: DaxPetPromptSubmitting {

    private let aiChatTabOpener: AIChatTabOpening
    private let windowControllersManager: WindowControllersManagerProtocol
    private let makeSuggestionsReader: () -> AIChatSuggestionsReading
    private let capabilitiesProvider: DaxPetAttachmentCapabilitiesProviding
    private let featureFlagger: FeatureFlagger
    private let promptHandler: AIChatPromptHandler

    init(aiChatTabOpener: AIChatTabOpening,
         windowControllersManager: WindowControllersManagerProtocol,
         makeSuggestionsReader: @escaping () -> AIChatSuggestionsReading,
         capabilitiesProvider: DaxPetAttachmentCapabilitiesProviding,
         featureFlagger: FeatureFlagger,
         promptHandler: AIChatPromptHandler = .shared) {
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
        self.makeSuggestionsReader = makeSuggestionsReader
        self.capabilitiesProvider = capabilitiesProvider
        self.featureFlagger = featureFlagger
        self.promptHandler = promptHandler
    }

    func submit(prompt: String, payload: AIChatNativePrompt?) {
        aiChatTabOpener.openAIChatTab(with: .query(prompt, shouldAutoSubmit: true), behavior: .newTab(selected: true))
        // The opener seeds a plain query, so the attachments have to land after it.
        if let payload {
            promptHandler.setData(payload)
        }
        // Dax never activates the app, so handing off is what brings the browser forward.
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDuckAI() {
        aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
        NSApp.activate(ignoringOtherApps: true)
    }

    func showBrowser() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func attachmentCapabilities() async -> DaxPetAttachmentCapabilities {
        await capabilitiesProvider.capabilities()
    }

    func currentPageContent() async -> DaxPetPageContent? {
        guard let (_, tab) = currentPage, let context = await AIChatUserScriptHandler.extractPageContext(from: tab),
              context.attachable != false else { return nil }
        return DaxPetPageContent(url: context.url, title: context.title, text: context.content)
    }

    /// The window the user was last in, and the page it shows when that's a web page.
    private var currentPage: (windowController: MainWindowController, tab: Tab)? {
        guard let windowController = windowControllersManager.lastKeyMainWindowController,
              let tab = windowController.mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab,
              tab.content.urlForWebView?.isHttpOrHttps == true else { return nil }
        return (windowController, tab)
    }

    var canSummarizeCurrentPage: Bool { currentPage != nil }

    var canCompareTabs: Bool {
        featureFlagger.isFeatureOn(.aiChatPageContext) && featureFlagger.isFeatureOn(.aiChatMultiplePageContexts)
    }

    func compare(_ prompt: String, tabs: [DaxPetTab]) async -> Bool {
        guard let origin = windowControllersManager.allTabCollectionViewModels.first(where: { !$0.isBurner }) else { return false }
        var contexts: [AIChatPageContextData] = []
        for tab in tabs {
            if let context = await AIChatUserScriptHandler.extractPageContext(forTabId: tab.id, origin: origin, in: windowControllersManager),
               context.attachable != false {
                contexts.append(context)
            }
        }
        guard !contexts.isEmpty else { return false }
        submit(prompt: prompt, payload: .queryPrompt(prompt, autoSubmit: true, pageContext: .multiple(contexts)))
        return true
    }

    func askAboutCurrentPage(_ request: String) async -> Bool {
        guard let (windowController, tab) = currentPage else { return false }
        let pageContext = await AIChatUserScriptHandler.extractPageContext(from: tab)
        let prompt = AIChatNativePrompt.queryPrompt(request,
                                                    autoSubmit: true,
                                                    pageContext: pageContext.map { .single($0) })
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController.mainViewController.aiChatCoordinator.revealChat(for: prompt)
        return true
    }

    func continueLastChat() async -> Bool {
        let reader = makeSuggestionsReader()
        defer { reader.tearDown() }
        let (pinned, recent) = await reader.fetchSuggestions(query: nil, maxChats: 10)
        guard let chat = Self.mostRecent(pinned + recent) else { return false }
        aiChatTabOpener.openAIChatTab(with: .existingChat(chatId: chat.chatId), behavior: .newTab(selected: true))
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// The chat touched last, pinned or not; chats without a date count as oldest.
    static func mostRecent(_ chats: [AIChatSuggestion]) -> AIChatSuggestion? {
        chats.max { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }
}
