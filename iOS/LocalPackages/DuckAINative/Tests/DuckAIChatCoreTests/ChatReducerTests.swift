//
//  ChatReducerTests.swift
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
import Testing
@testable import DuckAIChatCore

@Suite struct ChatReducerTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func explicitTurnContextPreservesEveryPageInOrderWithoutDuplicatingInitialContext() throws {
        let second = PageContext(title: "Geese", url: URL(string: "https://example.com/geese"), content: "Geese migrate together.")
        var state = try Fixture.state(page: Fixture.page)
        _ = state.apply(.send("Compare birds", context: [.page(Fixture.page), .page(second)], at: Fixture.time(0)))
        #expect(state.userMessages.first?.parts == [.context(.page(Fixture.page)), .context(.page(second)), .text("Compare birds")])
        let turn = try Fixture.expectedTurn(for: state)
        #expect(turn.input.contains("Ducks are waterfowl."))
        #expect(turn.input.contains("Geese migrate together."))
        finishReply(.id(2), text: "Both are waterfowl", in: &state)
        _ = state.apply(.send("Tell me more", at: Fixture.time(3)))
        #expect(state.userMessages.last?.parts == [.text("Tell me more")])
        let followUp = try Fixture.expectedTurn(for: state)
        #expect(!followUp.history.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openingPromptSendsOnceWithContextOnTheFirstMessage() throws {
        var state = try Fixture.state(page: Fixture.page, opening: .prompt("What are ducks?"))

        let effects = state.apply(.opened(at: Fixture.time(0)))

        #expect(state.userMessages.map(\.parts) == [[.context(.page(Fixture.page)), .text("What are ducks?")]])
        #expect(effects == [.prepareProvider, .startReply(.id(2), try Fixture.expectedTurn(for: state))])
        #expect(state.status == .loading(.starting))
        #expect(state.streamInFlight == .id(2))

        let again = state.apply(.opened(at: Fixture.time(1)))

        #expect(again == [.prepareProvider])
        #expect(state.messages.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func summarizeRequestPutsTheRequestBeforeThePage() throws {
        var state = try Fixture.state(page: Fixture.page, opening: .request(.summarize))

        _ = state.apply(.opened(at: Fixture.time(0)))

        #expect(state.userMessages.first?.parts == [.context(.request(.summarize)), .context(.page(Fixture.page))])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openingWithoutAnOpeningOnlyPrepares() throws {
        var state = try Fixture.state(page: Fixture.page)

        #expect(state.apply(.opened(at: Fixture.time(0))) == [.prepareProvider])
        #expect(state.messages.isEmpty)
        #expect(state.status == .ready)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func firstTypedMessageCarriesTheContextAndLaterOnesDoNot() throws {
        var state = try Fixture.state(page: Fixture.page)
        _ = state.apply(.opened(at: Fixture.time(0)))

        _ = state.apply(.send("Hi", at: Fixture.time(1)))
        finishReply(.id(2), text: "Hello", in: &state)
        _ = state.apply(.send("More", at: Fixture.time(3)))

