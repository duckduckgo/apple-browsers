//
//  PictureInPictureControllerTests.swift
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
import AVKit
import Combine
@testable import DuckDuckGo

// The suite will run on MainActor due to AVPlayerLayer usage.
@Suite("Video Player - Picture In Picture Controller")
struct PictureInPictureControllerTests {

    @MainActor
    struct Configuration {

        @Test(
            "Check Underlying AVPictureInPictureController Is Configured Correctly",
            arguments: [
                PictureInPictureConfiguration(),
                PictureInPictureConfiguration(canStartPictureInPictureAutomaticallyFromInline: false, requiresLinearPlayback: false)
            ]
        )
        func whenSetupPictureInPictureThenAVPictureInPictureControllerIsConfiguredCorrectly(configuration: PictureInPictureConfiguration) throws {
            // GIVEN
            let factoryMock = MockPictureInPictureControllerFactory()
            let sut = PictureInPictureController(configuration: configuration, factory: factoryMock)
            let avPictureInPictureController = try #require(factoryMock.avPictureInPictureControllerToReturn)
            #expect(avPictureInPictureController.delegate == nil)

            // WHEN
            sut.setupPictureInPicture(playerLayer: AVPlayerLayer())

            // THEN
            #expect(avPictureInPictureController.canStartPictureInPictureAutomaticallyFromInline == configuration.canStartPictureInPictureAutomaticallyFromInline)
            #expect(avPictureInPictureController.requiresLinearPlayback == configuration.requiresLinearPlayback)
            #expect(avPictureInPictureController.delegate === sut)
        }

        @Test("Check Underlying AVPictureInPictureController Is Not Configured when Factory Returns Nil Controller")
        func whenAVPictureInPictureControllerFactoryReturnsNilThenNoConfigurationOccurs() throws {
            // GIVEN
            let factoryMock = MockPictureInPictureControllerFactory()
            factoryMock.avPictureInPictureControllerToReturn = nil
            let sut = PictureInPictureController(configuration: PictureInPictureConfiguration(canStartPictureInPictureAutomaticallyFromInline: true, requiresLinearPlayback: true), factory: factoryMock)
            #expect(!sut.isAVPictureInPictureControllerInitialised)

            // WHEN
            sut.setupPictureInPicture(playerLayer: AVPlayerLayer())

            // THEN
            #expect(factoryMock.avPictureInPictureControllerToReturn == nil)
            #expect(!sut.isAVPictureInPictureControllerInitialised)
        }

    }

    @MainActor
    struct Actions {

        @Test("Check Stop Picture In Picture Asks Underlying AVPictureInPictureController To Stop")
        func whenStopPictureInPictureThenAVPictureInPictureControllerIsStopped() throws {
            // GIVEN
            let factoryMock = MockPictureInPictureControllerFactory()
            let sut = PictureInPictureController(configuration: PictureInPictureConfiguration(), factory: factoryMock)
            sut.setupPictureInPicture(playerLayer: AVPlayerLayer())
            let avPictureInPictureController = try #require(factoryMock.avPictureInPictureControllerToReturn)
            #expect(!avPictureInPictureController.didCallStopPictureInPicture)

            // WHEN
            sut.stopPictureInPicture()

            // THEN
            #expect(avPictureInPictureController.didCallStopPictureInPicture)
        }

    }

    @MainActor
    struct Events {

        @Test(
            "Check Picture In Picture Playback Events Are Published",
            arguments: [
                (
                    function: AVPictureInPictureControllerDelegate.pictureInPictureControllerWillStartPictureInPicture,
                    event: PictureInPictureEvent.willStartPictureInPicture
                ),
                (
                    function: AVPictureInPictureControllerDelegate.pictureInPictureControllerDidStartPictureInPicture,
                    event: PictureInPictureEvent.didStartPictureInPicture
                ),
                (
                    function: AVPictureInPictureControllerDelegate.pictureInPictureControllerWillStopPictureInPicture,
                    event: PictureInPictureEvent.willStopPictureInPicture
                ),
                (
                    function: AVPictureInPictureControllerDelegate.pictureInPictureControllerDidStopPictureInPicture,
                    event: PictureInPictureEvent.didStopPictureInPicture
                )
            ]
        )
        func whenPictureInPictureDelegateMethodsAreCalledThenEventsArePublished(context: (function: (any AVPictureInPictureControllerDelegate) -> ((AVPictureInPictureController) -> Void)?, event: PictureInPictureEvent)) throws {
            // GIVEN
            let factoryMock = MockPictureInPictureControllerFactory()
            let sut = PictureInPictureController(configuration: PictureInPictureConfiguration(), factory: factoryMock)
            sut.setupPictureInPicture(playerLayer: AVPlayerLayer())
            var capturedEvent: PictureInPictureEvent?
            let c = sut.pictureInPictureEventPublisher.sink { event in
                capturedEvent = event
            }
            let avPictureInPictureControllerMock = try #require(factoryMock.avPictureInPictureControllerToReturn)
            let delegateFunction = try #require(context.function(sut))
            withExtendedLifetime(c) {}
            // WHEN
            delegateFunction(avPictureInPictureControllerMock)

            // THEN
            withExtendedLifetime(c) {}
            #expect(capturedEvent == context.event)
        }

        @Test("Check Failed To Start Picture In Picture Event is Published")
        func whenPictureInPictureDelegateErrorMethodIsCalledThenErrorEventIsPublished() throws {
            let error = NSError(domain: #function, code: 0, userInfo: nil)
            let factoryMock = MockPictureInPictureControllerFactory()
            let sut = PictureInPictureController(configuration: PictureInPictureConfiguration(), factory: factoryMock)
            sut.setupPictureInPicture(playerLayer: AVPlayerLayer())
            var capturedEvent: PictureInPictureEvent?
            let c = sut.pictureInPictureEventPublisher.sink { event in
                capturedEvent = event
            }
            let avPictureInPictureControllerMock = try #require(factoryMock.avPictureInPictureControllerToReturn)

            // WHEN
            sut.pictureInPictureController(avPictureInPictureControllerMock, failedToStartPictureInPictureWithError: error)

            // THEN
            withExtendedLifetime(c) {}
            #expect(capturedEvent == .failedToStartPictureInPicture)
        }

    }
}
