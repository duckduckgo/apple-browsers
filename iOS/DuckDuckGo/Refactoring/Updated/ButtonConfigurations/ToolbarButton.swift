//
//  ToolbarButton.swift
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

class ToolbarButton: UIButton {

    enum ButtonType {
        case primary
        case secondary
    }

    let type: ButtonType

    init(_ type: ButtonType = .primary) {
        self.type = type
        super.init(frame: .zero)

        applyConfiguration()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage?) {
        configuration?.image = image
    }

    func applyConfiguration() {
        configuration = .omniBarDefault()

        let type = self.type

        configuration?.automaticallyUpdateForSelection = false
        configuration?.imageColorTransformer = .init { [weak self] _ in
            type.foregroundColor(for: self?.state ?? .normal)
        }

        configurationUpdateHandler = { button in

            var newConfiguration = button.configuration ?? .omniBarDefault()

            newConfiguration.baseForegroundColor = type.foregroundColor(for: button.state)
            newConfiguration.baseBackgroundColor = type.backgroundColor(for: button.state)

            UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
                button.configuration = newConfiguration
            }.startAnimation()
        }
    }
}

private extension ToolbarButton.ButtonType {

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
        case .secondary:
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
}
