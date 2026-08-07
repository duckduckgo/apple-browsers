//
//  JSAlertView.swift
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

import UIKit
import Core
import DesignResourcesKit

private extension UIImage {
    static let highlightedAlertButtonTint = UIImage(resource: .alertButtonHighlightedTint)
}

/// Custom UIKit component that renders JavaScript `alert`/`confirm`/`prompt` dialogs.
///
/// Replaces the previous storyboard-backed `JSAlertController`. The hosting view is expected
/// to add this view to a container that fills the tab and to keep that container hidden until
/// an alert is presented (this view toggles its `superview`'s visibility while presenting and
/// dismissing).
final class JSAlertView: UIView {

    private enum Constants {
        static let appearAnimationDuration = 0.2
        static let dismissAnimationDuration = 0.3
        static let keyboardAnimationDuration = 0.3

        static let alertWidth: CGFloat = 270
        static let alertCornerRadius: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 22
        static let buttonHeight: CGFloat = 44
        static let separatorHeight: CGFloat = 0.5
        static let alertEdgeInset: CGFloat = 16
        static let alertVerticalMargin: CGFloat = 20
        static let alertHorizontalMargin: CGFloat = 52
    }

    private let backgroundView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let alertView = UIView()
    private let messageScrollView = UIScrollView()
    private let verticalStackView = UIStackView()
    private let textFieldBox = UIView()

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let textField = UITextField()
    private let okButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let separatorViews: [UIView] = [UIView(), UIView()]

    private var scrollViewBottomConstraint: NSLayoutConstraint!

    private var alert: WebJSAlert? {
        didSet {
            reloadData()
        }
    }

    var isShown: Bool {
        alert != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        reloadData()
        alertView.alpha = 0.0
        backgroundView.alpha = 0.0
        registerForKeyboardNotifications()
        decorate()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ alert: WebJSAlert) {
        self.alert = alert

        superview?.isHidden = false
        self.alertView.alpha = 0.0
        self.alertView.transform = .init(scaleX: 1.15, y: 1.15)
        self.backgroundView.alpha = 0.0

        UIView.animate(withDuration: Constants.appearAnimationDuration, delay: 0, options: .curveEaseOut) {
            self.alertView.alpha = 1.0
            self.alertView.transform = .identity
            self.backgroundView.alpha = 1.0
        } completion: { _ in
            if !self.textFieldBox.isHidden {
                self.textField.becomeFirstResponder()
            }
            Pixel.fire(pixel: .jsAlertShown)
        }
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        if self.textField.isFirstResponder {
            self.textField.resignFirstResponder()
        }
        guard animated else {
            self.alert = nil
            superview?.isHidden = true
            completion?()
            return
        }

        UIView.animate(withDuration: Constants.dismissAnimationDuration) {
            self.backgroundView.alpha = 0.0
            self.alertView.alpha = 0.0

        } completion: { [alert = self.alert] _ in
            if self.alert === alert {
                self.alert = nil
            }
            self.superview?.isHidden = true
            completion?()

            // if another alert was requested while dismissing
            if let alert = self.alert {
                self.present(alert)
            }
        }
    }

    private func reloadData() {
        guard let alert = alert else { return }

        okButton.setTitle(UserText.webJSAlertOKButton, for: .normal)
        okButton.setBackgroundImage(.highlightedAlertButtonTint, for: .highlighted)
        cancelButton.setTitle(UserText.webJSAlertCancelButton, for: .normal)
        cancelButton.setBackgroundImage(.highlightedAlertButtonTint, for: .highlighted)
        titleLabel.text = String(format: UserText.webJSAlertWebsiteMessageFormat, alert.domain)
        messageLabel.text = alert.message

        if let text = alert.text {
            textField.placeholder = text
            textField.text = text
            textFieldBox.isHidden = false
        } else {
            textFieldBox.isHidden = true
        }

        cancelButton.isHidden = alert.isSimpleAlert
    }

    @objc private func okAction(_ sender: UIButton) {
        dismiss(animated: true) { [alert = self.alert, text = self.textField.text] in
            alert?.complete(with: true, text: text)
        }
    }

