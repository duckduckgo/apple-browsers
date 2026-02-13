//
//  HomeMessageViewModelBuilderTests.swift
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
import RemoteMessaging
import UIKit
@testable import DuckDuckGo

@Suite("RMF - Home Message View Model Builder")
struct HomeMessageViewModelBuilderTests {

    @Test("When message has no imageUrl then loadRemoteImage is nil")
    func whenMessageHasNoImageUrlThenLoadRemoteImageIsNil() throws {
        let message = makeRemoteMessage(
            content: .small(titleText: "Title", descriptionText: "Description"),
            isMetricsEnabled: true
        )
        let imageLoader = MockRemoteMessagingImageLoader()
        let pixelReporter = MockRemoteMessagingPixelReporter()

        let viewModel = try #require(
            HomeMessageViewModelBuilder.build(
                for: message,
                with: nil,
                messageActionHandler: MockRemoteMessagingActionHandler(),
                imageLoader: imageLoader,
                pixelReporter: pixelReporter,
                onDidClose: { _ in },
                onDidAppear: { }
            )
        )

        #expect(viewModel.loadRemoteImage == nil)
        #expect(viewModel.preloadedImage == nil)
        #expect(!pixelReporter.didCallMeasureRemoteMessageImageLoadSuccess)
        #expect(!pixelReporter.didCallMeasureRemoteMessageImageLoadFailed)
    }

    @Test("When image is cached then preloadedImage is set")
    func whenImageCachedThenPreloadedImageIsSet() throws {
        let imageUrl = URL(string: "https://example.com/image.png")!
        let message = makeRemoteMessage(
            content: .medium(titleText: "Title", descriptionText: "Desc", placeholder: .announce, imageUrl: imageUrl),
            isMetricsEnabled: true
        )
        let expectedImage = UIImage()
        let imageLoader = MockRemoteMessagingImageLoader()
        imageLoader.cachedImageToReturn = expectedImage
        let pixelReporter = MockRemoteMessagingPixelReporter()

        let viewModel = try #require(
            HomeMessageViewModelBuilder.build(
                for: message,
                with: nil,
                messageActionHandler: MockRemoteMessagingActionHandler(),
                imageLoader: imageLoader,
                pixelReporter: pixelReporter,
                onDidClose: { _ in },
                onDidAppear: { }
            )
        )

        #expect(viewModel.preloadedImage === expectedImage)
        #expect(imageLoader.cachedImageCalledWithUrl == imageUrl)
    }

    @Test("When image is cached then success pixel is fired")
    func whenImageCachedThenSuccessPixelFired() throws {
        let imageUrl = URL(string: "https://example.com/image.png")!
        let message = makeRemoteMessage(
            content: .medium(titleText: "Title", descriptionText: "Desc", placeholder: .announce, imageUrl: imageUrl),
            isMetricsEnabled: true
        )
        let imageLoader = MockRemoteMessagingImageLoader()
        imageLoader.cachedImageToReturn = UIImage()
        let pixelReporter = MockRemoteMessagingPixelReporter()

        _ = HomeMessageViewModelBuilder.build(
            for: message,
            with: nil,
            messageActionHandler: MockRemoteMessagingActionHandler(),
            imageLoader: imageLoader,
            pixelReporter: pixelReporter,
            onDidClose: { _ in },
            onDidAppear: { }
        )

        #expect(pixelReporter.didCallMeasureRemoteMessageImageLoadSuccess)
        #expect(pixelReporter.capturedImageLoadSuccessMessage?.id == message.id)
    }

    @Test("When loadRemoteImage succeeds then success pixel is fired")
    func whenLoadRemoteImageSucceedsThenSuccessPixelFired() async throws {
        let imageUrl = URL(string: "https://example.com/image.png")!
        let message = makeRemoteMessage(
            content: .medium(titleText: "Title", descriptionText: "Desc", placeholder: .announce, imageUrl: imageUrl),
            isMetricsEnabled: true
        )
        let expectedImage = UIImage()
        let imageLoader = MockRemoteMessagingImageLoader()
        imageLoader.imageToReturn = expectedImage
        let pixelReporter = MockRemoteMessagingPixelReporter()

        let viewModel = try #require(
            HomeMessageViewModelBuilder.build(
                for: message,
                with: nil,
                messageActionHandler: MockRemoteMessagingActionHandler(),
                imageLoader: imageLoader,
                pixelReporter: pixelReporter,
                onDidClose: { _ in },
                onDidAppear: { }
            )
        )

        let loadedImage = await viewModel.loadRemoteImage?()

        #expect(loadedImage === expectedImage)
        #expect(pixelReporter.didCallMeasureRemoteMessageImageLoadSuccess)
        #expect(pixelReporter.capturedImageLoadSuccessMessage?.id == message.id)
    }

    @Test("When loadRemoteImage fails then failure pixel is fired")
    func whenLoadRemoteImageFailsThenFailurePixelFired() async throws {
        let imageUrl = URL(string: "https://example.com/image.png")!
        let message = makeRemoteMessage(
            content: .medium(titleText: "Title", descriptionText: "Desc", placeholder: .announce, imageUrl: imageUrl),
            isMetricsEnabled: true
        )
        let imageLoader = MockRemoteMessagingImageLoader()
        imageLoader.errorToThrow = RemoteMessagingImageLoadingError.invalidImageData
        let pixelReporter = MockRemoteMessagingPixelReporter()

        let viewModel = try #require(
            HomeMessageViewModelBuilder.build(
                for: message,
                with: nil,
                messageActionHandler: MockRemoteMessagingActionHandler(),
                imageLoader: imageLoader,
                pixelReporter: pixelReporter,
                onDidClose: { _ in },
                onDidAppear: { }
            )
        )

        let loadedImage = await viewModel.loadRemoteImage?()

        #expect(loadedImage == nil)
        #expect(pixelReporter.didCallMeasureRemoteMessageImageLoadFailed)
        #expect(pixelReporter.capturedImageLoadFailedMessage?.id == message.id)
    }
}

private extension HomeMessageViewModelBuilderTests {

    func makeRemoteMessage(
        id: String = "test-message",
        content: RemoteMessageModelType,
        isMetricsEnabled: Bool
    ) -> RemoteMessageModel {
        RemoteMessageModel(
            id: id,
            surfaces: .newTabPage,
            content: content,
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: isMetricsEnabled
        )
    }
}
