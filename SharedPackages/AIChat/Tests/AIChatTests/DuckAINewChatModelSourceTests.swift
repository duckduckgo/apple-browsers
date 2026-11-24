//
//  DuckAINewChatModelSourceTests.swift
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
import Testing

@Suite("New chat model source for the prompt pixel")
struct DuckAINewChatModelSourceTests {

    private let serverDefault = AIChatNewChatSelection(modelId: "terra", reasoningEffort: nil, origin: .server)
    private let fallbackDefault = AIChatNewChatSelection(modelId: "luna", reasoningEffort: nil, origin: .fallback)

    private func resolve(_ sentModelId: String,
                         sendsDefaultEffort: Bool = true,
                         isPicked: Bool = false,
                         onboardingModelId: String? = nil,
                         newChatDefault: AIChatNewChatSelection?) -> DuckAINewChatModelSource? {
        DuckAINewChatModelSource.resolve(sentModelId: sentModelId,
                                         sendsDefaultEffort: sendsDefaultEffort,
                                         isPicked: isPicked,
                                         onboardingModelId: onboardingModelId,
                                         newChatDefault: newChatDefault)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sending the server default reports default", .timeLimit(.minutes(1)))
    func serverDefaultIsDefault() {
        #expect(resolve("terra", newChatDefault: serverDefault) == .default)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sending the fallback default reports fallback", .timeLimit(.minutes(1)))
    func fallbackDefaultIsFallback() {
        #expect(resolve("luna", newChatDefault: fallbackDefault) == .fallback)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sending another picked model reports picked", .timeLimit(.minutes(1)))
    func otherModelIsPicked() {
        #expect(resolve("claude", isPicked: true, newChatDefault: serverDefault) == .picked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Changing only the effort reports picked", .timeLimit(.minutes(1)))
    func effortOnlyChangeIsPicked() {
        #expect(resolve("terra", sendsDefaultEffort: false, isPicked: true, newChatDefault: serverDefault) == .picked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Picking back the default model reports default", .timeLimit(.minutes(1)))
    func pickingTheDefaultIsDefault() {
        #expect(resolve("terra", isPicked: true, newChatDefault: serverDefault) == .default)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sending the model onboarding opened the chat with reports onboarding", .timeLimit(.minutes(1)))
    func onboardingModelIsOnboarding() {
        #expect(resolve("terra", onboardingModelId: "terra", newChatDefault: serverDefault) == .onboarding)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing picked and no known default reports nothing", .timeLimit(.minutes(1)))
    func unknownDefaultIsNil() {
        #expect(resolve("luna", newChatDefault: nil) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sending the user default reports user_default", .timeLimit(.minutes(1)))
    func userDefaultIsUserDefault() {
        let userDefault = AIChatNewChatSelection(modelId: "haiku", reasoningEffort: nil, origin: .user)
        #expect(resolve("haiku", newChatDefault: userDefault) == .userDefault)
        #expect(resolve("haiku", isPicked: true, newChatDefault: userDefault) == .userDefault)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falling back from an unusable user default reports user_default_unavailable", .timeLimit(.minutes(1)))
    func unusableUserDefault() {
        let fellBack = AIChatNewChatSelection(modelId: "luna", reasoningEffort: nil, origin: .userDefaultUnavailable)
        #expect(resolve("luna", newChatDefault: fellBack) == .userDefaultUnavailable)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Picking another model with an unusable user default reports picked", .timeLimit(.minutes(1)))
    func pickedOverUnusableUserDefault() {
        let fellBack = AIChatNewChatSelection(modelId: "luna", reasoningEffort: nil, origin: .userDefaultUnavailable)
        #expect(resolve("claude", isPicked: true, newChatDefault: fellBack) == .picked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Raw values match the pixel parameter", .timeLimit(.minutes(1)))
    func rawValuesMatchPixel() {
        #expect(DuckAINewChatModelSource.pixelParameterKey == "model_source")
        #expect(DuckAINewChatModelSource.allCases.map(\.rawValue) == ["default", "picked", "onboarding", "fallback", "user_default", "user_default_unavailable"])
    }
}