    @objc private func cancelAction(_ sender: Any) {
        dismiss(animated: true) { [alert = self.alert] in
            alert?.complete(with: false, text: nil)
        }
    }

    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidShow),
                                               name: UIResponder.keyboardDidShowNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }

    @objc private func keyboardDidShow(notification: NSNotification) {
        guard let isLocalUserInfoKey = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber,
              isLocalUserInfoKey == true,
              let intersection = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?
                  .intersection(self.convert(bounds, to: window)),
              self.scrollViewBottomConstraint.constant != -intersection.height
        else {
            return
        }

        UIView.animate(withDuration: Constants.keyboardAnimationDuration) {
            self.scrollViewBottomConstraint.constant = -intersection.height
            self.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(notification: NSNotification) {
        guard let isLocalUserInfoKey = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber,
              isLocalUserInfoKey == true,
              self.scrollViewBottomConstraint.constant != 0
        else {
            return
        }

        UIView.animate(withDuration: Constants.keyboardAnimationDuration) {
            self.scrollViewBottomConstraint.constant = 0
            self.layoutSubviews()
        }
    }

    private func decorate() {
        self.titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        self.textField.backgroundColor = UIColor(designSystemColor: .surface)
        self.messageLabel.textColor = UIColor(designSystemColor: .textPrimary)
        self.alertView.backgroundColor = UIColor(designSystemColor: .background)
        self.separatorViews.forEach { $0.backgroundColor = UIColor(designSystemColor: .lines) }
        self.okButton.setTitleColor(UIColor(designSystemColor: .buttonsSecondaryWireText), for: .normal)
        self.cancelButton.setTitleColor(UIColor(designSystemColor: .buttonsSecondaryWireText), for: .normal)
    }

}

// MARK: - View construction

private extension JSAlertView {

    // swiftlint:disable:next function_body_length
    func setupViews() {
        backgroundColor = .clear

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        addSubview(backgroundView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delaysContentTouches = false
        addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        alertView.translatesAutoresizingMaskIntoConstraints = false
        alertView.clipsToBounds = true
        alertView.layer.cornerRadius = Constants.alertCornerRadius
        contentView.addSubview(alertView)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        alertView.addSubview(blurView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        alertView.addSubview(titleLabel)

        messageScrollView.translatesAutoresizingMaskIntoConstraints = false
        alertView.addSubview(messageScrollView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageScrollView.addSubview(messageLabel)

        verticalStackView.translatesAutoresizingMaskIntoConstraints = false
        verticalStackView.axis = .vertical
        alertView.addSubview(verticalStackView)

        setupTextFieldBox()

        verticalStackView.addArrangedSubview(textFieldBox)
        verticalStackView.addArrangedSubview(separatorViews[0])
        verticalStackView.addArrangedSubview(okButton)
        verticalStackView.addArrangedSubview(separatorViews[1])
        verticalStackView.addArrangedSubview(cancelButton)

        setupButton(okButton, fontWeight: .semibold)
        okButton.addTarget(self, action: #selector(okAction(_:)), for: .touchUpInside)
        setupButton(cancelButton, fontWeight: .regular)
        cancelButton.addTarget(self, action: #selector(cancelAction(_:)), for: .touchUpInside)

        separatorViews.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        setupConstraints(blurView: blurView)
    }

    func setupTextFieldBox() {
        textFieldBox.translatesAutoresizingMaskIntoConstraints = false

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .roundedRect
        textField.font = .systemFont(ofSize: 14)
        textFieldBox.addSubview(textField)
    }

    func setupButton(_ button: UIButton, fontWeight: UIFont.Weight) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: fontWeight)
        button.layer.cornerRadius = Constants.buttonCornerRadius
    }

    // swiftlint:disable:next function_body_length
    func setupConstraints(blurView: UIVisualEffectView) {
        scrollViewBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)

        let contentHeight = contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        contentHeight.priority = .defaultHigh

        let alertCenterY = alertView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        alertCenterY.priority = UILayoutPriority(900)

        let alertWidth = alertView.widthAnchor.constraint(equalToConstant: Constants.alertWidth)
        alertWidth.priority = UILayoutPriority(990)

        let messageMaxHeight = messageScrollView.heightAnchor.constraint(
            lessThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, multiplier: 0.3)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollViewBottomConstraint,

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentHeight,

            alertView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            alertCenterY,
            alertWidth,
            alertView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor,
                                               constant: Constants.alertHorizontalMargin),
            contentView.trailingAnchor.constraint(greaterThanOrEqualTo: alertView.trailingAnchor,
                                                  constant: Constants.alertHorizontalMargin),
            alertView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor,
                                           constant: Constants.alertVerticalMargin),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: alertView.bottomAnchor,
                                                constant: Constants.alertVerticalMargin),

            blurView.topAnchor.constraint(equalTo: alertView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: alertView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: alertView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: alertView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: alertView.topAnchor, constant: Constants.alertVerticalMargin),
            titleLabel.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: Constants.alertEdgeInset),
            alertView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: Constants.alertEdgeInset),

            messageScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            messageScrollView.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: Constants.alertEdgeInset),
            alertView.trailingAnchor.constraint(equalTo: messageScrollView.trailingAnchor, constant: Constants.alertEdgeInset),
            messageMaxHeight,

            verticalStackView.topAnchor.constraint(equalTo: messageScrollView.bottomAnchor, constant: Constants.alertEdgeInset),
            verticalStackView.leadingAnchor.constraint(equalTo: alertView.leadingAnchor),
            verticalStackView.trailingAnchor.constraint(equalTo: alertView.trailingAnchor),
            verticalStackView.bottomAnchor.constraint(equalTo: alertView.bottomAnchor),

            textField.leadingAnchor.constraint(equalTo: textFieldBox.leadingAnchor, constant: Constants.alertEdgeInset),
            textFieldBox.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: Constants.alertEdgeInset),
            textFieldBox.bottomAnchor.constraint(equalTo: textField.bottomAnchor, constant: 15),
            textField.heightAnchor.constraint(equalToConstant: 26),
            textFieldBox.heightAnchor.constraint(equalToConstant: Constants.buttonHeight),

            separatorViews[0].heightAnchor.constraint(equalToConstant: Constants.separatorHeight),
            separatorViews[1].heightAnchor.constraint(equalToConstant: Constants.separatorHeight),
            okButton.heightAnchor.constraint(equalToConstant: Constants.buttonHeight),
            cancelButton.heightAnchor.constraint(equalToConstant: Constants.buttonHeight)
        ])

        setupMessageLabelConstraints()
    }

    func setupMessageLabelConstraints() {
        let height = messageLabel.heightAnchor.constraint(equalTo: messageScrollView.heightAnchor)
        height.priority = UILayoutPriority(950)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.topAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.bottomAnchor),
            messageLabel.widthAnchor.constraint(equalTo: messageScrollView.frameLayoutGuide.widthAnchor),
            messageScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            height
        ])
    }

}
