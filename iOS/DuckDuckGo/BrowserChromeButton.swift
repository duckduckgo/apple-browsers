//
//  BrowserChromeButton.swift
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

import UIKit
import DesignResourcesKit

class BrowserChromeButton: UIButton {

    enum ButtonType {
        case primary
        case secondary
        case tabSwitcher
    }

    var type: ButtonType {
        didSet {
            applyConfiguration()
        }
    }

    init(_ type: ButtonType = .primary) {
        self.type = type
        super.init(frame: .zero)

        applyConfiguration()
    }
    
    required init?(coder: NSCoder) {
        self.type = .primary
        super.init(coder: coder)

        applyConfiguration()
    }

    func setImage(_ image: UIImage?) {
        configuration?.image = image
    }

    func applyConfiguration() {
        let image = configuration?.image
        let defaultConfiguration = defaultConfiguration()

        configuration = defaultConfiguration

        let type = self.type

        configuration?.image = image
        configuration?.automaticallyUpdateForSelection = false
        configuration?.imageColorTransformer = .init { [weak self] _ in
            type.foregroundColor(for: self?.state ?? .normal)
        }

        configurationUpdateHandler = { button in
            var newConfiguration = button.configuration ?? defaultConfiguration

            newConfiguration.baseForegroundColor = type.foregroundColor(for: button.state)
            newConfiguration.baseBackgroundColor = type.backgroundColor(for: button.state)

            UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
                button.configuration = newConfiguration
            }.startAnimation()
        }
    }

    private func defaultConfiguration() -> UIButton.Configuration {
        switch type {
        case .primary, .secondary:
            return .omniBarDefault()
        case .tabSwitcher:
            return .tabSwitcherDefault()
        }
    }
}

private extension BrowserChromeButton.ButtonType {

    func backgroundColor(for state: UIButton.State) -> UIColor {

        switch state {
        case .highlighted:
            return UIColor(designSystemColor: .controlsFillPrimary)
        default:
            return .clear
        }
    }

    func foregroundColor(for state: UIButton.State) -> UIColor {

        switch self {
        case .primary:
            switch state {
            case .disabled:
                return UIColor(designSystemColor: .icons).withAlphaComponent(0.5)
            default:
                return UIColor(designSystemColor: .icons)
            }
        case .secondary, .tabSwitcher:
            switch state {
            case .disabled:
                return UIColor(designSystemColor: .iconsSecondary).withAlphaComponent(0.5)
            default:
                return UIColor(designSystemColor: .iconsSecondary)
            }
        }
    }
}

private extension UIButton.Configuration {
    static func omniBarDefault() -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .dynamic
        config.buttonSize = .medium
        config.titleAlignment = .center
        config.background.backgroundInsets = .init(top: 2, leading: 2, bottom: 2, trailing: 2)

        config.background.cornerRadius = 14

        return config
    }

    static func tabSwitcherDefault() -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .dynamic
        config.buttonSize = .medium
        config.titleAlignment = .center
        config.background.backgroundInsets = .init(top: 4, leading: 4, bottom: 4, trailing: 4)

        config.background.cornerRadius = 8

        return config
    }
}
