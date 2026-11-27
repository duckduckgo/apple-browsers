//
//  NewChatHintsTests.swift
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
import Foundation
import Testing
@testable import DuckDuckGo

@Suite("New chat hints inputs")
struct NewChatHintsInputsTests {

    private static let allClear = NewChatHintsInputs(isEligibleUser: true,
                                                     isGuaranteedNewChat: true,
                                                     isPromoClear: true,
                                                     isTypeAtTipHidden: true,
                                                     isDraftEmpty: true,
                                                     availableHints: [.photo, .documents, .imageGeneration])

    @available(iOS 16, macOS 13, *)
    @Test("Every term true shows the available hints in their order", .timeLimit(.minutes(1)))
    func allTermsShowHints() {
        #expect(Self.allClear.visibleHints == [.photo, .documents, .imageGeneration])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any one term false hides every hint", .timeLimit(.minutes(1)),
          arguments: [\NewChatHintsInputs.isEligibleUser, \.isGuaranteedNewChat, \.isPromoClear, \.isTypeAtTipHidden, \.isDraftEmpty])
    func anyTermHidesHints(term: WritableKeyPath<NewChatHintsInputs, Bool>) {
        var inputs = Self.allClear
        inputs[keyPath: term] = false
        #expect(inputs.visibleHints.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing is shown before anything is known", .timeLimit(.minutes(1)))
    func defaultsShowNothing() {
        var inputs = NewChatHintsInputs()
        inputs.availableHints = NewChatHint.allCases
        #expect(inputs.visibleHints.isEmpty)
    }
}

@Suite("New chat state")
struct NewChatStateTests {

    private static let blankNewChat = NewChatState(isFullTabInput: true,
                                                   isTabSelected: true,
                                                   isInputReady: true)

    @available(iOS 16, macOS 13, *)
    @Test("A blank, settled, full-tab chat on the selected tab is a new chat", .timeLimit(.minutes(1)))
    func blankNewChat() {
        #expect(Self.blankNewChat.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each missing requirement rules it out", .timeLimit(.minutes(1)),
          arguments: [\NewChatState.isFullTabInput, \.isTabSelected, \.isInputReady])
    func missingRequirement(term: WritableKeyPath<NewChatState, Bool>) {
        var state = Self.blankNewChat
        state[keyPath: term] = false
        #expect(!state.isGuaranteedNewChat)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each exclusion rules it out", .timeLimit(.minutes(1)),
          arguments: [\NewChatState.hasChat, \.carriesPrompt, \.isVoiceHeld, \.isEditing])
    func exclusion(term: WritableKeyPath<NewChatState, Bool>) {
        var state = Self.blankNewChat
        state[keyPath: term] = true
        #expect(!state.isGuaranteedNewChat)
    }
}

@Suite("New chat hints eligibility")
struct NewChatHintsEligibilityTests {

    private let key = DuckAiNativeStorageReservedEntryKeys.originConversions.rawValue

    private func termsStore(accepted: Bool) -> DuckAiTermsOfServiceStore {
        let defaults = UserDefaults(suiteName: "NewChatHintsEligibilityTests-\(UUID().uuidString)")!
        let store = DuckAiTermsOfServiceStore(keyValueStore: defaults)
        if accepted { store.recordAcceptedOnWeb() }
        return store
    }

    private func storage(_ value: Any?) throws -> DuckAiNativeMemoryStorageHandler {
        let storage = DuckAiNativeMemoryStorageHandler()
        if let value { try storage.putEntry(key: key, value: value) }
        return storage
    }

    @available(iOS 16, macOS 13, *)
    @Test("The web app's entry counts in each shape it can take", .timeLimit(.minutes(1)))
    func entryShapes() throws {
        let cases: [(value: Any, isEligible: Bool)] = [
            (#"["duckai_prompt"]"#, true),
            (#"["serp_ai_chat","duckai_prompt"]"#, true),
            (["duckai_prompt"], true),
            (["other", "duckai_prompt"] as [Any], true),
            (#"["serp_ai_chat"]"#, false),
            ("[]", false),
            ("duckai_prompt", false),
            ("not json", false),
            ([1, 2], false),
            (true, false)
        ]
        for (value, isEligible) in cases {
            let eligibility = NewChatHintsEligibility(storage: try storage(value), fireModeStorage: nil,
                                                      termsOfServiceStore: termsStore(accepted: true))
            #expect(eligibility.isEligibleUser(isFireTab: false) == isEligible, "\(value)")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("No entry means a first-time user", .timeLimit(.minutes(1)))
    func noEntry() throws {
        let eligibility = NewChatHintsEligibility(storage: try storage(nil), fireModeStorage: nil,
                                                  termsOfServiceStore: termsStore(accepted: true))
        #expect(!eligibility.isEligibleUser(isFireTab: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without accepted terms nobody is eligible", .timeLimit(.minutes(1)))
    func termsNotAccepted() throws {
        let eligibility = NewChatHintsEligibility(storage: try storage(#"["duckai_prompt"]"#), fireModeStorage: nil,
                                                  termsOfServiceStore: termsStore(accepted: false))
        #expect(!eligibility.isEligibleUser(isFireTab: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A Fire tab reads the normal store too", .timeLimit(.minutes(1)))
    func fireTabReadsNormalStore() throws {
        let eligibility = NewChatHintsEligibility(storage: try storage(#"["duckai_prompt"]"#), fireModeStorage: try storage(nil),
                                                  termsOfServiceStore: termsStore(accepted: true))
        #expect(eligibility.isEligibleUser(isFireTab: true))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A prompt sent in a Fire tab counts there, and only there", .timeLimit(.minutes(1)))
    func promptInFireStore() throws {
        let eligibility = NewChatHintsEligibility(storage: try storage(nil), fireModeStorage: try storage(#"["duckai_prompt"]"#),
                                                  termsOfServiceStore: termsStore(accepted: true))
        #expect(eligibility.isEligibleUser(isFireTab: true))
        #expect(!eligibility.isEligibleUser(isFireTab: false))
    }
}
