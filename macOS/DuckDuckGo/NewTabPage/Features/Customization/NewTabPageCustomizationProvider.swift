//
//  NewTabPageCustomizationProvider.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import NewTabPage
import SwiftUI

final class NewTabPageCustomizationProvider: NewTabPageCustomBackgroundProviding {
    let customizationModel: NewTabPageCustomizationModel
    let appearancePreferences: AppearancePreferences

    init(customizationModel: NewTabPageCustomizationModel, appearancePreferences: AppearancePreferences = .shared) {
        self.customizationModel = customizationModel
        self.appearancePreferences = appearancePreferences
    }

    var customizerOpener: NewTabPageCustomizerOpener {
        customizationModel.customizerOpener
    }

    var customizerData: NewTabPageDataModel.CustomizerData {
        .init(
            background: .init(customizationModel.customBackground),
            theme: .init(appearancePreferences.currentThemeName),
            userColor: customizationModel.lastPickedCustomColor,
            userImages: customizationModel.availableUserBackgroundImages.map(NewTabPageDataModel.UserImage.init)
        )
    }

    var background: NewTabPageDataModel.Background {
        get {
            .init(customizationModel.customBackground)
        }
        set {
            customizationModel.customBackground = .init(newValue)
        }
    }

    var backgroundPublisher: AnyPublisher<NewTabPageDataModel.Background, Never> {
        customizationModel.$customBackground.dropFirst().removeDuplicates()
            .map(NewTabPageDataModel.Background.init)
            .eraseToAnyPublisher()
    }

    var theme: NewTabPageDataModel.Theme? {
        get {
            .init(appearancePreferences.currentThemeName)
        }
        set {
            appearancePreferences.currentThemeName = .init(newValue)
        }
    }

    var themePublisher: AnyPublisher<NewTabPageDataModel.Theme?, Never> {
        appearancePreferences.$currentThemeName.dropFirst().removeDuplicates()
            .map(NewTabPageDataModel.Theme.init)
            .eraseToAnyPublisher()
    }

    var userImagesPublisher: AnyPublisher<[NewTabPageDataModel.UserImage], Never> {
        customizationModel.$availableUserBackgroundImages.dropFirst().removeDuplicates()
            .map { $0.map(NewTabPageDataModel.UserImage.init) }
            .eraseToAnyPublisher()
    }

    @MainActor
    func presentUploadDialog() async {
        await customizationModel.addNewImage()
    }

    func deleteImage(with imageID: String) async {
        guard let image = customizationModel.availableUserBackgroundImages.first(where: { $0.id == imageID }) else {
            return
        }
        customizationModel.customImagesManager?.deleteImage(image)
    }

    @MainActor
    func showContextMenu(for imageID: String, using presenter: any NewTabPageContextMenuPresenting) async {
        let menu = NSMenu()

        menu.buildItems {
            NSMenuItem(title: UserText.deleteBackground, action: #selector(deleteBackground(_:)), target: self, representedObject: imageID)
                .withAccessibilityIdentifier("HomePage.Views.deleteBackground")
        }

        presenter.showContextMenu(menu)
    }

    @objc public func deleteBackground(_ sender: NSMenuItem) {
        Task {
            guard let imageID = sender.representedObject as? String else { return }
            await deleteImage(with: imageID)
        }
    }
}

extension NewTabPageDataModel.Background {
    init(_ customBackground: CustomBackground?) {
        switch customBackground {
        case .gradient(let gradient):
            self = .gradient(gradient.rawValue)
        case .solidColor(let solidColor):
            if let predefinedColorName = solidColor.predefinedColorName {
                self = .solidColor(predefinedColorName)
            } else {
                self = .hexColor(solidColor.description)
            }
        case .userImage(let userBackgroundImage):
            self = .userImage(.init(userBackgroundImage))
        case .none:
            self = .default
        }
    }
}

extension CustomBackground {
    init?(_ background: NewTabPageDataModel.Background) {
        switch background {
        case .default:
            return nil
        case .solidColor(let color), .hexColor(let color):
            guard let solidColor = SolidColorBackground(color) else {
                return nil
            }
            self = .solidColor(solidColor)
        case .gradient(let gradient):
            guard let gradient = GradientBackground(rawValue: gradient) else {
                return nil
            }
            self = .gradient(gradient)
        case .userImage(let userImage):
            self = .userImage(.init(fileName: userImage.id, colorScheme: .init(userImage.colorScheme)))
        }
    }
}

extension NewTabPageDataModel.UserImage {
    init(_ userBackgroundImage: UserBackgroundImage) {
        self.init(
            colorScheme: .init(userBackgroundImage.colorScheme),
            id: userBackgroundImage.id,
            src: "/background/images/\(userBackgroundImage.fileName)",
            thumb: "/background/thumbnails/\(userBackgroundImage.fileName)"
        )
    }
}

extension ColorScheme {
    init(_ theme: NewTabPageDataModel.Theme) {
        switch theme {
        case .dark:
            self = .dark
        case .light:
            self = .light
        }
    }
}

extension ThemeName {
    init(_ theme: NewTabPageDataModel.Theme?) {
        switch theme {
        case .dark:
            self = .dark
        case .light:
            self = .light
        default:
            self = .systemDefault
        }
    }
}

extension NewTabPageDataModel.Theme {
    init(_ colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            self = .dark
        case .light:
            self = .light
        @unknown default:
            self = .light
        }
    }

    init?(_ themeName: ThemeName) {
        switch themeName {
        case .light:
            self = .light
        case .dark:
            self = .dark
        case .systemDefault:
            return nil
        }
    }
}
