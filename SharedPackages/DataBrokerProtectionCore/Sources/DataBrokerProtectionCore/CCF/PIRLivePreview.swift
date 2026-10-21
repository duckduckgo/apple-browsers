//
//  PIRLivePreview.swift
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

#if os(macOS) && DEBUG
import AppKit
import WebKit

public struct PIRLivePreviewFrame: Sendable {
    public let imageData: Data
    public let operationID: UUID
    public let brokerName: String
    public let activity: String
    public let faviconURL: URL?
    public let pageURL: URL?
    public let canTakeControl: Bool
    public let isManualControl: Bool
    public let needsAssistance: Bool
    public let target: PIRLivePreviewTarget?
    public let checklist: PIRLivePreviewChecklist?

    public init(imageData: Data, operationID: UUID, brokerName: String, activity: String, faviconURL: URL? = nil,
                pageURL: URL? = nil, canTakeControl: Bool = false, isManualControl: Bool = false, needsAssistance: Bool = false,
                target: PIRLivePreviewTarget? = nil, checklist: PIRLivePreviewChecklist? = nil) {
        self.imageData = imageData
        self.operationID = operationID
        self.brokerName = brokerName
        self.activity = activity
        self.faviconURL = faviconURL
        self.pageURL = pageURL
        self.canTakeControl = canTakeControl
        self.isManualControl = isManualControl
        self.needsAssistance = needsAssistance
        self.target = target
        self.checklist = checklist
    }
}

/// The current step's user-facing actions, with the one in progress.
public struct PIRLivePreviewChecklist: Sendable, Equatable {
    public let isOptOut: Bool
    /// The second half of an opt-out, after the broker's confirmation email arrived.
    public let isConfirmation: Bool
    public let items: [String]
    public let currentIndex: Int

    public init(isOptOut: Bool, isConfirmation: Bool = false, items: [String], currentIndex: Int) {
        self.isOptOut = isOptOut
        self.isConfirmation = isConfirmation
        self.items = items
        self.currentIndex = currentIndex
    }

    init(stepType: StepType, actions: [Action], currentIndex: Int?, brokerName: String, profileQuery: ProfileQuery,
         isConfirmation: Bool = false) {
        let isOptOut = stepType == .optOut
        let lastClickIndex = actions.lastIndex { $0.actionType == .click }
        let firstNavigationIndex = actions.firstIndex { $0.actionType == .navigate }
        let context = LabelContext(isOptOut: isOptOut, isConfirmation: isConfirmation, brokerName: brokerName,
                                   person: "\(profileQuery.firstName) \(profileQuery.lastName)",
                                   place: "\(profileQuery.city), \(profileQuery.state)")
        // The first half already happened in an earlier run; show it as done so this reads as the same request.
        var items: [String] = isConfirmation ? ["Submit your removal request", "Get \(brokerName)\u{2019}s confirmation email"] : []
        var itemIndexForAction: [Int] = []
        for (index, action) in actions.enumerated() {
            // Forms with an email field fetch one on the side, without a generateEmail action of their own.
            if (action as? FillFormAction)?.needsEmail == true, items.last != Self.createEmailLabel {
                items.append(Self.createEmailLabel)
            }
            if let label = Self.label(for: action, context: context, isFirstNavigation: index == firstNavigationIndex,
                                      isLastClick: index == lastClickIndex), label != items.last {
                items.append(label)
            }
            itemIndexForAction.append(max(items.count - 1, 0))
        }
        self.isOptOut = isOptOut
        self.isConfirmation = isConfirmation
        self.items = items
        self.currentIndex = currentIndex.flatMap { itemIndexForAction.indices.contains($0) ? itemIndexForAction[$0] : nil } ?? 0
    }

    private static let createEmailLabel = "Create a private email for the reply"

    private struct LabelContext {
        let isOptOut: Bool
        let isConfirmation: Bool
        let brokerName: String
        let person: String
        let place: String
    }