        #expect(state.userMessages.map(\.parts) == [
            [.context(.page(Fixture.page)), .text("Hi")],
            [.text("More")]
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func streamingReplyIsCommittedUnderItsOwnID() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))

        _ = state.apply(.provider(.id(2), .stage(.readingInput(estimatedTokens: 40, fraction: nil)), at: Fixture.time(1)))
        #expect(state.status == .loading(.provider(.readingInput(estimatedTokens: 40, fraction: nil))))

        _ = state.apply(.provider(.id(2), .textDelta("Hel"), at: Fixture.time(2)))
        _ = state.apply(.provider(.id(2), .textDelta("lo"), at: Fixture.time(3)))
        #expect(state.status == .streaming)
        #expect(state.liveReply?.parts == [.text("Hello")])

        let stats = GenerationStats(promptTokens: 40, generatedTokens: 2, loadTime: nil, promptTime: nil, generateTime: nil)
        _ = state.apply(.provider(.id(2), .finished(stats), at: Fixture.time(4)))

        #expect(state.assistantMessages == [
            AssistantMessage(id: .id(2), createdAt: Fixture.time(0), parts: [.text("Hello")], ending: .completed(stats))
        ])
        #expect(state.status == .ready)
        #expect(state.streamInFlight == .id(2))

        _ = state.apply(.providerEnded(.id(2), at: Fixture.time(5)))
        #expect(state.streamInFlight == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sendWhileRespondingIsRejectedWithoutChangingState() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        let before = state

        #expect(state.apply(.send("Again", at: Fixture.time(1))).isEmpty)
        #expect(state == before)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func blankSendIsIgnored() throws {
        var state = try Fixture.state()

        #expect(state.apply(.send("  \n ", at: Fixture.time(0))).isEmpty)
        #expect(state.messages.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stopKeepsPartialTextAndAsksTheProviderToStop() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.provider(.id(2), .textDelta("Hel"), at: Fixture.time(1)))

        let effects = state.apply(.stop(at: Fixture.time(2)))

        #expect(effects == [.requestStop(.id(2))])
        #expect(state.assistantMessages == [AssistantMessage(id: .id(2), createdAt: Fixture.time(0), parts: [.text("Hel")], ending: .stopped)])
        #expect(state.status == .ready)
        #expect(state.streamInFlight == .id(2))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stopBeforeAnyOutputDropsTheReply() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))

        #expect(state.apply(.stop(at: Fixture.time(1))) == [.requestStop(.id(2))])
        #expect(state.assistantMessages.isEmpty)
        #expect(state.status == .ready)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func eventsFromAStoppedReplyAreIgnored() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.provider(.id(2), .textDelta("Hel"), at: Fixture.time(1)))
        _ = state.apply(.stop(at: Fixture.time(2)))
        let afterStop = state

        _ = state.apply(.provider(.id(2), .textDelta("lo"), at: Fixture.time(3)))
        _ = state.apply(.provider(.id(2), .finished(nil), at: Fixture.time(4)))

        #expect(state == afterStop)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sendWhileAStoppedStreamDrainsIsQueuedUntilTheStreamEnds() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.stop(at: Fixture.time(1)))

        #expect(state.apply(.send("Again", at: Fixture.time(2))).isEmpty)
        #expect(state.status == .loading(.queued))

        let effects = state.apply(.providerEnded(.id(2), at: Fixture.time(3)))

        #expect(effects == [.startReply(.id(4), try Fixture.expectedTurn(for: state))])
        #expect(state.status == .loading(.starting))
        #expect(state.streamInFlight == .id(4))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stoppingAQueuedReplyDoesNotTouchTheProvider() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.stop(at: Fixture.time(1)))
        _ = state.apply(.send("Again", at: Fixture.time(2)))

        #expect(state.apply(.stop(at: Fixture.time(3))).isEmpty)
        #expect(state.apply(.providerEnded(.id(2), at: Fixture.time(4))).isEmpty)
        #expect(state.streamInFlight == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func finishedWithNothingIsAnEmptyResponseError() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))

        _ = state.apply(.provider(.id(2), .finished(nil), at: Fixture.time(1)))

        #expect(state.assistantMessages.isEmpty)
        #expect(state.status == .error(.emptyResponse))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func streamEndingWithoutATerminalEventFinishesTheReply() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.provider(.id(2), .textDelta("Hello"), at: Fixture.time(1)))

        _ = state.apply(.providerEnded(.id(2), at: Fixture.time(2)))

        #expect(state.assistantMessages.map(\.ending) == [.completed(nil)])
        #expect(state.status == .ready)
        #expect(state.streamInFlight == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func reasoningIsTimedAndClosedByTheFirstText() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))

        _ = state.apply(.provider(.id(2), .reasoningDelta("Think"), at: Fixture.time(1)))
        _ = state.apply(.provider(.id(2), .reasoningDelta("ing"), at: Fixture.time(2)))
        #expect(state.liveReply?.parts == [.reasoning(Reasoning(text: "Thinking", timing: .thinking(since: Fixture.time(1))))])

        _ = state.apply(.provider(.id(2), .textDelta("Answer"), at: Fixture.time(4)))

        #expect(state.liveReply?.parts == [
            .reasoning(Reasoning(text: "Thinking", timing: .done(.seconds(3)))),
            .text("Answer")
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stoppingWhileThinkingClosesTheReasoning() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.provider(.id(2), .reasoningDelta("Hmm"), at: Fixture.time(1)))

        _ = state.apply(.stop(at: Fixture.time(3)))

        #expect(state.assistantMessages.first?.parts == [.reasoning(Reasoning(text: "Hmm", timing: .done(.seconds(2))))])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func refusalIsAPartNotAnError() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))

        _ = state.apply(.provider(.id(2), .refusal(Refusal(detectedBy: "guardrail")), at: Fixture.time(1)))

        #expect(state.assistantMessages.first?.parts == [.refusal(Refusal(detectedBy: "guardrail"))])
        #expect(state.status == .ready)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failureKeepsPartialTextAndRedoStartsAgain() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.provider(.id(2), .textDelta("Hel"), at: Fixture.time(1)))
        _ = state.apply(.providerFailed(.id(2), .network, at: Fixture.time(2)))

        #expect(state.assistantMessages.map(\.ending) == [.interrupted])
        #expect(state.status == .error(.network))
        #expect(state.canRedo)

        _ = state.apply(.providerEnded(.id(2), at: Fixture.time(3)))
        let effects = state.apply(.redo(at: Fixture.time(4)))

        #expect(state.assistantMessages.isEmpty)
        #expect(state.userMessages.count == 1)
        #expect(effects == [.startReply(.id(3), try Fixture.expectedTurn(for: state))])
        #expect(state.status == .loading(.starting))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func redoReplacesACompletedReply() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        finishReply(.id(2), text: "Hello", in: &state)

        _ = state.apply(.redo(at: Fixture.time(5)))

        #expect(state.assistantMessages.isEmpty)
        #expect(state.liveReply?.id == .id(3))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func replyWaitsForTheModelDownload() throws {
        var state = try Fixture.state(availability: .needsDownload(bytes: 1_000))
        #expect(state.canSend)

        #expect(state.apply(.send("Hi", at: Fixture.time(0))).isEmpty)
        #expect(state.status == .loading(.waitingForModel))
        #expect(state.streamInFlight == nil)

        #expect(state.apply(.availabilityChanged(.downloading(fraction: 0.5))).isEmpty)

        let effects = state.apply(.availabilityChanged(.ready))

        #expect(effects == [.startReply(.id(2), try Fixture.expectedTurn(for: state))])
        #expect(state.status == .loading(.starting))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unsupportedProviderFailsTheLiveReplyAndBlocksSending() throws {
        var state = try Fixture.state(availability: .needsDownload(bytes: 1_000))
        _ = state.apply(.send("Hi", at: Fixture.time(0)))

        _ = state.apply(.availabilityChanged(.unsupported(reason: "Needs 6 GB")))

        #expect(state.status == .error(.modelUnavailable(reason: "Needs 6 GB")))
        #expect(!state.canSend)
        #expect(!state.canRedo)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unsupportedProviderStopsAStreamingReply() throws {
        var state = try Fixture.state()
        _ = state.apply(.send("Hi", at: Fixture.time(0)))
        _ = state.apply(.provider(.id(2), .textDelta("Hel"), at: Fixture.time(1)))

        let effects = state.apply(.availabilityChanged(.unsupported(reason: "Unloaded")))

        #expect(effects == [.requestStop(.id(2))])
        #expect(state.assistantMessages.isEmpty)
        #expect(state.status == .error(.modelUnavailable(reason: "Unloaded")))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func openingWithAnUnsupportedProviderFailsInsteadOfWaiting() throws {
        var state = try Fixture.state(opening: .prompt("Hi"), availability: .unsupported(reason: "MLX requires a device."))

        #expect(state.apply(.opened(at: Fixture.time(0))) == [.prepareProvider])
        #expect(state.status == .error(.modelUnavailable(reason: "MLX requires a device.")))
        #expect(state.userMessages.count == 1)
    }

    private func finishReply(_ id: MessageID, text: String, in state: inout ChatState) {
        _ = state.apply(.provider(id, .textDelta(text), at: Fixture.time(1)))
        _ = state.apply(.provider(id, .finished(nil), at: Fixture.time(2)))
        _ = state.apply(.providerEnded(id, at: Fixture.time(2)))
    }
}
