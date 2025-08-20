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
    private let videoURL: URL
    private var mockPlayer: MockAVQueuePlayer!
    private var mockAudioSessionManager: MockAudioSessionManager!
    private var mockPictureInPictureController: MockPictureInPictureController!
    private var playerConfiguration: VideoPlayerConfiguration!

    init() throws {
        videoURL = try #require(Bundle(for: VideoPlayerCoordinatorTests.self).url(forResource: "default-browser", withExtension: "mp4"))
        mockPlayer = MockAVQueuePlayer()
        mockAudioSessionManager = MockAudioSessionManager()
        mockPictureInPictureController = MockPictureInPictureController()
    }

    @discardableResult
    func makeSUT(
        configuration: VideoPlayerConfiguration = VideoPlayerConfiguration(),
        player: MockAVQueuePlayer = MockAVQueuePlayer()
    ) -> VideoPlayerCoordinator {
        mockPlayer = player
        playerConfiguration = configuration
        return VideoPlayerCoordinator(
            configuration: playerConfiguration,
            player: mockPlayer,
            pictureInPictureController: mockPictureInPictureController,
            audioSessionManager: mockAudioSessionManager,
            scheduler: DispatchQueue.immediate.eraseToAnyScheduler()
        )
    }

    @Test("Check When URL Does Not Exist Then AVPlayerItem Status is Failed")
    func whenInitWithFakeURLThenPlayerItemIsNotAssignedToPlayer() async throws {
        // GIVEN
        let sut = makeSUT(player: mockPlayer)
        #expect(!mockPlayer.didCallReplaceCurrentItem)
        #expect(mockPlayer.capturedCurrentItem == nil)

        // WHEN
        await sut.loadAsset(url: fakeURL, shouldLoopVideo: false).value

        // THEN
        #expect(!mockPlayer.didCallReplaceCurrentItem)
        #expect(mockPlayer.capturedCurrentItem == nil)
        #expect(sut.playerItemStatus == .failed)
    }

    @Test("Check PlayerItem Is Assigned To Player When Load URL")
    func whenInitWithURLThenPlayerItemIsAssignedToPlayer() async throws {
        // GIVEN
        let sut = makeSUT(player: mockPlayer)
        #expect(!mockPlayer.didCallReplaceCurrentItem)
        #expect(mockPlayer.capturedCurrentItem == nil)

        // WHEN
        await sut.loadAsset(url: videoURL, shouldLoopVideo: false).value

        // THEN
        let asset = try #require(mockPlayer.capturedCurrentItem?.asset as? AVURLAsset)
        #expect(mockPlayer.didCallReplaceCurrentItem)
        #expect(asset.url == videoURL)
    }

    @Test(
        "Check Looping Parameter Creates Loop Video",
        arguments: [
            true,
            false
        ]
    )
    func whenIsLoopingVideoCalledAndLoopVideoIsTrueThenReturnTrue(isLooping: Bool) async {
        // GIVEN
        mockPlayer = .init()
        let sut = makeSUT(player: mockPlayer)
        await sut.loadAsset(url: videoURL, shouldLoopVideo: isLooping).value

        // WHEN
        let result = sut.isLoopingVideo

        // THEN
        #expect(result == isLooping)
    }

    @Test(
        "Check Video Player Is Configured With The Right Parameters",
        arguments: [
            VideoPlayerConfiguration(),
            VideoPlayerConfiguration(preventsDisplaySleepDuringVideoPlayback: true, allowsExternalPlayback: true)
        ]
    )
    func whenInitWithDefaultConfigurationThenVideoPlayerConfigurationIsTheOneExpected(configuration: VideoPlayerConfiguration) {
        // GIVEN
        mockPlayer = .init()

        // WHEN
        makeSUT(configuration: configuration, player: mockPlayer)

        // THEN
        #expect(mockPlayer.preventsDisplaySleepDuringVideoPlayback == configuration.preventsDisplaySleepDuringVideoPlayback)
        #expect(mockPlayer.allowsExternalPlayback == configuration.allowsExternalPlayback)
    }

    @Test("Check Play Is Called")
    func whenPlayIsCalledThenAskPlayerToPlay() {
        // GIVEN
        let sut = makeSUT()
        #expect(!mockPlayer.didCallPlay)

        // WHEN
        sut.play()

        // THEN
        #expect(mockPlayer.didCallPlay)
    }

    @Test("Check Pause Is Called")
    func whenPauseIsCalledThenAskPlayerToPause() {
        // GIVEN
        let sut = makeSUT()
        #expect(!mockPlayer.didCallPause)

        // WHEN
        sut.pause()

        // THEN
        #expect(mockPlayer.didCallPause)
    }

    @Test("Check Stop Removes Player Item")
    func whenStopIsCalledThenResetPlayerItem() {
        // GIVEN
        let sut = makeSUT()
        #expect(!mockPlayer.didCallRemoveAllItems)

        // WHEN
        sut.stop()

        // THEN
        #expect(mockPlayer.didCallRemoveAllItems)
    }

    @Test("Check Stop Resets AVPlayerItem Status")
    func whenStopIsCalledThenResetAVPlayerItemStatus() async {
        // GIVEN
        let playerItem = MockAVPlayerItem(url: fakeURL)
        mockPlayer.mockItemToReturn = playerItem
        let sut = makeSUT(player: mockPlayer)
        await sut.loadAsset(url: videoURL, shouldLoopVideo: false).value
        playerItem.mockStatus = .readyToPlay
        #expect(sut.playerItemStatus == .readyToPlay)

        // WHEN
        sut.stop()

        // THEN
        #expect(sut.playerItemStatus == .unknown)
    }

    // MARK: - Player Item Status

    @Test(
        "Check Player Item Status Is Updated When AVPlayerItem Status changes",
        arguments: [
            AVPlayerItem.Status.unknown,
            .readyToPlay,
            .failed,
        ]
    )
    func whenPlayerItemStatusIsUpdatedThenUpdatePlayerItemStatus(_ status: AVPlayerItem.Status) async {
        // GIVEN
        let playerItem = MockAVPlayerItem(url: fakeURL)
        mockPlayer.mockItemToReturn = playerItem
        let sut = makeSUT(player: mockPlayer)
        await sut.loadAsset(url: videoURL, shouldLoopVideo: false).value

        // WHEN
        playerItem.mockStatus = status

        // THEN
        #expect(sut.playerItemStatus == status)
    }

    // MARK: - Picture In Picture

    @Test("Check Is Supported Picture In Picture Value Is Returned Correctly", arguments: [true, false])
    func whenIsSupportedPictureInPictureIsCalledThenReturnCorrectValue(_ isSupported: Bool) {
        // GIVEN
        let sut = makeSUT()
        mockPictureInPictureController.supportsPictureInPicture = isSupported

        // WHEN
        let result = sut.isPictureInPictureSupported()

        // THEN
        #expect(result == isSupported)
    }

    @Test(
        "Check Audio Session Is Configured When Picture In Picture Required",
        arguments: [
            VideoPlayerConfiguration(allowsPictureInPicturePlayback: true),
            VideoPlayerConfiguration(allowsPictureInPicturePlayback: false)
        ]

    )
    func whenPictureInPictureRequiredThenConfigureAudioSession(configuration: VideoPlayerConfiguration) {
        // GIVEN
        #expect(!mockAudioSessionManager.didCallSetPlaybackSessionActive)

        // WHEN
        makeSUT(configuration: configuration)

        // THEN
        #expect(mockAudioSessionManager.didCallSetPlaybackSessionActive == configuration.allowsPictureInPicturePlayback)
    }

    @Test("Check Setup Picture In Picture Is Called")
    func whenSetupPictureInPictureIsCalledThenAskPictureInPictureControllerToSetupPictureInPicture() {
        // GIVEN
        let avPlayerLayer = AVPlayerLayer()
        #expect(!mockPictureInPictureController.didCallSetupPictureInPicture)
        #expect(mockPictureInPictureController.capturedAVPlayerLayer == nil)
        let sut = makeSUT()

        // WHEN
        sut.setupPictureInPicture(playerLayer: avPlayerLayer)

        // THEN
        #expect(mockPictureInPictureController.didCallSetupPictureInPicture)
        #expect(mockPictureInPictureController.capturedAVPlayerLayer == avPlayerLayer)
    }

    @Test("Check Stop Picture In Picture Is Called When PiP Session Is Active")
    func whenStopPictureInPictureIsCalledThenAskPictureInPictureControllerToStopPictureInPicture() {
        // GIVEN
        #expect(!mockPictureInPictureController.didCallStopPictureInPicture)
        let sut = makeSUT()
        mockPictureInPictureController.send(.didStartPictureInPicture)

        // WHEN
        sut.stopPictureInPicture()

        // THEN
        #expect(mockPictureInPictureController.didCallStopPictureInPicture)
    }

    @Test("Check Audio Session is Deactivated On Deinitialization")
    func whenDeinitThenAudioSessionIsDeactivated() {
        // GIVEN
        var sut: VideoPlayerCoordinator! = makeSUT(configuration: .init(allowsPictureInPicturePlayback: true))
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
        let sut = makeSUT(configuration: .init(allowsPictureInPicturePlayback: true))
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
