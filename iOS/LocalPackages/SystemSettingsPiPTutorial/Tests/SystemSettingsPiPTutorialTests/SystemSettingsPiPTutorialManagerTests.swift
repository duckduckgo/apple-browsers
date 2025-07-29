//
//  SystemSettingsPiPTutorialManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Testing
import UIKit
import SystemSettingsPiPTutorialTestSupport
@testable import SystemSettingsPiPTutorial

@MainActor
@Suite("System Settings PiP Tutorial - Manager Tests")
struct SystemSettingsPiPTutorialManagerTests {
    private var videoPlayerMock = MockSystemSettingsPiPTutorialPlayer()
    private var urlProviderMock = MockSystemSettingsPiPTutorialURLManager()
    private var urlOpenerMock = MockSystemSettingsPiPTutorialURLOpener()
    private var eventMapperMock = MockSystemSettingsPiPTutorialEventMapper()

    @Test("Check Registering Provider For Destination Asks URL Provider To Register Provider")
    func checkRegisteringProviderForDestinationAsksURLProviderToRegisterProvider() async throws {
        // GIVEN
        let sut = SystemSettingsPiPTutorialManager(
            playerView: UIView(),
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        let provider = MockPiPTutorialURLProvider()

        #expect(!urlProviderMock.didCallRegisterProvider)
        #expect(urlProviderMock.capturedProvider == nil)
        #expect(urlProviderMock.capturedRDestination == nil)

        // WHEN
        sut.register(provider, for: .mock)

        // THEN
        #expect(urlProviderMock.didCallRegisterProvider)
        #expect(urlProviderMock.capturedProvider === provider)
        #expect(urlProviderMock.capturedRDestination == .mock)
    }

    @Test("Check Calling Stop PiP Tutorial Call Stop on Video Player")
    func checkCallingStopPiPTutorialIfNeededAsksVideoPlayerToStopPlayback() async throws {
        // GIVEN
        let playerView = UIView()
        let sut = SystemSettingsPiPTutorialManager(
            playerView: playerView,
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        let presenterMock = MockSystemSettingsPiPTutorialPresenting()
        sut.setPresenter(presenterMock)

        #expect(!videoPlayerMock.didCallStop)
        #expect(!presenterMock.didCallDetachPlayerView)
        #expect(presenterMock.capturedPlayerView == nil)

        // WHEN
        sut.stopPiPTutorialIfNeeded()

        // THEN
        #expect(videoPlayerMock.didCallStop)
        #expect(presenterMock.didCallDetachPlayerView)
        #expect(presenterMock.capturedPlayerView == playerView)
    }

    @Test("Check When Picture In Picture Is Not Supported Video Does Not Play And Navigate To Destination")
    func checkWhenPiPIsNotSupportedThenDoNotPlayVideoAndNavigatesToDestination() async throws {
        // GIVEN
        videoPlayerMock.isPiPSupported = false
        let sut = SystemSettingsPiPTutorialManager(
            playerView: UIView(),
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        #expect(!urlProviderMock.didCallUrlForDestination)
        #expect(!urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == nil)

        // WHEN
        sut.playPiPTutorialAndNavigateTo(destination: .mock)

        // THEN
        #expect(!urlProviderMock.didCallUrlForDestination)
        #expect(urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == SystemSettingsPiPTutorialDestination.mock.url)
    }

    @Test("Check When Provider Can't Resolve URL Video Does Not Play And Navigate To Destination")
    func checkWhenProviderCannotResolveURLThenDoNotPlayVideoAndNavigatesToDestination() async throws {
        // GIVEN
        urlProviderMock.urlForDestinationResult = .failure(.noProviderAvailable(destination: .mock))
        let sut = SystemSettingsPiPTutorialManager(
            playerView: UIView(),
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        #expect(!urlProviderMock.didCallUrlForDestination)
        #expect(!urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == nil)

        // WHEN
        sut.playPiPTutorialAndNavigateTo(destination: .mock)

        // THEN
        #expect(urlProviderMock.didCallUrlForDestination)
        #expect(urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == SystemSettingsPiPTutorialDestination.mock.url)
    }

    @available(iOS 16, *)
    @Test("Check When Video Load Successfully and Becomes Ready To Play Starts Playback And Navigate To Destination", .timeLimit(.minutes(1)))
    func checkWhenVideoLoadsSuccessfullyAndBecomeReadyToPlayThenStartPlaybackAndNavigatesToDestination() async throws {
        // GIVEN
        let playerView = UIView()
        let sut = SystemSettingsPiPTutorialManager(
            playerView: playerView,
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        let presenterMock = MockSystemSettingsPiPTutorialPresenting()
        sut.setPresenter(presenterMock)
        #expect(!presenterMock.didCallAttachPlayerView)
        #expect(presenterMock.capturedPlayerView == nil)

        sut.playPiPTutorialAndNavigateTo(destination: .mock)
        #expect(!videoPlayerMock.didCallPlay)
        #expect(!urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == nil)

        await withCheckedContinuation { continuation in
            videoPlayerMock.onPlay = {
                continuation.resume()
            }
            // WHEN
            videoPlayerMock.send(event: .readyToPlay)
        }

        // THEN
        #expect(urlProviderMock.didCallUrlForDestination)
        #expect(videoPlayerMock.didCallPlay)
        #expect(urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == SystemSettingsPiPTutorialDestination.mock.url)
        #expect(presenterMock.didCallAttachPlayerView)
        #expect(presenterMock.capturedPlayerView == playerView)
    }

    @available(iOS 16, *)
    @Test("Check When Video Fails To Load Does Not Start Playback And Navigate To Destination", .timeLimit(.minutes(1)))
    func checkWhenVideoFailsToLoadThenDoesNotStartPlaybackAndNavigatesToDestination() async throws {
        // GIVEN
        let playerView = UIView()
        let sut = SystemSettingsPiPTutorialManager(
            playerView: playerView,
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        let presenterMock = MockSystemSettingsPiPTutorialPresenting()
        sut.setPresenter(presenterMock)
        #expect(!presenterMock.didCallAttachPlayerView)
        #expect(presenterMock.capturedPlayerView == nil)

        sut.playPiPTutorialAndNavigateTo(destination: .mock)
        #expect(!videoPlayerMock.didCallPlay)
        #expect(!urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == nil)

        await withCheckedContinuation { continuation in
            urlOpenerMock.onOpenURL = {
                continuation.resume()
            }
            // WHEN
            videoPlayerMock.send(event: .failed)
        }

        // THEN
        #expect(urlProviderMock.didCallUrlForDestination)
        #expect(!videoPlayerMock.didCallPlay)
        #expect(urlOpenerMock.didCallOpenURL)
        #expect(urlOpenerMock.capturedURL == SystemSettingsPiPTutorialDestination.mock.url)
        #expect(presenterMock.didCallAttachPlayerView)
        #expect(presenterMock.capturedPlayerView == playerView)
    }

    @available(iOS 16, *)
    @Test("Check When Video Fails Send Debug Event", .timeLimit(.minutes(1)))
    func checkWhenVideoFailsToLoadThenSendEvent() async throws {
        // GIVEN
        let error = NSError(domain: #function, code: 0, userInfo: nil)
        let url = URL(string: "www.example.com/video.mp4")
        videoPlayerMock.currentItemError = error
        videoPlayerMock.currentItemURL = url
        let sut = SystemSettingsPiPTutorialManager(
            playerView: UIView(),
            videoPlayer: videoPlayerMock,
            pipTutorialURLProvider: urlProviderMock,
            eventMapper: eventMapperMock,
            urlOpener: urlOpenerMock
        )
        sut.playPiPTutorialAndNavigateTo(destination: .mock)
        #expect(!eventMapperMock.didCallFireFailedToLoadPiPTutorialEvent)
        #expect(eventMapperMock.capturedError == nil)
        #expect(eventMapperMock.capturedURLPath == nil)

        await withCheckedContinuation { continuation in
            urlOpenerMock.onOpenURL = {
                continuation.resume()
            }
            // WHEN
            videoPlayerMock.send(event: .failed)
        }

        // THEN
        #expect(eventMapperMock.didCallFireFailedToLoadPiPTutorialEvent)
        #expect(eventMapperMock.capturedError as? NSError == error)
        #expect(eventMapperMock.capturedURLPath == url?.absoluteString)
    }
}