    private static func label(for action: Action, context: LabelContext, isFirstNavigation: Bool, isLastClick: Bool) -> String? {
        switch action.actionType {
        case .navigate:
            guard isFirstNavigation else { return "Go to the next page" }
            if context.isConfirmation { return "Open the confirmation link from your email" }
            // Scan URLs already carry the search terms, so the first page load is the search itself.
            return context.isOptOut ? "Open \(context.brokerName)\u{2019}s opt-out form" : "Search for \(context.person) in \(context.place)"
        case .fillForm:
            let fields = (action as? FillFormAction)?.elements.compactMap { fieldName(for: $0.type) } ?? []
            var unique: [String] = []
            for field in fields where !unique.contains(field) { unique.append(field) }
            guard let last = unique.last else { return "Fill in the form" }
            let list = unique.count == 1 ? last : unique.dropLast().joined(separator: ", ") + " and " + last
            return "Enter your " + list
        case .click:
            if context.isOptOut {
                guard isLastClick else { return "Continue to the next step" }
                return context.isConfirmation ? "Confirm your removal request" : "Submit your removal request"
            }
            return "Run the search"
        case .extract: return "Check the results against your profile"
        case .getCaptchaInfo, .solveCaptcha: return "Prove you\u{2019}re human"
        case .generateEmail: return createEmailLabel
        case .getEmailData: return "Wait for \(context.brokerName)\u{2019}s email"
        case .emailConfirmation: return "Confirm the request from your email"
        case .expectation:
            // A wait for a Turnstile token is the moment a person may have to prove they are human.
            let waitsForTurnstile = action.json.flatMap { String(bytes: $0, encoding: .utf8) }?.contains("cf-turnstile-response") == true
            return waitsForTurnstile ? "Prove you\u{2019}re human" : nil
        case .condition, .executeScript: return nil
        }
    }

    private static func fieldName(for type: String) -> String? {
        switch type {
        case "firstName", "lastName", "middleName", "fullName": return "name"
        case "city", "state", "fullState", "$generated_zip_code$", "$generated_street_address$": return "location"
        case "age", "birthYear": return "age"
        case "email": return "email"
        case "$generated_phone_number$": return "phone"
        case "profileUrl", "url": return "profile link"
        case "verificationCode": return "verification code"
        default: return nil
        }
    }
}

/// The page elements the current action works on, in viewport fractions with a top-left origin.
public struct PIRLivePreviewTarget: Sendable, Equatable {
    public let actionID: String
    public let actionType: ActionType
    public let rects: [CGRect]
    /// What a form fill types into each rect, when the profile supplies it.
    public let texts: [String?]

    public init(actionID: String, actionType: ActionType, rects: [CGRect], texts: [String?] = []) {
        self.actionID = actionID
        self.actionType = actionType
        self.rects = rects
        self.texts = texts
    }
}

struct PIRLivePreviewTargetQuery: Sendable, Equatable {
    let actionID: String
    let actionType: ActionType
    let rootSelector: String?
    let selectors: [String]
    let texts: [String?]
    let limit: Int

    init?(action: Action, profileQuery: ProfileQuery?, email: String? = nil) {
        guard let json = action.json,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let selector = object["selector"] as? String
        let elements = (object["elements"] as? [[String: Any]])?.filter { $0["selector"] is String } ?? []
        let elementSelectors = elements.compactMap { $0["selector"] as? String }
        texts = action.actionType == .fillForm
            ? elements.map { element in
                (element["type"] as? String) == "email" ? email
                    : profileQuery.flatMap { Self.typedValue(for: element["type"] as? String, from: $0) }
            }
            : []
        switch action.actionType {
        case .click:
            rootSelector = nil
            selectors = elementSelectors
            limit = 1
        case .fillForm:
            rootSelector = selector
            selectors = elementSelectors
            limit = 1
        case .extract, .getCaptchaInfo, .solveCaptcha:
            rootSelector = nil
            selectors = selector.map { [$0] } ?? []
            limit = action.actionType == .extract ? 6 : 1
        default:
            return nil
        }
        guard !selectors.isEmpty else { return nil }
        actionID = action.id
        actionType = action.actionType
    }

    private static func typedValue(for type: String?, from profile: ProfileQuery) -> String? {
        switch type {
        case "firstName": return profile.firstName
        case "lastName": return profile.lastName
        case "middleName": return profile.middleName
        case "fullName": return profile.fullName
        case "city": return profile.city
        case "state", "fullState": return profile.state
        case "age": return String(profile.age)
        case "birthYear": return String(profile.birthYear)
        default: return nil
        }
    }

    private init(actionID: String, actionType: ActionType, selectors: [String]) {
        self.actionID = actionID
        self.actionType = actionType
        self.rootSelector = nil
        self.selectors = selectors
        self.texts = []
        self.limit = 1
    }

