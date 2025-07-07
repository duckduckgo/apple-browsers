//
//  VideoPlayerCoordinatorTests.swift
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
import AVFoundation
@testable import DuckDuckGo

@MainActor
@Suite("Video Player - Coordinator")
final class VideoPlayerCoordinatorTests {
    private let fakeURL = URL(string: "https://duckduckgo.com")!
    private var mockPlayer: MockAVQueuePlayer!
    private var mockAudioSessionManager: MockAudioSessionManager!
    private var mockPictureInPictureController: MockPictureInPictureController!
    private var playerConfiguration: VideoPlayerConfiguration!

    init() {
        mockPlayer = MockAVQueuePlayer()
        mockAudioSessionManager = MockAudioSessionManager()
        mockPictureInPictureController = MockPictureInPictureController()
    }

    @discardableResult
    func makeSUT(
        url: URL,
        configuration: VideoPlayerConfiguration = .init(loopVideo: false),
        player: MockAVQueuePlayer = MockAVQueuePlayer()
    ) -> VideoPlayerCoordinator {
        mockPlayer = player
        playerConfiguration = configuration
        return VideoPlayerCoordinator(
            url: url,
            configuration: playerConfiguration,
            player: mockPlayer,
            pictureInPictureController: mockPictureInPictureController,
            audioSessionManager: mockAudioSessionManager
        )
    }

    @Test("Check PlayerItem Is Assigned To Player When Init With URL")
    func whenInitWithURLThenPlayerItemIsAssignedToPlayer() throws {
        // GIVEN
        #expect(!mockPlayer.didCallReplaceCurrentItem)
        #expect(mockPlayer.capturedCurrentItem == nil)

        // WHEN
        makeSUT(url: fakeURL, configuration: .init(loopVideo: true), player: mockPlayer)

        // THEN
        let asset = try #require(mockPlayer.capturedCurrentItem?.asset as? AVURLAsset)
        #expect(mockPlayer.didCallReplaceCurrentItem)
        #expect(asset.url == fakeURL)
    }

    @Test(
        "Check Looping Parameter Creates Loop Video",
        arguments: [
            true,
            false
        ]
    )
    func whenIsLoopingVideoCalledAndLoopVideoIsTrueThenReturnTrue(isLooping: Bool) {
        // GIVEN
        mockPlayer = .init()
        let sut = makeSUT(url: fakeURL, configuration: .init(loopVideo: isLooping), player: mockPlayer)

        // WHEN
        let result = sut.isLoopingVideo

        // THEN
        #expect(result == isLooping)
    }

    @Test(
        "Check Video Player Is Configured With The Right Parameters",
        arguments: [
            VideoPlayerConfiguration(loopVideo: false),
            VideoPlayerConfiguration(loopVideo: false, preventsDisplaySleepDuringVideoPlayback: true, allowsExternalPlayback: true)
        ]
    )
    func whenInitWithDefaultConfigurationThenVideoPlayerConfigurationIsTheOneExpected(configuration: VideoPlayerConfiguration) {
        // GIVEN
        mockPlayer = .init()

        // WHEN
        makeSUT(url: fakeURL, configuration: configuration, player: mockPlayer)

        // THEN
        #expect(mockPlayer.preventsDisplaySleepDuringVideoPlayback == configuration.preventsDisplaySleepDuringVideoPlayback)
        #expect(mockPlayer.allowsExternalPlayback == configuration.allowsExternalPlayback)
    }

    @Test("Check Play Is Called")
    func whenPlayIsCalledThenAskPlayerToPlay() {
        // GIVEN
        #expect(!mockPlayer.didCallPlay)
        let sut = makeSUT(url: fakeURL)

        // WHEN
        sut.play()

        // THEN
        #expect(mockPlayer.didCallPlay)
    }

    @Test("Check Pause Is Called")
    func whenPauseIsCalledThenAskPlayerToPause() {
        // GIVEN
        #expect(!mockPlayer.didCallPause)
        let sut = makeSUT(url: fakeURL)

        // WHEN
        sut.pause()

        // THEN
        #expect(mockPlayer.didCallPause)
    }

    // MARK: - Picture In Picture

    @Test(
        "Check Audio Session Is Configured When Picture In Picture Required",
        arguments: [
            VideoPlayerConfiguration(loopVideo: false, allowsPictureInPicturePlayback: true),
            VideoPlayerConfiguration(loopVideo: false, allowsPictureInPicturePlayback: false)
        ]

    )
    func whenPictureInPictureRequiredThenConfigureAudioSession(configuration: VideoPlayerConfiguration) {
        // GIVEN
        #expect(!mockAudioSessionManager.didCallSetPlaybackSessionActive)

        // WHEN
        makeSUT(url: fakeURL, configuration: configuration)

        // THEN
        #expect(mockAudioSessionManager.didCallSetPlaybackSessionActive == configuration.allowsPictureInPicturePlayback)
    }

    @Test("Check Setup Picture In Picture Is Called")
    func whenSetupPictureInPictureIsCalledThenAskPictureInPictureControllerToSetupPictureInPicture() {
        // GIVEN
        let avPlayerLayer = AVPlayerLayer()
        #expect(!mockPictureInPictureController.didCallSetupPictureInPicture)
        #expect(mockPictureInPictureController.capturedAVPlayerLayer == nil)
        let sut = makeSUT(url: fakeURL)

        // WHEN
        sut.setupPictureInPicture(playerLayer: avPlayerLayer)

        // THEN
        #expect(mockPictureInPictureController.didCallSetupPictureInPicture)
        #expect(mockPictureInPictureController.capturedAVPlayerLayer == avPlayerLayer)
    }

    @Test("Check Stop Picture In Picture Is Called")
    func whenStopPictureInPictureIsCalledThenAskPictureInPictureControllerToStopPictureInPicture() {
        // GIVEN
        #expect(!mockPictureInPictureController.didCallStopPictureInPicture)
        let sut = makeSUT(url: fakeURL)

        // WHEN
        sut.stopPictureInPicture()

        // THEN
        #expect(mockPictureInPictureController.didCallStopPictureInPicture)
    }

    @Test("Check Audio Session is Deactivated On Deinitialization")
    func whenDeinitThenAudioSessionIsDeactivated() {
        // GIVEN
        var sut: VideoPlayerCoordinator! = makeSUT(url: fakeURL, configuration: .init(loopVideo: false, allowsPictureInPicturePlayback: true))
        #expect(!mockAudioSessionManager.didCallSetPlaybackSessionInactive)

        // WHEN
        sut = nil

        // THEN
        #expect(sut == nil)
        #expect(mockAudioSessionManager.didCallSetPlaybackSessionInactive)
    }

    @Test(
        "Check Picture In Picture Is Active Event Is Published when Picture In Picture Starts",
        arguments: [
            (PictureInPictureEvent.didStartPictureInPicture, true),
            (.didStopPictureInPicture, false),
            (.failedToStartPictureInPicture, false)
        ]
    )
    func whenPictureInPictureStartsThenPictureInPictureIsActiveEventIsPublished(context: (event: PictureInPictureEvent, expectedResult: Bool)) {
        // GIVEN
        let sut = makeSUT(url: fakeURL, configuration: .init(loopVideo: false, allowsPictureInPicturePlayback: true))
        var capturedIsActive: Bool = false
        let c = sut.$isPictureInPictureActive
            .sink { isActive in
                capturedIsActive = isActive
            }

        // WHEN
        mockPictureInPictureController.send(context.event)

        // THEN
        withExtendedLifetime(c){}
        #expect(capturedIsActive == context.expectedResult)
    }
}
