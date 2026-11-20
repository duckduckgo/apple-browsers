//
//  UnifiedSuggestionsViewModelTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedSuggestionsViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    func test_searchEmptyWithFavorites_publishesFavorites() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .favorites)
    }

    func test_searchTyping_publishesList() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .list(.search))
    }

    func test_modeSwitchFromLogoToFavorites_waitsForTheLogoButTypingDoesNot() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .aiChat, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .logo)

        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertEqual(sut.content, .favorites)
        XCTAssertTrue(sut.waitsForLogoFadeOut)

        inputs.send(.init(mode: .search, isTyping: true, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertEqual(sut.content, .list(.search))
        XCTAssertFalse(sut.waitsForLogoFadeOut)
    }

    func test_focusInAnotherModeThanTheLastSession_doesNotWaitForTheLogo() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .aiChat, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .logo)

        sut.prepareForActivation()
        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertEqual(sut.content, .favorites)
        XCTAssertFalse(sut.waitsForLogoFadeOut)
    }

    func test_modeSwitchFromALogoHiddenForLackOfRoom_doesNotWaitForIt() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .aiChat, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        // Beside an embedded hatch, a logo without a backdrop frame is not on screen.
        sut.setEscapeHatchPlacement(.embedded)

        inputs.send(.init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        XCTAssertEqual(sut.content, .favorites)
        XCTAssertFalse(sut.waitsForLogoFadeOut)
    }

    func test_modeSwitchLosingRoomForTheLogo_retainsItsFrameAndMarkOnlyForLegacyFade() throws {
        for mode in [TextEntryMode.search, .aiChat] {
            for usesRedesign in [false, true] {
                for usesScrollableHatch in [false, true] {
                    for isFloatingUIEnabled in [false, true] {
                        for resolvesBeforeHost in [false, true] {
                            let (sut, inputs, sourceFrame) = try makeLogoSUT(mode: mode, usesRedesign: usesRedesign,
                                                                           usesScrollableHatch: usesScrollableHatch,
                                                                           isFloatingUIEnabled: isFloatingUIEnabled)
                            let destination: TextEntryMode = mode == .search ? .aiChat : .search
                            if resolvesBeforeHost { inputs.send(Self.logoInputs(mode: destination)) }
                            sut.performLogoModeChange(to: destination) {
                                if !resolvesBeforeHost { inputs.send(Self.logoInputs(mode: destination)) }
                                setLogoViewport(CGRect(x: 0, y: 0, width: 440, height: 220), on: sut,
                                                isFloatingUIEnabled: isFloatingUIEnabled)
                            }

                            XCTAssertEqual(sut.content, .logo)
                            XCTAssertEqual(sut.logoModeChange?.source?.frame, sourceFrame)
                            XCTAssertEqual(sut.logoModeChange?.source?.progress, mode == .search ? 0 : 1)
                            XCTAssertEqual(sut.logoModeChange?.isFadingOut, !usesRedesign)
                            XCTAssertEqual(sut.waitsForLogoFadeOut, !usesRedesign)
                            XCTAssertNil(sut.logoLayout(in: CGRect(x: 0, y: 0, width: 440, height: 220)).hatchLayout?.visibleFrame)
                        }
                    }
                }
            }
        }
    }

    func test_modeSwitchReplacingTheLogo_delaysFavoritesOrRecentsOnlyForLegacy() throws {
        for mode in [TextEntryMode.search, .aiChat] {
            for usesRedesign in [false, true] {
                let (sut, inputs, sourceFrame) = try makeLogoSUT(mode: mode, usesRedesign: usesRedesign)
                let destination: TextEntryMode = mode == .search ? .aiChat : .search
                sut.performLogoModeChange(to: destination) {
                    inputs.send(.init(mode: destination, isTyping: false, hasFavorites: true, hasMessages: false,
                                      hasRecents: true, resultsPending: false))
                }

                XCTAssertEqual(sut.content, destination == .search ? .favorites : .list(.recents))
                XCTAssertEqual(sut.logoModeChange?.source?.frame, sourceFrame)
                XCTAssertEqual(sut.logoModeChange?.source?.progress, mode == .search ? 0 : 1)
                XCTAssertEqual(sut.logoModeChange?.isFadingOut, !usesRedesign)
                XCTAssertEqual(sut.waitsForLogoFadeOut, !usesRedesign)
            }
        }
    }

    func test_modeSwitchWithRoomForBothLogos_morphsWithoutWaiting() throws {
        for mode in [TextEntryMode.search, .aiChat] {
            let (sut, inputs, _) = try makeLogoSUT(mode: mode)
            let destination: TextEntryMode = mode == .search ? .aiChat : .search
            sut.performLogoModeChange(to: destination) { inputs.send(Self.logoInputs(mode: destination)) }

            XCTAssertFalse(sut.waitsForLogoFadeOut)
            XCTAssertEqual(sut.logoModeChange?.isFadingOut, false)
            XCTAssertTrue(sut.logoModel.morphs)
            XCTAssertEqual(sut.logoModel.progress, destination == .search ? 0 : 1)
        }
    }

    func test_modeSwitchFromHiddenLogo_doesNotCaptureTheDestinationAsItsSource() throws {
        let (sut, inputs, frame) = try makeLogoSUT(mode: .search)
        sut.backdropLogoFrame = nil
        sut.prepareLogoModeChange(to: .aiChat)
        XCTAssertNil(sut.logoModeChange?.source)

        sut.backdropLogoFrame = frame
        inputs.send(Self.logoInputs(mode: .aiChat))
        sut.performLogoModeChange(to: .aiChat) {}

        XCTAssertNil(sut.logoModeChange?.source)
        XCTAssertFalse(sut.waitsForLogoFadeOut)
    }

    func test_typingImmediatelyAfterAModeSwitch_doesNotWaitForTheLogo() throws {
        let (sut, inputs, _) = try makeLogoSUT(mode: .search)
        sut.performLogoModeChange(to: .aiChat) { inputs.send(Self.logoInputs(mode: .aiChat)) }

        inputs.send(.init(mode: .aiChat, isTyping: true, hasFavorites: false, hasMessages: false,
                          hasRecents: false, resultsPending: false))

        XCTAssertEqual(sut.content, .list(.duckAI))
        XCTAssertFalse(sut.waitsForLogoFadeOut)
        XCTAssertNil(sut.logoModeChange?.source)
    }

    func test_reversingDuringLogoFade_keepsTheDisplayedSourceAndCancelsItsOldCompletion() throws {
        let (sut, inputs, sourceFrame) = try makeLogoSUT(mode: .search)
        sut.performLogoModeChange(to: .aiChat) {
            inputs.send(Self.logoInputs(mode: .aiChat))
            sut.logoViewportFrame = CGRect(x: 0, y: 0, width: 440, height: 220)
        }
        sut.startLogoFadeOut()
        sut.performLogoModeChange(to: .search) { inputs.send(Self.logoInputs(mode: .search)) }

        XCTAssertEqual(sut.logoModeChange?.source?.frame, sourceFrame)
        XCTAssertEqual(sut.logoModeChange?.source?.progress, 0)
        let oldCompletion = expectation(description: "Previous fade completion cannot clear the reversed switch")
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusedContentFade.duration + 0.05) {
            XCTAssertEqual(sut.logoModeChange?.mode, .search)
            XCTAssertEqual(sut.logoModeChange?.source?.frame, sourceFrame)
            oldCompletion.fulfill()
        }
        wait(for: [oldCompletion], timeout: 1)
        sut.cancelLogoModeChange()
    }

    func test_logoFadeCompletion_releasesItsSourceAndContentWait() throws {
        let (sut, inputs, _) = try makeLogoSUT(mode: .search)
        sut.performLogoModeChange(to: .aiChat) {
            inputs.send(Self.logoInputs(mode: .aiChat))
            sut.logoViewportFrame = CGRect(x: 0, y: 0, width: 440, height: 220)
        }
        sut.startLogoFadeOut()

        let completed = expectation(description: "The outgoing logo releases destination content after its fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusedContentFade.duration + 0.05) {
            XCTAssertNil(sut.logoModeChange?.source)
            XCTAssertFalse(sut.waitsForLogoFadeOut)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func test_focusAndDismiss_clearAnOutgoingLogo() throws {
        for reset in [0, 1, 2] {
            let (sut, inputs, _) = try makeLogoSUT(mode: .search)
            sut.performLogoModeChange(to: .aiChat) {
                inputs.send(Self.logoInputs(mode: .aiChat))
                sut.logoViewportFrame = CGRect(x: 0, y: 0, width: 440, height: 220)
            }
            XCTAssertEqual(sut.logoModeChange?.isFadingOut, true)

            switch reset {
            case 0: sut.prepareForActivation()
            case 1: sut.beginDismissFade()
            default: sut.morphLogoHomeForDismiss(matching: 0.2)
            }

            XCTAssertNil(sut.logoModeChange)
            XCTAssertFalse(sut.waitsForLogoFadeOut)
        }
    }

    private func makeLogoSUT(mode: TextEntryMode, usesRedesign: Bool = false, usesScrollableHatch: Bool = true,
                             isFloatingUIEnabled: Bool = true)
        throws -> (UnifiedSuggestionsViewModel, CurrentValueSubject<UnifiedSuggestionsInputs, Never>, CGRect) {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(Self.logoInputs(mode: mode))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        sut.usesRedesignedNewTabPageLayout = usesRedesign
        sut.setEscapeHatchPlacement(usesScrollableHatch ? .embedded : .pinned)
        sut.chromeInsetTop = 100
        sut.contentTopInset = 100
        if usesScrollableHatch {
            sut.setEmbeddedEscapeHatchGeometry(.init(frame: CGRect(x: 16, y: 120, width: 408, height: 56), appliedContentTopInset: 100))
        }
        let viewport = CGRect(x: 0, y: 0, width: 440, height: 900)
        setLogoViewport(viewport, on: sut, isFloatingUIEnabled: isFloatingUIEnabled)
        let frame = try XCTUnwrap(sut.logoLayout(in: viewport).hatchLayout?.visibleFrame)
        sut.backdropLogoFrame = frame
        return (sut, inputs, frame)
    }

    private func setLogoViewport(_ viewport: CGRect, on sut: UnifiedSuggestionsViewModel, isFloatingUIEnabled: Bool) {
        if isFloatingUIEnabled {
            sut.logoViewportFrame = viewport
        } else {
            sut.logoHostFrame = viewport
        }
    }

    private static func logoInputs(mode: TextEntryMode) -> UnifiedSuggestionsInputs {
        .init(mode: mode, isTyping: false, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false)
    }

    func test_uneditedURLWithoutRecentChats_hidesQueryRowsUntilTyping() {
        let query = "https://example.com"
        let sections = DuckAISuggestionsSource.sections(from: .init(chats: [], urls: [], isPending: false), query: query)
        let duckAIList = SuggestionsListViewModel(source: StubSuggestionsSource(sections: sections))
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            UnifiedSuggestionsInputsMerger.merge(mode: .aiChat, text: query, hasUserInteractedWithText: false,
                                                 search: .init(hasFavorites: false, hasMessages: false),
                                                 duckAI: .init(hasRecents: false, settled: true)))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()),
                                              duckAIListViewModel: duckAIList)

        XCTAssertEqual(sut.content, .logo)
        XCTAssertFalse(duckAIList.sections.isEmpty)
        XCTAssertTrue(sut.listViewModel(for: .recents).sections.isEmpty)

        inputs.send(UnifiedSuggestionsInputsMerger.merge(mode: .aiChat, text: query, hasUserInteractedWithText: true,
                                                        search: .init(hasFavorites: false, hasMessages: false),
                                                        duckAI: .init(hasRecents: false, settled: true)))

        XCTAssertEqual(sut.content, .list(.duckAI))
        XCTAssertEqual(sut.listViewModel(for: .duckAI).sections, sections)
    }

    // MARK: - Duck.ai suggestions shown

    private func makeDuckAISUT(mode: TextEntryMode, sections: [SuggestionSection])
        -> (UnifiedSuggestionsViewModel, CurrentValueSubject<UnifiedSuggestionsInputs, Never>, StubSuggestionsSource, () -> Int) {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: mode, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let duckAISource = StubSuggestionsSource(sections: sections)
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        var shownCount = 0
        sut.onDuckAISuggestionsShown = { shownCount += 1 }
        sut.setDuckAIListViewModel(SuggestionsListViewModel(source: duckAISource))
        inputs.send(inputs.value)
        return (sut, inputs, duckAISource, { shownCount })
    }

    func test_duckAIListWithRows_reportsShownOncePerFocus() {
        let (sut, inputs, duckAISource, shownCount) = makeDuckAISUT(mode: .aiChat, sections: [Self.section])
        duckAISource.subject.send([Self.section, Self.section])
        XCTAssertEqual(shownCount(), 1)

        sut.prepareForActivation()
        inputs.send(inputs.value)
        XCTAssertEqual(shownCount(), 2)
    }

    func test_duckAIRowsArrivingAfterTheListShows_reportShown() {
        let (sut, _, duckAISource, shownCount) = makeDuckAISUT(mode: .aiChat, sections: [])
        XCTAssertEqual(shownCount(), 0)

        duckAISource.subject.send([Self.section])
        XCTAssertEqual(shownCount(), 1)
        withExtendedLifetime(sut) {}
    }

    func test_searchList_neverReportsDuckAIShown() {
        let (sut, _, duckAISource, shownCount) = makeDuckAISUT(mode: .search, sections: [Self.section])
        duckAISource.subject.send([Self.section])
        XCTAssertEqual(shownCount(), 0)
        withExtendedLifetime(sut) {}
    }

    private static let section = SuggestionSection(id: "chats", rows: [])
}

private final class StubSuggestionsSource: SuggestionsSource {
    let subject: CurrentValueSubject<[SuggestionSection], Never>
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> { subject.eraseToAnyPublisher() }
    init(sections: [SuggestionSection]) { subject = CurrentValueSubject(sections) }
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}

private final class EmptySuggestionsSource: SuggestionsSource {
    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never> = Just([]).eraseToAnyPublisher()
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}
