//
//  HomeMessageViewModelBuilder.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Core
import RemoteMessaging

struct HomeMessageViewModelBuilder {

    private enum Images {
        static let announcement = "RemoteMessageAnnouncement"
        static let ddgAnnouncement = "RemoteMessageDDGAnnouncement"
        static let appUpdate = "RemoteMessageAppUpdate"
        static let criticalAppUpdate = "RemoteMessageCriticalAppUpdate"
        static let macComputer = "RemoteMessageMacComputer"
    }

    static func build(for remoteMessage: RemoteMessageModel,
                      with subscriptionDataReporter: SubscriptionDataReporting?,
                      messageActionHandler: RemoteMessagingActionHandling,
                      imageLoader: RemoteMessagingImageLoading,
                      pixelReporter: RemoteMessagingPixelReporting?,
                      onDidClose: @escaping (HomeMessageViewModel.ButtonAction?) async -> Void,
                      onDidAppear: @escaping () -> Void) -> HomeMessageViewModel? {
        guard
            let content = remoteMessage.content,
            let homeSupportedMessageDisplayType = HomeSupportedMessageDisplayType(content)
        else {
            return nil
        }

        let preloadedImage: UIImage? = content.imageUrl.flatMap { imageLoader.cachedImage(for: $0) }

        if preloadedImage != nil {
            pixelReporter?.measureRemoteMessageImageLoadSuccess(remoteMessage)
        }

        let loadRemoteImage: (() async -> UIImage?)? = if preloadedImage == nil {
            content.imageUrl.map { imageUrl in
                return {
                    do {
                        let image = try await imageLoader.loadImage(from: imageUrl)
                        pixelReporter?.measureRemoteMessageImageLoadSuccess(remoteMessage)
                        return image
                    } catch is CancellationError {
                        return nil
                    } catch {
                        pixelReporter?.measureRemoteMessageImageLoadFailed(remoteMessage)
                        return nil
                    }
                }
            }
        } else {
            nil
        }

        return HomeMessageViewModel(
            messageId: remoteMessage.id,
            modelType: homeSupportedMessageDisplayType,
            messageActionHandler: messageActionHandler,
            preloadedImage: preloadedImage,
            loadRemoteImage: loadRemoteImage,
            onDidClose: onDidClose,
            onDidAppear: onDidAppear,
            onAttachAdditionalParameters: { useCase, params in
                subscriptionDataReporter?.mergeRandomizedParameters(for: useCase, with: params) ?? params
            }
        )
    }

}

extension RemoteAction {

    func actionStyle(isSecondaryAction: Bool = false) -> HomeMessageButtonViewModel.ActionStyle {
        switch self {
        case .share(let value, let title):
            return .share(value: value, title: title)

        case .appStore, .url, .urlInContext, .survey, .navigation:
            if isSecondaryAction {
                return .cancel
            }
            return .default

        case .dismiss:
            return .cancel
        }
    }

}

private extension HomeSupportedMessageDisplayType {

    init?(_ remoteType: RemoteMessageModelType) {
        switch remoteType {
        case let .small(titleText, descriptionText):
            self = .small(titleText: titleText,
                          descriptionText: descriptionText)
        case let .medium(titleText, descriptionText, placeholder, imageUrl):
            self = .medium(titleText: titleText,
                           descriptionText: descriptionText,
                           placeholder: placeholder,
                           imageUrl: imageUrl)
        case let .bigSingleAction(titleText, descriptionText, placeholder, imageUrl, primaryActionText, primaryAction):
            self = .bigSingleAction(titleText: titleText,
                                    descriptionText: descriptionText,
                                    placeholder: placeholder,
                                    imageUrl: imageUrl,
                                    primaryActionText: primaryActionText,
                                    primaryAction: primaryAction)
        case let .bigTwoAction(titleText, descriptionText, placeholder, imageUrl, primaryActionText, primaryAction, secondaryActionText, secondaryAction):
            self = .bigTwoAction(titleText: titleText,
                                 descriptionText: descriptionText,
                                 placeholder: placeholder,
                                 imageUrl: imageUrl,
                                 primaryActionText: primaryActionText,
                                 primaryAction: primaryAction,
                                 secondaryActionText: secondaryActionText,
                                 secondaryAction: secondaryAction)
        case let .promoSingleAction(titleText, descriptionText, placeholder, imageUrl, actionText, action):
            self = .promoSingleAction(titleText: titleText,
                                      descriptionText: descriptionText,
                                      placeholder: placeholder,
                                      imageUrl: imageUrl,
                                      actionText: actionText,
                                      action: action)
        case .cardsList:
            return nil
        }
    }

}
