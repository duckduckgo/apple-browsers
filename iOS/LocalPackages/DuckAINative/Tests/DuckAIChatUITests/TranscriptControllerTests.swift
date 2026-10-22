//
//  TranscriptControllerTests.swift
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

#if canImport(UIKit)
import DuckAIChatCore
import Testing
import UIKit
@testable import DuckAIChatUI

@Suite @MainActor struct TranscriptControllerTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func hiddenTranscriptAcceptsFinalSnapshotWithoutAppearance() throws {
        let controller = makeController()
        var state = ChatState(conversation: ConversationID(), context: try ChatContext(page: nil, selections: [], opening: nil),
                              budget: PromptBudget(contextWindowTokens: 8192), availability: .ready)
        _ = state.apply(.send("Question", at: .now))
        let id = try #require(state.liveReply?.id)
        _ = state.apply(.provider(id, .textDelta("First"), at: .now))
        controller.apply(snapshot: state)
        _ = state.apply(.provider(id, .textDelta(" and final"), at: .now))
        _ = state.apply(.provider(id, .finished(nil), at: .now))
        controller.apply(snapshot: state)
        let texts = descendants(controller.view).compactMap { ($0 as? UITextView)?.text }
        #expect(texts.contains("First and final"))
        #expect(descendants(controller.view).compactMap { ($0 as? UILabel)?.text }.contains("Remote model"))
        #expect(!descendants(controller.view).contains { $0 is UITextField })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func displayClockDoesNotRetainRemovedController() {
        weak var released: ChatViewController?
        do {
            let controller = makeController()
            released = controller
            controller.loadViewIfNeeded()
            controller.viewDidAppear(false)
        }
        #expect(released == nil)
    }

    private func makeController() -> ChatViewController {
        ChatViewController(surface: .tab, metadata: ChatDisplayMetadata(title: "Remote model"),
                           actions: ChatActions(close: {}, continueInWeb: { _ in }, redo: {}, download: {}))
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
#endif
