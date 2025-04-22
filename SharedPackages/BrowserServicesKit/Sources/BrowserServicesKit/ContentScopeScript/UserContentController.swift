//
//  UserContentController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import os.log
import QuartzCore
import UserScript
@preconcurrency import WebKit

public protocol UserContentControllerDelegate: AnyObject {
    @MainActor
    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent)
}

public protocol UserContentControllerNewContent {
    associatedtype SourceProvider
    associatedtype UserScripts: UserScriptsProvider

    var rulesUpdate: ContentBlockerRulesManager.UpdateEvent { get }
    var sourceProvider: SourceProvider { get }
    var makeUserScripts: @MainActor (SourceProvider) -> UserScripts { get }
}

@objc(UserContentController)
final public class UserContentController: WKUserContentController {

    public let privacyConfigurationManager: PrivacyConfigurationManaging
    @MainActor
    public weak var delegate: UserContentControllerDelegate?

    public struct ContentBlockingAssets: CustomDebugStringConvertible {
        public let globalRuleLists: [String: WKContentRuleList]
        public let userScripts: UserScriptsProvider
        public let wkUserScripts: [WKUserScript]
        public let updateEvent: ContentBlockerRulesManager.UpdateEvent

        public init<Content: UserContentControllerNewContent>(content: Content) async {
            self.globalRuleLists = content.rulesUpdate.rules.reduce(into: [:]) { result, rules in
                result[rules.name] = rules.rulesList
            }
            let userScripts = await content.makeUserScripts(content.sourceProvider)
            self.userScripts = userScripts
            self.updateEvent = content.rulesUpdate

            self.wkUserScripts = await userScripts.loadWKUserScripts()
        }

        public var debugDescription: String {
            """
            <ContentBlockingAssets
            globalRuleLists: \(globalRuleLists)
            wkUserScripts: \(wkUserScripts)
            updateEvent: (
            \(updateEvent.debugDescription)
            )>
            """
        }
    }

    @Published @MainActor public private(set) var contentBlockingAssets: ContentBlockingAssets? {
        willSet {
            self.removeAllContentRuleLists()
            self.removeInstalledUserScripts()

            if let contentBlockingAssets = newValue {
                Logger.contentBlocking.debug("📚 installing \(contentBlockingAssets.debugDescription)")
                self.installGlobalContentRuleLists(contentBlockingAssets.globalRuleLists)
                Logger.contentBlocking.debug("📜 installing user scripts")
                self.installUserScripts(contentBlockingAssets.wkUserScripts, handlers: contentBlockingAssets.userScripts.userScripts)
                Logger.contentBlocking.debug("✅ installing content blocking assets done")
            }
        }
    }

    @MainActor
    private func installContentBlockingAssets(_ contentBlockingAssets: ContentBlockingAssets) {
        // don‘t install ContentBlockingAssets (especially Message Handlers retaining `self`) after cleanUpBeforeClosing was called
        guard assetsPublisherCancellables != nil else { return }
        // installation should happen in `contentBlockingAssets.willSet`
        // so the $contentBlockingAssets subscribers receive an update only after everything is set
        self.contentBlockingAssets = contentBlockingAssets

        delegate?.userContentController(self,
                                        didInstallContentRuleLists: contentBlockingAssets.globalRuleLists,
                                        userScripts: contentBlockingAssets.userScripts,
                                        updateEvent: contentBlockingAssets.updateEvent)
    }

    enum ContentRuleListIdentifier: Hashable {
        case global(String), local(String)
    }
    @MainActor
    private var contentRuleLists = [ContentRuleListIdentifier: WKContentRuleList]()
    @MainActor
    private var assetsPublisherCancellables: Set<AnyCancellable>?
    @MainActor
    private let scriptMessageHandler = PermanentScriptMessageHandler()

