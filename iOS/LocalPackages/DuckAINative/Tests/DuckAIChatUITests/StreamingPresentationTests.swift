//
//  StreamingPresentationTests.swift
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

import DuckAIChatCore
import Foundation
import Testing
@testable import DuckAIChatUI

@Suite struct StreamingPresentationTests {
    private func reply(_ text: String, ending: ReplyEnding? = nil, id: Int = 1) -> AssistantReplySnapshot {
        AssistantReplySnapshot(id: MessageID(rawValue: id), parts: [.text(text)],
                               phase: ending.map { .ended($0) } ?? .receiving(.starting))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unevenBurstsDrainExactlyAndCompletionKeepsItsCursor() {
        let source = "# Ducks\n\n" + String(repeating: "A 🦆 and e\u{301} swim. ", count: 80)
        var display = ReplyPresentation(reply(""))
        var arrived = ""
        for chunk in source.map(String.init) {
            arrived += chunk
            display.receive(reply(arrived))
            display.advance(by: 1.0 / 240)
            #expect(arrived.hasPrefix(text(display)))
        }
        let before = text(display)
        display.receive(reply(source, ending: .completed(nil)))
        #expect(text(display) == before)
        #expect(display.needsFrame)
        var previous = before
        for _ in 0..<240 {
            display.advance(by: 1.0 / 60)
            #expect(text(display).hasPrefix(previous))
            #expect(source.hasPrefix(text(display)))
            previous = text(display)
        }
        #expect(text(display) == source)
        #expect(!display.rendered.isRevealing)
        #expect(!display.needsFrame)
        let final = display.rendered
        display.advance(by: 1)
        #expect(display.rendered == final)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stoppedAndFailedRepliesFlushOnlyAcceptedSource() {
        for ending in [ReplyEnding.stopped, .interrupted] {
            let source = String(repeating: "accepted ", count: 100)
            var display = ReplyPresentation(reply(source))
            display.advance(by: 1.0 / 60)
            #expect(text(display).count < source.count)
            display.receive(reply(source, ending: ending))
            #expect(text(display) == source)
            #expect(!display.needsFrame)
            #expect(!display.rendered.isRevealing)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func historyDoesNotReplayAndNewTurnSettlesDrainingReply() {
        let source = String(repeating: "old answer ", count: 100)
        let history = ReplyPresentation(reply(source, ending: .completed(nil)))
        #expect(text(history) == source)
        #expect(!history.needsFrame)
        var live = ReplyPresentation(reply(source))
        live.advance(by: 1.0 / 60)
        live.receive(reply(source, ending: .completed(nil)), settle: true)
        #expect(text(live) == source)
        #expect(!live.needsFrame)
        live.receive(reply("replacement", id: 2))
        #expect(text(live).isEmpty)
        #expect(live.target.id == MessageID(rawValue: 2))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func frameBudgetIsRefreshIndependentAndStallsAreCapped() {
        let source = String(repeating: "word ", count: 300)
        var fast = ReplyPresentation(reply(source))
        var slow = fast
        for _ in 0..<60 { fast.advance(by: 1.0 / 120) }
        for _ in 0..<30 { slow.advance(by: 1.0 / 60) }
        #expect(abs(text(fast).count - text(slow).count) < 20)
        var stalled = ReplyPresentation(reply(source))
        stalled.advance(by: 0)
        #expect(text(stalled).isEmpty)
        stalled.advance(by: 60)
        #expect(!text(stalled).isEmpty)
        #expect(text(stalled).count < source.count / 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func laterPartsWaitForEarlierTextAndGraphemeExtensionsArePreserved() {
        let first = String(repeating: "first ", count: 100)
        let parts: [AssistantPart] = [.text(first), .source(Source(url: URL(string: "https://example.com")!, title: "Source", site: nil)),
                                      .text("last e\u{301} 👨‍👩‍👧‍👦\r\n")]
        var display = ReplyPresentation(AssistantReplySnapshot(id: MessageID(rawValue: 1), parts: parts, phase: .receiving(.starting)))
        display.advance(by: 1.0 / 60)
        #expect(display.rendered.parts.count == 1)
        for _ in 0..<300 { display.advance(by: 1.0 / 60) }
        #expect(display.rendered.parts == parts)
        var extensionDisplay = ReplyPresentation(reply("e"))
        extensionDisplay.advance(by: 0.05)
        extensionDisplay.receive(reply("e\u{301}", ending: .completed(nil)))
        extensionDisplay.advance(by: 0.05)
        #expect(text(extensionDisplay) == "e\u{301}")
        #expect(!extensionDisplay.needsFrame)
    }

    private func text(_ display: ReplyPresentation) -> String {
        display.rendered.parts.compactMap { if case .text(let value) = $0 { value } else { nil } }.joined()
    }
}
