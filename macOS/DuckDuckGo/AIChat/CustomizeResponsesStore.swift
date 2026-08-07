//
//  CustomizeResponsesStore.swift
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
import AIChat

/// Reads/writes the Duck.ai Customize Responses state from the native-storage bridge and derives the
/// omnibar/NTP menu-row state (toggle + localized sub-label). Shared by the native omnibar
/// (`AIChatOmnibarContainerViewController`) and the NTP (`NewTabPageOmnibarConfigProvider`).
final class CustomizeResponsesStore {

    private let storageHandler: DuckAiNativeStorageHandling?

    init(storageHandler: DuckAiNativeStorageHandling?) {
        self.storageHandler = storageHandler
    }

    func currentState() -> CustomizeResponsesState {
        guard let storageHandler else { return .none }
        let customization = (try? storageHandler.getEntry(key: CustomizeResponsesStorageKey.customization)) ?? nil
        let active = (try? storageHandler.getEntry(key: CustomizeResponsesStorageKey.active)) ?? nil
        return CustomizeResponsesState.make(customizationValue: customization,
                                            activeValue: active,
                                            clarifiesLabel: UserText.aiChatCustomizeResponsesClarifies,
                                            translations: Self.translations)
    }

    func setActive(_ active: Bool) {
        try? storageHandler?.putEntry(key: CustomizeResponsesStorageKey.active, value: active ? "true" : "false")
    }

    /// Maps the frontend's stored English ids to their localized `UserText` labels for the sub-label.
    /// Kept macOS-side (not in the shared AIChat package) so these strings are translated only for the
    /// macOS locale set — iOS hasn't committed to a native Customize Responses entry point. Keyed per
    /// field so the same id under different fields (e.g. "Writer", "Professional") resolves its own
    /// translation; any id absent here falls back to its raw (English) value.
    static let translations = CustomizeResponsesTranslations(
        tone: [
            "Casual": UserText.aiChatCustomizeResponsesToneCasual,
            "Professional": UserText.aiChatCustomizeResponsesToneProfessional,
            "Friendly": UserText.aiChatCustomizeResponsesToneFriendly,
            "Playful": UserText.aiChatCustomizeResponsesTonePlayful,
            "Empathetic": UserText.aiChatCustomizeResponsesToneEmpathetic,
            "Ducky": UserText.aiChatCustomizeResponsesToneDucky
        ],
        length: [
            "Short": UserText.aiChatCustomizeResponsesLengthShort,
            "Shortest": UserText.aiChatCustomizeResponsesLengthShortest
        ],
        assistantRole: [
            "Brainstorm partner": UserText.aiChatCustomizeResponsesAiRoleBrainstormPartner,
            "Career coach": UserText.aiChatCustomizeResponsesAiRoleCareerCoach,
            "Chef": UserText.aiChatCustomizeResponsesAiRoleChef,
            "Coding coach": UserText.aiChatCustomizeResponsesAiRoleCodingCoach,
            "Editor": UserText.aiChatCustomizeResponsesAiRoleEditor,
            "Entertainment guide": UserText.aiChatCustomizeResponsesAiRoleEntertainmentGuide,
            "Fitness trainer": UserText.aiChatCustomizeResponsesAiRoleFitnessTrainer,
            "Gardener": UserText.aiChatCustomizeResponsesAiRoleGardener,
            "Homework helper": UserText.aiChatCustomizeResponsesAiRoleHomeworkHelper,
            "Language tutor": UserText.aiChatCustomizeResponsesAiRoleLanguageTutor,
            "Life coach": UserText.aiChatCustomizeResponsesAiRoleLifeCoach,
            "Marketer": UserText.aiChatCustomizeResponsesAiRoleMarketer,
            "Product manager": UserText.aiChatCustomizeResponsesAiRoleProductManager,
            "Public speaking coach": UserText.aiChatCustomizeResponsesAiRolePublicSpeakingCoach,
            "Social media copywriter": UserText.aiChatCustomizeResponsesAiRoleSocialMediaCopywriter,
            "Storyteller": UserText.aiChatCustomizeResponsesAiRoleStoryteller,
            "Summarizer": UserText.aiChatCustomizeResponsesAiRoleSummarizer,
            "Tech support specialist": UserText.aiChatCustomizeResponsesAiRoleTechSupportSpecialist,
            "Teacher": UserText.aiChatCustomizeResponsesAiRoleTeacher,
            "Translator": UserText.aiChatCustomizeResponsesAiRoleTranslator,
            "Travel guide": UserText.aiChatCustomizeResponsesAiRoleTravelGuide,
            "Trivia expert": UserText.aiChatCustomizeResponsesAiRoleTriviaExpert,
            "Writer": UserText.aiChatCustomizeResponsesAiRoleWriter
        ],
        userRole: [
            "Parent": UserText.aiChatCustomizeResponsesYourRoleParent,
            "Professional": UserText.aiChatCustomizeResponsesYourRoleProfessional,
            "Programmer": UserText.aiChatCustomizeResponsesYourRoleProgrammer,
            "Student": UserText.aiChatCustomizeResponsesYourRoleStudent,
            "Writer": UserText.aiChatCustomizeResponsesYourRoleWriter
        ]
    )
}