    /// The Turnstile widget inside a broker's form, so the preview can scroll to it and point at it.
    static let turnstileWidget = PIRLivePreviewTargetQuery(
        actionID: "turnstile-widget", actionType: .expectation,
        selectors: ["//input[@name='cf-turnstile-response']/..", ".cf-turnstile", "iframe[src*='challenges.cloudflare.com']"])

    /// Gives the cursor time to reach its targets before the broker page changes.
    static func presentationDelay(for action: Action, alreadyWaited: TimeInterval) -> TimeInterval {
        switch action {
        case let fillForm as FillFormAction:
            return min(0.6 + 0.9 * Double(fillForm.elements.count), 4.5)
        case is ClickAction:
            return max(0, 1.4 - alreadyWaited)
        case is ExtractAction:
            return 1
        default:
            return 0
        }
    }
}

/// Observes agent-owned pages without retaining them or changing their viewport.
@MainActor
public final class PIRLivePreview {
    public static let shared = PIRLivePreview()

    public func captureFrame() async throws -> PIRLivePreviewFrame? {
        sources.removeAll { $0.webView == nil }
        guard let source = sources.first, let webView = source.webView else { return nil }
        guard !isCapturing else { throw PreviewError.captureInProgress }

        isCapturing = true
        defer { isCapturing = false }
        let pageURL = webView.url
        // The placeholder page the agent loads before the broker site is not worth showing. During the next
        // navigation `url` already names the broker while the placeholder is still on screen, so ask the page.
        let shownProtocol = try? await webView.callAsyncJavaScript("return location.protocol", contentWorld: .defaultClient) as? String
        let placeholderProtocol = WebViewSchemeHandler.dataBrokerProtectionScheme + ":"
        let isPlaceholder = pageURL?.scheme == WebViewSchemeHandler.dataBrokerProtectionScheme || shownProtocol == placeholderProtocol
        let query = source.targetQuery
        var rects: [(CGRect, Int)] = []
        // Measure first: it may scroll an off-screen target into view, and the snapshot should show that.
        if let query { rects = await targetRects(webView, query) }
        let imageData = isPlaceholder ? Data() : try await snapshot(webView)
        let faviconValue = try? await webView.evaluateJavaScript("document.querySelector('link[rel~=\"icon\"]')?.href || new URL('/favicon.ico', location.href).href")
        let faviconURL = (faviconValue as? String).flatMap { URL(string: $0) }

        // A page can finish while WebKit captures it. Never deliver its stale frame.
        guard sources.contains(where: { $0 === source }), webView.url == pageURL else { return nil }
        let target = query.flatMap { query in
            source.targetQuery == query && !rects.isEmpty
                ? PIRLivePreviewTarget(actionID: query.actionID, actionType: query.actionType, rects: rects.map(\.0),
                                       texts: rects.map { query.texts.indices.contains($0.1) ? query.texts[$0.1] : nil }) : nil
        }
        return PIRLivePreviewFrame(imageData: imageData, operationID: source.operationID,
                                   brokerName: source.brokerName, activity: source.activity, faviconURL: faviconURL,
                                   pageURL: isPlaceholder ? nil : pageURL,
                                   canTakeControl: source.handler?.manualControl.canTakeControl ?? false,
                                   isManualControl: source.handler?.manualControl.isUserControlling ?? false,
                                   needsAssistance: source.handler?.manualControl.needsAssistance ?? false,
                                   target: target, checklist: source.checklist)
    }

    func showTarget(_ query: PIRLivePreviewTargetQuery, operationID: UUID) {
        sources.first { $0.operationID == operationID }?.targetQuery = query
    }

    func updateChecklist(_ checklist: PIRLivePreviewChecklist, operationID: UUID) {
        sources.first { $0.operationID == operationID }?.checklist = checklist
    }

    func updateTarget(for action: Action?, profileQuery: ProfileQuery? = nil, email: String? = nil, operationID: UUID) {
        sources.first { $0.operationID == operationID }?.targetQuery = action.flatMap {
            PIRLivePreviewTargetQuery(action: $0, profileQuery: profileQuery, email: email)
        }
    }

    public func register(webView: WKWebView, operationID: UUID, brokerName: String, activity: String = "Opening the broker website") {
        sources.removeAll { $0.operationID == operationID }
        sources.append(Source(webView: webView, operationID: operationID, brokerName: brokerName, activity: activity))
        activityChanged?(true)
    }

    public func updateActivity(_ activity: String, operationID: UUID) {
        sources.first { $0.operationID == operationID }?.activity = activity
    }

