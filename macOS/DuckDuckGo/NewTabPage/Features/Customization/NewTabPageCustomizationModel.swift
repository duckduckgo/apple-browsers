//
//  NewTabPageCustomizationModel.swift
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

import Combine
import Common
import Foundation
import NewTabPage
import os.log
import PixelKit
import SwiftUI
import SwiftUIExtensions

final class NewTabPageCustomizationModel: ObservableObject {

    enum Const {
        static let maximumNumberOfUserImages = 8
        static let defaultColorPickerColor = NSColor.white
    }

    struct DefaultBackgroundColorStyle {
        let lightBackgroundColor: String
        let darkBackgroundColor: String
    }

    let appearancePreferences: AppearancePreferences
    let customImagesManager: UserBackgroundImagesManaging?
    let sendPixel: (PixelKitEvent) -> Void
    let openFilePanel: () -> URL?
    let showAddImageFailedAlert: () -> Void
    let customizerOpener = NewTabPageCustomizerOpener()
    let backgroundColors: DefaultBackgroundColorStyle

    @Published private(set) var availableUserBackgroundImages: [UserBackgroundImage] = []

    private var availableCustomImagesCancellable: AnyCancellable?
    private var customBackgroundPixelCancellable: AnyCancellable?

    convenience init(visualStyleManager: VisualStyleManagerProviding, appearancePreferences: AppearancePreferences) {
        self.init(
            appearancePreferences: appearancePreferences,
            userBackgroundImagesManager: UserBackgroundImagesManager(
                maximumNumberOfImages: Const.maximumNumberOfUserImages,
                applicationSupportDirectory: URL.sandboxApplicationSupportURL
            ),
            sendPixel: { pixelEvent in
                PixelKit.fire(pixelEvent)
            },
            openFilePanel: {
                let panel = NSOpenPanel(allowedFileTypes: [.image])
                guard case .OK = panel.runModal(), let url = panel.url else {
                    return nil
                }
                return url
            },
            showAddImageFailedAlert: {
                let alert = NSAlert.cannotReadImageAlert()
                alert.runModal()
            },
            visualStyle: visualStyleManager.style
        )
    }

    init(
        appearancePreferences: AppearancePreferences,
        userBackgroundImagesManager: UserBackgroundImagesManaging?,
        sendPixel: @escaping (PixelKitEvent) -> Void,
        openFilePanel: @escaping () -> URL?,
        showAddImageFailedAlert: @escaping () -> Void,
        visualStyle: VisualStyleProviding
    ) {
        self.appearancePreferences = appearancePreferences
        self.customImagesManager = userBackgroundImagesManager

        if case .userImage = appearancePreferences.homePageCustomBackground, userBackgroundImagesManager == nil {
            customBackground = nil
        } else {
            customBackground = appearancePreferences.homePageCustomBackground
        }

        self.sendPixel = sendPixel
        self.openFilePanel = openFilePanel
        self.showAddImageFailedAlert = showAddImageFailedAlert
        self.backgroundColors = DefaultBackgroundColorStyle(lightBackgroundColor: visualStyle.colorsProvider.ntpLightBackgroundColor,
                                                            darkBackgroundColor: visualStyle.colorsProvider.ntpDarkBackgroundColor)

        subscribeToUserBackgroundImages()
        subscribeToCustomBackground()

        if let lastPickedCustomColorHexValue, let customColor = NSColor(hex: lastPickedCustomColorHexValue) {
            lastPickedCustomColor = customColor
        }
    }

    private func subscribeToUserBackgroundImages() {
        availableCustomImagesCancellable = customImagesManager?.availableImagesPublisher
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] images in
                guard case .userImage(let userBackgroundImage) = self?.customBackground, !images.contains(userBackgroundImage) else {
                    return
                }
                if let firstImage = images.first {
                    self?.customBackground = .userImage(firstImage)
                } else {
                    self?.customBackground = nil
                }
            })
            .assign(to: \.availableUserBackgroundImages, onWeaklyHeld: self)
    }

    private func subscribeToCustomBackground() {
        let customBackgroundPublisher: AnyPublisher<CustomBackground?, Never> = {
            if AppVersion.runType == .unitTests {
                return $customBackground.dropFirst().eraseToAnyPublisher()
            }
            return $customBackground.dropFirst()
                .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
                .eraseToAnyPublisher()
        }()

        customBackgroundPixelCancellable = customBackgroundPublisher
            .sink { [weak self] customBackground in
                switch customBackground {
                case .gradient:
                    self?.sendPixel(NewTabBackgroundPixel.newTabBackgroundSelectedGradient)
                case .solidColor:
                    self?.sendPixel(NewTabBackgroundPixel.newTabBackgroundSelectedSolidColor)
                case .userImage:
                    self?.sendPixel(NewTabBackgroundPixel.newTabBackgroundSelectedUserImage)
                case .none:
                    self?.sendPixel(NewTabBackgroundPixel.newTabBackgroundReset)
                }
            }
    }

    @Published var customBackground: CustomBackground? {
        didSet {
            appearancePreferences.homePageCustomBackground = customBackground
            switch customBackground {
            case .solidColor(let solidColorBackground) where solidColorBackground.predefinedColorName == nil:
                lastPickedCustomColor = solidColorBackground.color
            case .userImage(let userBackgroundImage):
                customImagesManager?.updateSelectedTimestamp(for: userBackgroundImage)
            default:
                break
            }
            if let customBackground {
                Logger.newTabPageCustomization.debug("Home page background updated: \(customBackground), color scheme: \(customBackground.colorScheme)")
            } else {
                Logger.newTabPageCustomization.debug("Home page background reset")
            }
        }
    }

    @MainActor
    func addNewImage() async {
        guard let customImagesManager, let url = openFilePanel() else {
            return
        }

        do {
            let image = try await customImagesManager.addImage(with: url)
            customBackground = .userImage(image)
            Logger.newTabPageCustomization.debug("New user image added")
        } catch {
            sendPixel(DebugEvent(NewTabBackgroundPixel.newTabBackgroundAddImageError, error: error))
            showAddImageFailedAlert()
            Logger.newTabPageCustomization.error("Failed to add user image: \(error)")
        }
    }

    @Published private(set) var lastPickedCustomColor: NSColor? {
        didSet {
            guard let lastPickedCustomColor else {
                return
            }
            lastPickedCustomColorHexValue = lastPickedCustomColor.hex()
        }
    }

    @UserDefaultsWrapper(key: .homePageLastPickedCustomColor, defaultValue: nil)
    private var lastPickedCustomColorHexValue: String?

    /**
     * This function is used from Debug Menu and shouldn't otherwise be used in the code accessible to the users.
     */
    func resetAllCustomizations() {
        customBackground = nil
        lastPickedCustomColor = nil
        lastPickedCustomColorHexValue = nil
        customImagesManager?.availableImages.forEach { image in
            customImagesManager?.deleteImage(image)
        }
    }
}