    /// if earlyAccessHandlers (WKScriptMessageHandlers) are provided they are installed without waiting for contentBlockingAssets to be loaded if.
    @MainActor
    public init<Pub, Content>(assetsPublisher: Pub, privacyConfigurationManager: PrivacyConfigurationManaging, earlyAccessHandlers: [UserScript] = [])
    where Pub: Publisher, Content: UserContentControllerNewContent, Pub.Output == Content, Pub.Failure == Never {

        self.privacyConfigurationManager = privacyConfigurationManager
        super.init()

        // Install initial WKScriptMessageHandlers if any. Currently, no WKUserScript are provided at initialization.
        installUserScripts([], handlers: earlyAccessHandlers)
        // 1. receive UserContentControllerNewContent from assetsPublisher
        // 2. prepare ContentBlockingAssets(content: userContentControllerNewContent) asynchronously
        // 3. receive the ContentBlockingAssets from contentBlockingAssetsPublisher and install
        let contentBlockingAssetsPublisher = PassthroughSubject<ContentBlockingAssets, Never>()
        assetsPublisherCancellables = [
            contentBlockingAssetsPublisher.receive(on: DispatchQueue.main).sink { [weak self] contentBlockingAssets in
                self?.installContentBlockingAssets(contentBlockingAssets)
            },
            assetsPublisher.sink { [selfDescr=self.debugDescription] content in
                Logger.contentBlocking.debug("\(selfDescr): 📚 received content blocking assets")
                Task.detached {
                    let contentBlockingAssets = await ContentBlockingAssets(content: content)
                    contentBlockingAssetsPublisher.send(contentBlockingAssets)
                }
            }
        ]
#if DEBUG
        // make sure delegate for UserScripts is set shortly after init
        DispatchQueue.main.async { [weak self] in
            assert(self == nil || self?.delegate != nil, "UserContentController delegate not set")
        }
#endif
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    private func installGlobalContentRuleLists(_ globalContentRuleLists: [String: WKContentRuleList]) {
        assert(contentRuleLists.isEmpty, "installGlobalContentRuleLists should be called after removing all Content Rule Lists")
        guard self.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking) else {
            Logger.contentBlocking.debug("\(self): ❗️ content blocking disabled, removing all content rule lists")
            removeAllContentRuleLists()
            return
        }

        Logger.contentBlocking.debug("\(self): ❇️ installing global rule lists: \(globalContentRuleLists))")
        contentRuleLists = globalContentRuleLists.reduce(into: [:]) {
            $0[.global($1.key)] = $1.value
        }
        globalContentRuleLists.values.forEach(self.add)
    }

    public struct ContentRulesNotFoundError: Error {}
    @MainActor
    public func enableGlobalContentRuleList(withIdentifier identifier: String) throws {
        guard let ruleList = contentBlockingAssets?.globalRuleLists[identifier]
                // when enabling from a $contentBlockingAssets subscription, the ruleList gets
                // to contentRuleLists before contentBlockingAssets value is set
                ?? contentRuleLists[.global(identifier)] else {
            Logger.contentBlocking.debug("\(self): ❗️ can‘t enable rule list `\(identifier)` as it‘s not available")
            throw ContentRulesNotFoundError()
        }
        guard contentRuleLists[.global(identifier)] == nil else { return /* already enabled */ }

        Logger.contentBlocking.debug("\(self): 🟩 enabling rule list `\(identifier)`")
        contentRuleLists[.global(identifier)] = ruleList
        add(ruleList)
    }

    public struct ContentRulesNotEnabledError: Error {}
    @MainActor
    public func disableGlobalContentRuleList(withIdentifier identifier: String) throws {
        guard let ruleList = contentRuleLists[.global(identifier)] else {
            Logger.contentBlocking.debug("\(self): ❗️ can‘t disable rule list `\(identifier)` as it‘s not enabled")
            throw ContentRulesNotEnabledError()
        }

        Logger.contentBlocking.debug("\(self): 🔻 disabling rule list `\(identifier)`")
        contentRuleLists[.global(identifier)] = nil
        remove(ruleList)
    }

    @MainActor
    public func installLocalContentRuleList(_ ruleList: WKContentRuleList, identifier: String) {
        // replace if already installed
        removeLocalContentRuleList(withIdentifier: identifier)

        Logger.contentBlocking.debug("\(self): 🔸 installing local rule list `\(identifier)`")
        contentRuleLists[.local(identifier)] = ruleList
        add(ruleList)
    }

    @MainActor
    public func removeLocalContentRuleList(withIdentifier identifier: String) {
        guard let ruleList = contentRuleLists.removeValue(forKey: .local(identifier)) else { return }

        Logger.contentBlocking.debug("\(self): 🔻 removing local rule list `\(identifier)`")
        remove(ruleList)
    }

    @MainActor
    public override func removeAllContentRuleLists() {
        Logger.contentBlocking.debug("\(self): 🧹 removing all content rule lists")
        contentRuleLists.removeAll(keepingCapacity: true)
        super.removeAllContentRuleLists()
    }

#if os(macOS)
    static let removeUserScriptSelector = "removeUserScript:"
    private var removeUserScriptSupported: Bool {
        responds(to: NSSelectorFromString("_" + Self.removeUserScriptSelector))
    }
    private var installedUserScripts = [WKUserScript]()
#endif

    @MainActor
    private func installUserScripts(_ wkUserScripts: [WKUserScript], handlers: [UserScript]) {
        handlers.forEach { self.addHandler($0) }
        wkUserScripts.forEach(self.addUserScript)

#if os(macOS)
        installedUserScripts.append(contentsOf: wkUserScripts)
#endif
    }

    private func removeInstalledUserScripts() {
#if os(macOS)
        // Avoid removal of web extension scripts
        if removeUserScriptSupported {
            for installedUserScript in installedUserScripts {
                self.perform(NSSelectorFromString("_" + Self.removeUserScriptSelector), with: installedUserScript)
            }
            installedUserScripts.removeAll()
        } else {
            self.removeAllUserScripts()
        }
#else
        self.removeAllUserScripts()
#endif

    }

    @MainActor
    public func cleanUpBeforeClosing() {
        Logger.contentBlocking.debug("\(self): 💀 cleanUpBeforeClosing")

        self.removeAllUserScripts()

        if #available(macOS 11.0, *) {
            self.removeAllScriptMessageHandlers()
        } else {
            self.scriptMessageHandler.registeredMessageNames.forEach(self.removeScriptMessageHandler)
        }