    public func unregister(operationID: UUID) {
        sources.removeAll { $0.operationID == operationID }
        if sources.isEmpty { activityChanged?(false) }
    }

    /// Reports whether any broker page is open, so the agent can show the preview while it works.
    public var activityChanged: ((Bool) -> Void)?

    public var manualControlChanged: ((UUID, Bool) -> Void)?
    public var manualControlStarted: (() -> Void)?
    public var automationResumed: (() -> Void)?

    public var isManualControlActive: Bool {
        sources.contains { $0.handler?.manualControl.isUserControlling == true }
    }

    func attach(handler: DataBrokerProtectionWebViewHandler, operationID: UUID) {
        sources.first { $0.operationID == operationID }?.handler = handler
    }

    public func takeControl(operationID: UUID) async throws -> Bool {
        guard let handler = sources.first(where: { $0.operationID == operationID })?.handler else { return false }
        return try await handler.takeManualControl()
    }

    private var sources: [Source] = []
    private var isCapturing = false
    private let snapshot: (WKWebView) async throws -> Data
    private let targetRects: (WKWebView, PIRLivePreviewTargetQuery) async -> [(CGRect, Int)]

    init(snapshot: @escaping (WKWebView) async throws -> Data = PIRLivePreview.snapshot,
         targetRects: @escaping (WKWebView, PIRLivePreviewTargetQuery) async -> [(CGRect, Int)] = PIRLivePreview.targetRects) {
        self.snapshot = snapshot
        self.targetRects = targetRects
    }

    /// Resolves selectors the way the broker JSON writes them: XPath when it starts with `/`, `./` or `(`, CSS otherwise.
    private static let targetRectsScript = """
    const find = (selector, root, limit) => {
      try {
        if (/^(\\.?\\/|\\()/.test(selector)) {
          const result = document.evaluate(selector, root, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          return Array.from({ length: Math.min(result.snapshotLength, limit) }, (_, i) => result.snapshotItem(i));
        }
        return Array.from(root.querySelectorAll(selector)).slice(0, limit);
      } catch (e) { return []; }
    };
    const root = (rootSelector && find(rootSelector, document, 1)[0]) || document;
    const width = window.innerWidth || 1, height = window.innerHeight || 1;
    const matches = selectors.flatMap((selector, index) => find(selector, root, limit).map(node => [node, index]));
    const first = matches.map(([node]) => node).find(node => node.getBoundingClientRect().height > 0);
    if (first) {
      const rect = first.getBoundingClientRect();
      if (rect.top < 0 || rect.bottom > height) first.scrollIntoView({ block: 'center', behavior: 'instant' });
    }
    return matches
      .map(([node, index]) => [node.getBoundingClientRect(), index])
      .filter(([rect]) => rect.width > 0 && rect.height > 0)
      .map(([rect, index]) => [rect.left / width, rect.top / height, rect.width / width, rect.height / height, index]);
    """

    /// Each rect comes with the index of the selector that found it.
    private static func targetRects(_ webView: WKWebView, _ query: PIRLivePreviewTargetQuery) async -> [(CGRect, Int)] {
        let arguments: [String: Any] = ["rootSelector": query.rootSelector ?? "", "selectors": query.selectors, "limit": query.limit]
        guard let rows = try? await webView.callAsyncJavaScript(targetRectsScript, arguments: arguments, contentWorld: .defaultClient) as? [[Double]] else {
            return []
        }
        return rows.compactMap { row in
            row.count == 5 ? (CGRect(x: row[0], y: row[1], width: row[2], height: row[3]), Int(row[4])) : nil
        }
    }

    private static func snapshot(_ webView: WKWebView) async throws -> Data {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = 1024
        let image = try await webView.takeSnapshot(configuration: configuration)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            throw PreviewError.imageEncodingFailed
        }
        return data
    }

    private final class Source {
        weak var webView: WKWebView?
        weak var handler: DataBrokerProtectionWebViewHandler?
        let operationID: UUID
        let brokerName: String
        var activity: String
        var targetQuery: PIRLivePreviewTargetQuery?
        var checklist: PIRLivePreviewChecklist?

        init(webView: WKWebView, operationID: UUID, brokerName: String, activity: String) {
            self.webView = webView
            self.operationID = operationID
            self.brokerName = brokerName
            self.activity = activity
        }
    }

    private enum PreviewError: Error {
        case captureInProgress
        case imageEncodingFailed
    }
}
#endif
