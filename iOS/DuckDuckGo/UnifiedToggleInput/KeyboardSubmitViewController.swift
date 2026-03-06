//
//  KeyboardSubmitViewController.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// Floats a single circular button above the keyboard: mic when input is empty, send when text is present.
/// Installed as a full-screen child VC whose root view passes touches through to the content below it.
final class KeyboardSubmitViewController: UIViewController {

    var onMicTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?

    private var hasText = false
    private lazy var button = KeyboardCircularButton()
    private let gradientView = KeyboardGradientView()
    private let solidView = UIView()

    // MARK: - Lifecycle

    override func loadView() {
        let passthroughView = KeyboardPassthroughView()
        passthroughView.backgroundColor = .clear
        view = passthroughView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        solidView.backgroundColor = UIColor(designSystemColor: .surface).withAlphaComponent(0.8)
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        setupLayout()
        updateButtonAppearance(animated: false)
    }

    // MARK: - Public

    func updateText(_ text: String) {
        let newHasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard newHasText != hasText else { return }
        hasText = newHasText
        updateButtonAppearance(animated: true)
    }

    // MARK: - Private

    private func setupLayout() {
        [gradientView, solidView, button].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Metrics.padding),
            button.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -Metrics.padding),
            button.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),

            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.topAnchor.constraint(equalTo: button.topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            solidView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            solidView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            solidView.topAnchor.constraint(equalTo: gradientView.bottomAnchor),
            solidView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func buttonTapped() {
        hasText ? onSubmitTapped?() : onMicTapped?()
    }

    private func updateButtonAppearance(animated: Bool) {
        let icon = hasText ? DesignSystemImages.Glyphs.Size24.arrowRightSmall : DesignSystemImages.Glyphs.Size24.microphone
        let fg = hasText ? UIColor(designSystemColor: .accentContentPrimary) : UIColor(designSystemColor: .icons)
        let bg = hasText ? UIColor(designSystemColor: .accent) : UIColor(designSystemColor: .surfaceTertiary)
        let pressedBg = hasText ? UIColor(designSystemColor: .accentTertiary) : UIColor(designSystemColor: .surface)

        if animated {
            UIView.transition(with: button, duration: 0.15, options: .transitionCrossDissolve) {
                self.button.configure(icon: icon, foreground: fg, background: bg, pressedBackground: pressedBg)
            }
        } else {
            button.configure(icon: icon, foreground: fg, background: bg, pressedBackground: pressedBg)
        }
    }

    private enum Metrics {
        static let buttonSize: CGFloat = 40
        static let padding: CGFloat = 16
    }
}

// MARK: - KeyboardCircularButton

private final class KeyboardCircularButton: UIButton {

    private let secondShadowLayer = CALayer()
    private var normalBackground: UIColor?
    private var pressedBackground: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        layer.masksToBounds = false
        adjustsImageWhenHighlighted = false
        imageView?.contentMode = .scaleAspectFit

        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6

        secondShadowLayer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        secondShadowLayer.shadowOpacity = 1.0
        secondShadowLayer.shadowOffset = CGSize(width: 0, height: 16)
        secondShadowLayer.shadowRadius = 16
        secondShadowLayer.masksToBounds = false
        layer.insertSublayer(secondShadowLayer, at: 0)
    }

    func configure(icon: UIImage?, foreground: UIColor, background: UIColor, pressedBackground: UIColor) {
        normalBackground = background
        self.pressedBackground = pressedBackground
        setImage(icon, for: .normal)
        imageView?.tintColor = foreground
        backgroundColor = background
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.backgroundColor = self.isHighlighted
                    ? (self.pressedBackground ?? self.normalBackground?.withAlphaComponent(0.8))
                    : self.normalBackground
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        secondShadowLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
            secondShadowLayer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        }
    }
}

// MARK: - KeyboardGradientView

private final class KeyboardGradientView: UIView {

    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGradient()
    }

    private func setupGradient() {
        updateColors()
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    private func updateColors() {
        let surface = UIColor(designSystemColor: .surface)
        gradientLayer.colors = [
            surface.withAlphaComponent(0.0).cgColor,
            surface.withAlphaComponent(0.8).cgColor,
        ]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateColors()
        }
    }
}

// MARK: - KeyboardPassthroughView

private final class KeyboardPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }
}
