//
//  SuggestionsVariant.swift
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

import Foundation

public struct SuggestionsVariant: Equatable, Sendable {
    public enum Input: String, CaseIterable, Sendable { case title, headings, body }
    public enum Trigger: String, CaseIterable, Sendable { case pageLoad, sheetOpen }
    public enum Method: String, CaseIterable, Sendable { case model, foundationModels, templates }

    public var input: Input
    public var trigger: Trigger
    public var method: Method
    public var count: Int
    public var modelID: String
    public var locale: String
    public var budgetSeconds: Double

    public init(input: Input = .headings, trigger: Trigger = .pageLoad, method: Method = .model,
                count: Int = 3, modelID: String, locale: String, budgetSeconds: Double = 1.5) {
        self.input = input
        self.trigger = trigger
        self.method = method
        self.count = count == 4 ? 4 : 3
        self.modelID = modelID
        self.locale = locale
        self.budgetSeconds = budgetSeconds
    }
}

public struct SuggestionsKey: Equatable, Sendable {
    public let document: UUID
    public let url: URL
    public let variant: SuggestionsVariant

    public init(document: UUID, url: URL, variant: SuggestionsVariant) {
        self.document = document
        self.url = url
        self.variant = variant
    }
}

@MainActor
public final class CurrentDocumentSuggestions {
    public private(set) var key: SuggestionsKey?
    public private(set) var prompts: [SuggestedPrompt] = []
    public private(set) var run: SuggestedPromptsRun?
    private var generation = UUID()
    private var task: Task<SuggestedPromptsRun?, Never>?
    private var subscribers: [UUID: ([SuggestedPrompt]) -> Void] = [:]

    public init() {}

    deinit { task?.cancel() }

    public func invalidate() {
        generation = UUID()
        task?.cancel()
        task = nil
        key = nil
        prompts = []
        run = nil
        subscribers = [:]
    }

    public func start(key: SuggestionsKey,
                      operation: @escaping @Sendable (@escaping @Sendable ([SuggestedPrompt]) async -> Void) async -> SuggestedPromptsRun) {
        if self.key == key {
            if run == nil, task != nil { return }
            if case .generated = run?.result { return }
        }
        invalidate()
        self.key = key
        let generation = generation
        task = Task { [weak self] in
            let result = await operation { _ in }
            guard !Task.isCancelled, let self, self.key == key, self.generation == generation else { return nil }
            self.run = result
            if case .generated(let prompts, _) = result.result { self.publish(prompts, for: key, generation: generation) }
            return result
        }
    }

    public func resolve(onUpdate: @escaping ([SuggestedPrompt]) -> Void) async -> SuggestedPromptsRun? {
        let id = UUID()
        subscribers[id] = onUpdate
        if !prompts.isEmpty { onUpdate(prompts) }
        defer { subscribers[id] = nil }
        return await withTaskCancellationHandler {
            await task?.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.subscribers[id] = nil }
        }
    }

    private func publish(_ prompts: [SuggestedPrompt], for key: SuggestionsKey, generation: UUID) {
        guard self.key == key, self.generation == generation, !prompts.isEmpty else { return }
        self.prompts = prompts
        for subscriber in subscribers.values { subscriber(prompts) }
    }
}
