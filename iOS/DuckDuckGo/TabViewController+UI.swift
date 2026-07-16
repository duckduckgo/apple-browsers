//
//  TabViewController+UI.swift
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
import UIKit

extension TabViewController {

    func setupErrorActionButton() {
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.baseForegroundColor = UIColor(designSystemColor: .buttonsPrimaryText)
        buttonConfiguration.baseBackgroundColor = UIColor(designSystemColor: .buttonsPrimaryDefault)
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        buttonConfiguration.background.cornerRadius = 8
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var transformed = incoming
            transformed.font = UIFont.daxButton()
            transformed.kern = -0.23
            return transformed
        }
        errorActionButton.configuration = buttonConfiguration
        errorActionButton.configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            if !button.isEnabled {
                configuration.baseForegroundColor = UIColor(designSystemColor: .buttonsPrimaryTextDisabled)
                configuration.baseBackgroundColor = UIColor(designSystemColor: .buttonsPrimaryDisabled)
            } else if button.isHighlighted {
                configuration.baseForegroundColor = UIColor(designSystemColor: .buttonsPrimaryText)
                configuration.baseBackgroundColor = UIColor(designSystemColor: .buttonsPrimaryPressed)
            } else {
                configuration.baseForegroundColor = UIColor(designSystemColor: .buttonsPrimaryText)
                configuration.baseBackgroundColor = UIColor(designSystemColor: .buttonsPrimaryDefault)
            }
            button.configuration = configuration
        }
    }

    func setupErrorReportBrokenSiteButton() {
        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.baseForegroundColor = UIColor(designSystemColor: .accentTextPrimary)
        buttonConfiguration.contentInsets = .zero
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var transformed = incoming
            transformed.font = UIFont.daxBodyRegular()
            return transformed
        }
        errorReportBrokenSiteButton.configuration = buttonConfiguration
        errorReportBrokenSiteButton.contentHorizontalAlignment = .center
        errorReportBrokenSiteButton.configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            configuration.baseForegroundColor = UIColor(designSystemColor: .accentTextPrimary).withAlphaComponent(button.isHighlighted ? 0.7 : 1)
            configuration.background.backgroundColor = .clear
            button.configuration = configuration
        }
    }

    func configureRootView() {
        class RootView: UIView { }
        let rootView = RootView()
        rootView.backgroundColor = UIColor(designSystemColor: .background)
        view = rootView

        containerStackView = UIStackView()
        containerStackView.axis = .vertical
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        final class OuterContainer: UIView { }
        outerContainer = OuterContainer()
        outerContainer.clipsToBounds = true
        outerContainer.translatesAutoresizingMaskIntoConstraints = false

        final class WebViewContainerView: UIView { }
        webViewContainer = WebViewContainerView()
        webViewContainer.translatesAutoresizingMaskIntoConstraints = false

        outerContainer.addSubview(webViewContainer)
        NSLayoutConstraint.activate([
            webViewContainer.topAnchor.constraint(equalTo: outerContainer.topAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: outerContainer.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: outerContainer.trailingAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: outerContainer.bottomAnchor)
        ])

        containerStackView.addArrangedSubview(outerContainer)
        rootView.addSubview(containerStackView)

        let safeArea = rootView.safeAreaLayoutGuide
        let isFloatingUIEnabled = FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled
        // Floating UI: top/bottom pin to the screen edges so content underflows the glass chrome (via
        // WebKit obscured insets); leading/trailing pin to the safe area so landscape respects the notch.
        let containerStackViewTop = isFloatingUIEnabled
            ? containerStackView.topAnchor.constraint(equalTo: rootView.topAnchor)
            : containerStackView.topAnchor.constraint(equalTo: safeArea.topAnchor)
        let containerStackViewLeading = isFloatingUIEnabled
            ? containerStackView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor)
            : containerStackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
        let containerStackViewTrailing = isFloatingUIEnabled
            ? containerStackView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
            : containerStackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        NSLayoutConstraint.activate([
            containerStackViewTop,
            containerStackViewLeading,
            containerStackViewTrailing,
            containerStackView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        final class PrivacyDashboardAnchorView: UIView { }
        privacyDashboardAnchor = PrivacyDashboardAnchorView()
        privacyDashboardAnchor.backgroundColor = .clear
        privacyDashboardAnchor.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(privacyDashboardAnchor)
        NSLayoutConstraint.activate([
            privacyDashboardAnchor.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: -80),
            privacyDashboardAnchor.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            privacyDashboardAnchor.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            privacyDashboardAnchor.heightAnchor.constraint(equalToConstant: 80)
        ])

        setupErrorView(in: rootView)

        final class JSAlertContainerView: UIView { }
        jsAlertContainerView = JSAlertContainerView()
        jsAlertContainerView.translatesAutoresizingMaskIntoConstraints = false
        // Hidden until a JS alert is presented. This fills rootView and sits above the web view,
        // so leaving it visible would swallow all touches/scrolls. The JSAlertView toggles this
        // container's visibility when presenting/dismissing; it starts hidden because setup is deferred.
        jsAlertContainerView.isHidden = true
        rootView.addSubview(jsAlertContainerView)
        NSLayoutConstraint.activate([
            jsAlertContainerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            jsAlertContainerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            jsAlertContainerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            jsAlertContainerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        showBarsTapGestureRecogniser = UITapGestureRecognizer(target: self, action: #selector(onBottomOfScreenTapped(_:)))
        showBarsTapGestureRecogniser.delegate = self
        rootView.addGestureRecognizer(showBarsTapGestureRecogniser)
    }

    func setupErrorView(in rootView: UIView) {
        error = UIView()
        error.translatesAutoresizingMaskIntoConstraints = false
        error.isHidden = true
        rootView.addSubview(error)

        let errorContentStack = UIStackView()
        errorContentStack.axis = .vertical
        errorContentStack.alignment = .center
        errorContentStack.spacing = 24
        errorContentStack.translatesAutoresizingMaskIntoConstraints = false
        error.addSubview(errorContentStack)

        errorInfoImage = UIImageView(image: UIImage(rebrandable: "Dax-Accident"))
        errorInfoImage.contentMode = .scaleAspectFit
        errorInfoImage.translatesAutoresizingMaskIntoConstraints = false
        errorInfoImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorInfoImage.widthAnchor.constraint(equalToConstant: 296),
            errorInfoImage.heightAnchor.constraint(equalToConstant: 188)
        ])

        let labelsStack = UIStackView()
        labelsStack.axis = .vertical
        labelsStack.alignment = .center
        labelsStack.spacing = 11
        labelsStack.translatesAutoresizingMaskIntoConstraints = false

        errorHeader = UILabel()
        errorHeader.translatesAutoresizingMaskIntoConstraints = false
        errorHeader.font = .systemFont(ofSize: 20, weight: .semibold)
        errorHeader.numberOfLines = 0
        errorHeader.textAlignment = .center
        errorHeader.text = UserText.webPageLoadErrorTitle

        errorMessage = UILabel()
        errorMessage.translatesAutoresizingMaskIntoConstraints = false
        errorMessage.font = .systemFont(ofSize: 16)
        errorMessage.numberOfLines = 0
        errorMessage.textAlignment = .center
        errorMessage.text = UserText.webPageLoadErrorMessage

        labelsStack.addArrangedSubview(errorHeader)
        labelsStack.addArrangedSubview(errorMessage)
        errorContentStack.addArrangedSubview(errorInfoImage)
        errorContentStack.addArrangedSubview(labelsStack)
        errorContentStack.addArrangedSubview(errorReportBrokenSiteButton)
        errorContentStack.addArrangedSubview(errorActionButton)
        errorContentStack.setCustomSpacing(8, after: labelsStack)
        errorContentStack.setCustomSpacing(32, after: errorReportBrokenSiteButton)

        let safeArea = rootView.safeAreaLayoutGuide
        let minHeightConstraint = error.heightAnchor.constraint(equalToConstant: 400)
        minHeightConstraint.priority = .defaultLow
        let errorActionButtonFillWidthConstraint = errorActionButton.widthAnchor.constraint(equalTo: error.widthAnchor, constant: -64)
        errorActionButtonFillWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            error.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            error.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            error.widthAnchor.constraint(equalTo: rootView.widthAnchor),
            minHeightConstraint,

            errorContentStack.centerXAnchor.constraint(equalTo: error.centerXAnchor),
            errorContentStack.centerYAnchor.constraint(equalTo: error.centerYAnchor),
            errorContentStack.leadingAnchor.constraint(equalTo: error.leadingAnchor, constant: 10),
            errorContentStack.trailingAnchor.constraint(equalTo: error.trailingAnchor, constant: -10),
            errorContentStack.topAnchor.constraint(greaterThanOrEqualTo: error.topAnchor),
            errorContentStack.bottomAnchor.constraint(lessThanOrEqualTo: error.bottomAnchor),

            labelsStack.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            errorMessage.widthAnchor.constraint(lessThanOrEqualTo: errorHeader.widthAnchor),
            errorActionButtonFillWidthConstraint,
            errorActionButton.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            errorActionButton.heightAnchor.constraint(equalToConstant: 50),
            errorActionButton.centerXAnchor.constraint(equalTo: errorContentStack.centerXAnchor),
            errorActionButton.leadingAnchor.constraint(greaterThanOrEqualTo: error.leadingAnchor, constant: 32),
            errorActionButton.trailingAnchor.constraint(lessThanOrEqualTo: error.trailingAnchor, constant: -32),
            errorReportBrokenSiteButton.centerXAnchor.constraint(equalTo: errorContentStack.centerXAnchor)
        ])
    }

    /// Lazily creates the `JSAlertView` on first use.
    ///
    /// This is deliberately not called from `viewDidLoad`: the view contains a
    /// `UIVisualEffectView`/`UIBlurEffect` whose first decode triggers a synchronous
    /// CoreMaterial recipe-bundle scan. Doing that for every tab on the cold-launch path
    /// could exhaust the scene-create CPU budget and trip the watchdog (SIGKILL 0x8BADF00D).
    /// Deferring it to the first presented JS alert keeps that work off the launch path.
    func setupJSAlertViewIfNeeded() {
        guard jsAlertView == nil else { return }

        let alertView = JSAlertView()
        jsAlertView = alertView

        alertView.translatesAutoresizingMaskIntoConstraints = false
        jsAlertContainerView.addSubview(alertView)
        NSLayoutConstraint.activate([
            alertView.topAnchor.constraint(equalTo: jsAlertContainerView.topAnchor),
            alertView.leadingAnchor.constraint(equalTo: jsAlertContainerView.leadingAnchor),
            alertView.trailingAnchor.constraint(equalTo: jsAlertContainerView.trailingAnchor),
            alertView.bottomAnchor.constraint(equalTo: jsAlertContainerView.bottomAnchor)
        ])
    }

    func makeXSafariHTTPSURL(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "x-safari-https"
        return components.url ?? url
    }
}
