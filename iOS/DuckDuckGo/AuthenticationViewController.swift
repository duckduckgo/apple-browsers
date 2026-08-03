//
//  AuthenticationViewController.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import DesignResourcesKitIcons
import DesignResourcesKit

protocol AuthenticationViewControllerDelegate: AnyObject {

    func authenticationViewController(authenticationViewController: AuthenticationViewController, didTapWithSender sender: Any)

}

class AuthenticationViewController: UIViewController {

    private enum Constants {
        static let unlockInstructionsNumberOfLines = 0
        static let unlockInstructionsFontSize: CGFloat = 18
        static let logoTopPadding: CGFloat = 48
        static let unlockInstructionsHeight: CGFloat = 135
        static let unlockInstructionsBottomOffset: CGFloat = -59
        static let unlockImageSize: CGFloat = 56
        static let unlockInstructionsLabelWidthOffset: CGFloat = -40
        static let unlockInstructionsLabelTopPadding: CGFloat = 21
        static let unlockInstructionsLabelBottomOffset: CGFloat = -20
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.shared.currentTheme.statusBarStyle
    }

    private let logo: UIImageView = {
        let imageView = UIImageView(image: UIImage(rebrandable: "LogoText"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let unlockInstructions = UIView()

    weak var delegate: AuthenticationViewControllerDelegate?

    override func loadView() {
        view = UIView()
        setupView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hideUnlockInstructions()
        decorate()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    @objc func onTap(_ sender: Any) {
        delegate?.authenticationViewController(authenticationViewController: self, didTapWithSender: sender)
    }
    
    func hideUnlockInstructions() {
        unlockInstructions.isHidden = true
    }

    func showUnlockInstructions() {
        unlockInstructions.isHidden = false
    }
}

extension AuthenticationViewController {

    private func setupView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        view.addSubview(logo)

        unlockInstructions.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(unlockInstructions)

        let unlockImageView = UIImageView(image: UIImage(named: "AuthRequired"))
        unlockImageView.translatesAutoresizingMaskIntoConstraints = false
        unlockInstructions.addSubview(unlockImageView)

        let unlockInstructionsLabel = UILabel()
        unlockInstructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        unlockInstructionsLabel.text = UserText.appUnlockInstructions
        unlockInstructionsLabel.textAlignment = .center
        unlockInstructionsLabel.numberOfLines = Constants.unlockInstructionsNumberOfLines
        unlockInstructionsLabel.font = .systemFont(ofSize: Constants.unlockInstructionsFontSize)
        unlockInstructionsLabel.textColor = UIColor(designSystemColor: .accentPrimary)
        unlockInstructions.addSubview(unlockInstructionsLabel)

        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logo.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.logoTopPadding),

            unlockInstructions.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unlockInstructions.widthAnchor.constraint(equalTo: view.widthAnchor),
            unlockInstructions.heightAnchor.constraint(equalToConstant: Constants.unlockInstructionsHeight),
            unlockInstructions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: Constants.unlockInstructionsBottomOffset),

            unlockImageView.centerXAnchor.constraint(equalTo: unlockInstructions.centerXAnchor),
            unlockImageView.widthAnchor.constraint(equalToConstant: Constants.unlockImageSize),
            unlockImageView.heightAnchor.constraint(equalToConstant: Constants.unlockImageSize),

            unlockInstructionsLabel.centerXAnchor.constraint(equalTo: unlockInstructions.centerXAnchor),
            unlockInstructionsLabel.widthAnchor.constraint(equalTo: unlockInstructions.widthAnchor, constant: Constants.unlockInstructionsLabelWidthOffset),
            unlockInstructionsLabel.topAnchor.constraint(equalTo: unlockImageView.bottomAnchor, constant: Constants.unlockInstructionsLabelTopPadding),
            unlockInstructionsLabel.bottomAnchor.constraint(equalTo: unlockInstructions.bottomAnchor,
                                                           constant: Constants.unlockInstructionsLabelBottomOffset)
        ])
    }

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.backgroundColor
    }
}