        self.scriptMessageHandler.clear()
        self.assetsPublisherCancellables = nil

        self.removeAllContentRuleLists()
    }

    @MainActor
    func addHandler(_ userScript: UserScript) {
        for messageName in userScript.messageNames {
            assert(scriptMessageHandler.messageHandler(for: messageName) == nil || type(of: scriptMessageHandler.messageHandler(for: messageName)!) == type(of: userScript),
                   "\(scriptMessageHandler.messageHandler(for: messageName)!) already registered for message \(messageName)")

            defer {
                scriptMessageHandler.register(userScript, for: messageName)
            }
            guard !scriptMessageHandler.isMessageHandlerRegistered(for: messageName) else { continue }

            if #available(macOS 11.0, iOS 14.0, *) {
                let contentWorld: WKContentWorld = userScript.getContentWorld()
                if userScript is WKScriptMessageHandlerWithReply {
                    addScriptMessageHandler(scriptMessageHandler, contentWorld: contentWorld, name: messageName)
                } else {
                    add(scriptMessageHandler, contentWorld: contentWorld, name: messageName)
                }
            } else {
                add(scriptMessageHandler, name: messageName)
            }
        }
    }

}

public extension UserContentController {

    @MainActor
    var contentBlockingAssetsInstalled: Bool {
        contentBlockingAssets != nil
    }

    // func awaitContentBlockingAssetsInstalled() async non-retaining `self`
    @MainActor
    var awaitContentBlockingAssetsInstalled: () async -> Void {
        guard !contentBlockingAssetsInstalled else { return {} }
        Logger.contentBlocking.debug("\(self): 🛑 will wait for content blocking assets installed")
        let startTime = CACurrentMediaTime()
        return { [weak self, selfDescr=self.description] in
            // merge $contentBlockingAssets with Task cancellation completion event publisher
            let taskCancellationSubject = PassthroughSubject<ContentBlockingAssets?, Error>()
            guard let assetsPublisher = self?.$contentBlockingAssets else { return }

            // throw an error when current Task is cancelled
            let throwingPublisher = assetsPublisher
                .mapError({ _ -> Error in })
                .merge(with: taskCancellationSubject)
                .receive(on: DispatchQueue.main)

            // send completion to the throwingPublisher if current Task is cancelled
            try? await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { c in
                    var cancellable: AnyCancellable!
                    var elapsedTime: String {
                        String(format: "%.2fs.", CACurrentMediaTime() - startTime)
                    }
                    cancellable = throwingPublisher.sink /* completion: */ { _ in
                        withExtendedLifetime(cancellable) {
                            Logger.contentBlocking.debug("\(selfDescr): ❌ wait cancelled after \(elapsedTime)")

                            c.resume(with: .failure(CancellationError()))
                            cancellable.cancel()
                        }
                    } receiveValue: { assets in
                        guard assets != nil else { return }
                        withExtendedLifetime(cancellable) {
                            Logger.contentBlocking.debug("\(selfDescr): 🏁 content blocking assets installed (\(elapsedTime))")

                            c.resume(with: .success( () ))
                            cancellable.cancel()
                        }
                    }
                } as Void

            } onCancel: {
                taskCancellationSubject.send(completion: .failure(CancellationError()))
            }
        }
    }

}

/// Script Message Handler only added once per UserScriptController for all the Message Names (to avoid race conditions for re-added User Scripts)
private class PermanentScriptMessageHandler: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {

    private struct WeakScriptMessageHandlerBox {
        weak var handler: WKScriptMessageHandler?
    }
    private var registeredMessageHandlers = [String: WeakScriptMessageHandlerBox]()

    var registeredMessageNames: [String] {
        Array(registeredMessageHandlers.keys)
    }

    func clear() {
        self.registeredMessageHandlers.removeAll()
    }

    func isMessageHandlerRegistered(for messageName: String) -> Bool {
        return self.registeredMessageHandlers[messageName] != nil
    }

    func messageHandler(for messageName: String) -> WKScriptMessageHandler? {
        return self.registeredMessageHandlers[messageName]?.handler
    }

    func register(_ handler: WKScriptMessageHandler, for messageName: String) {
        self.registeredMessageHandlers[messageName] = .init(handler: handler)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let box = self.registeredMessageHandlers[message.messageName] else {
            assertionFailure("no registered message handler for \(message.messageName)")
            return
        }
        guard let handler = box.handler else {
            assertionFailure("handler for \(message.messageName) has been unregistered")
            return
        }
        handler.userContentController(userContentController, didReceive: message)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let box = self.registeredMessageHandlers[message.messageName] else {
            assertionFailure("no registered message handler for \(message.messageName)")
            return
        }
        guard let handler = box.handler else {
            assertionFailure("handler for \(message.messageName) has been unregistered")
            return
        }
        assert(handler is WKScriptMessageHandlerWithReply)
        (handler as? WKScriptMessageHandlerWithReply)?.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }

}
