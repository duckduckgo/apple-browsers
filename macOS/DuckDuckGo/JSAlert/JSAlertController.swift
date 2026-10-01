//
//  JSAlertController.swift
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

import AppKit
import Combine
import Carbon.HIToolbox

final class JSAlertController: NSViewController {

    private enum Constants {
        static let appearAnimationDuration = 0.05
        static let dismissAnimationDuration = 0.1
        static let scrollViewToTextfieldSpacing = 8.0
        static let initialTransformScale = CATransform3DMakeScale(0.95, 0.95, 1)

        static let contentSize = CGSize(width: 600, height: 401)
        static let alertWidth: CGFloat = 460
        static let alertInset: CGFloat = 20
        static let alertBottomInset: CGFloat = 16
        static let alertMinVerticalMargin: CGFloat = 12
        static let stackSpacing: CGFloat = 32
        static let stackEdgeInset: CGFloat = 4
        static let messageMinSize = NSSize(width: 420, height: 50)
        static let messageMaxWidth: CGFloat = 444
        static let defaultScrollViewHeight: CGFloat = 32
    }

    var cancellables: Set<AnyCancellable> = []

    private(set) var scrollViewHeight: NSLayoutConstraint!
    private(set) var alertCenterYAlignment: NSLayoutConstraint!

    private(set) var backgroundView: ColorView!
    private(set) var alertView: ColorView!
    private(set) var verticalStackView: NSStackView!
    private(set) var titleTextField: NSTextField!
    private(set) var scrollView: NSScrollView!
    private(set) var messageTextView: NSTextView!
    private(set) var inputTextField: NSTextField!
    private(set) var okButton: NSButton!
    private(set) var cancelButton: NSButton!

    private let viewModel: JSAlertViewModel

    static func create(_ query: JSAlertQuery) -> JSAlertController {
        JSAlertController(query: query)
    }

    init(query: JSAlertQuery) {
        self.viewModel = JSAlertViewModel(query: query)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(type(of: self)): Bad initializer")
    }

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: Constants.contentSize))
        view.autoresizingMask = [.width, .height]

        backgroundView = ColorView(frame: .zero, backgroundColor: .alertBackgroundOverlay, interceptClickEvents: true)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        alertView = ColorView(frame: .zero, backgroundColor: .dialogPanelBackground)
        alertView.translatesAutoresizingMaskIntoConstraints = false

        titleTextField = NSTextField(labelWithString: "")
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleTextField.alignment = .left
        titleTextField.isSelectable = true
        titleTextField.setContentHuggingPriority(.init(251), for: .horizontal)
        titleTextField.setContentHuggingPriority(.init(750), for: .vertical)

        messageTextView = NSTextView()
        messageTextView.importsGraphics = false
        messageTextView.isRichText = false
        messageTextView.isVerticallyResizable = true
        messageTextView.isAutomaticSpellingCorrectionEnabled = true
        messageTextView.smartInsertDeleteEnabled = true
        messageTextView.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageTextView.textColor = .textColor
        messageTextView.backgroundColor = .clear
        messageTextView.insertionPointColor = .textColor
        messageTextView.minSize = Constants.messageMinSize
        messageTextView.maxSize = NSSize(width: Constants.messageMaxWidth, height: .greatestFiniteMagnitude)
        messageTextView.autoresizingMask = [.width, .height]

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.contentView.drawsBackground = false
        scrollView.drawsBackground = false
        scrollView.documentView = messageTextView

        inputTextField = NSTextField()
        inputTextField.translatesAutoresizingMaskIntoConstraints = false
        inputTextField.controlSize = .large
        inputTextField.font = .systemFont(ofSize: NSFont.systemFontSize)
        inputTextField.lineBreakMode = .byClipping
        inputTextField.isBezeled = true
        inputTextField.bezelStyle = .roundedBezel
        inputTextField.isEditable = true
        inputTextField.isSelectable = true
        inputTextField.cell?.sendsActionOnEndEditing = true
        (inputTextField.cell as? NSTextFieldCell)?.isScrollable = true
        inputTextField.setContentHuggingPriority(.init(750), for: .vertical)

        cancelButton = NSButton(title: "", target: self, action: #selector(cancelAction))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"

        okButton = NSButton(title: "", target: self, action: #selector(okAction))
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.bezelStyle = .rounded
        okButton.controlSize = .large
        okButton.keyEquivalent = "\r"

        let buttonsStackView = NSStackView(views: [cancelButton, okButton])
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.orientation = .horizontal
        buttonsStackView.distribution = .fillEqually
        buttonsStackView.alignment = .centerY
        buttonsStackView.setContentCompressionResistancePriority(.init(250), for: .vertical)

        verticalStackView = NSStackView(views: [titleTextField, scrollView, inputTextField, buttonsStackView])
        verticalStackView.translatesAutoresizingMaskIntoConstraints = false
        verticalStackView.orientation = .vertical
        verticalStackView.alignment = .leading
        verticalStackView.distribution = .fill
        verticalStackView.spacing = Constants.stackSpacing
        verticalStackView.detachesHiddenViews = true
        verticalStackView.edgeInsets = NSEdgeInsets(top: Constants.stackEdgeInset,
                                                    left: Constants.stackEdgeInset,
                                                    bottom: Constants.stackEdgeInset,
                                                    right: Constants.stackEdgeInset)

        alertView.addSubview(verticalStackView)
        view.addSubview(backgroundView)
        view.addSubview(alertView)

        scrollViewHeight = scrollView.heightAnchor.constraint(equalToConstant: Constants.defaultScrollViewHeight)
        scrollViewHeight.priority = .init(250)

        alertCenterYAlignment = alertView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        alertCenterYAlignment.priority = .init(250)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            alertView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            alertView.widthAnchor.constraint(equalToConstant: Constants.alertWidth),
            alertView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: Constants.alertMinVerticalMargin),
            view.bottomAnchor.constraint(greaterThanOrEqualTo: alertView.bottomAnchor, constant: Constants.alertMinVerticalMargin),
            alertCenterYAlignment,

            verticalStackView.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: Constants.alertInset),
            alertView.trailingAnchor.constraint(equalTo: verticalStackView.trailingAnchor, constant: Constants.alertInset),
            verticalStackView.topAnchor.constraint(equalTo: alertView.topAnchor, constant: Constants.alertInset),
            alertView.bottomAnchor.constraint(equalTo: verticalStackView.bottomAnchor, constant: Constants.alertBottomInset),

            buttonsStackView.widthAnchor.constraint(equalTo: verticalStackView.widthAnchor),
            scrollViewHeight,
        ])

        self.view = view
    }

    override func viewDidLoad() {
        alertView.layer?.cornerRadius = 10.0
        alertView.applyDropShadow()

        messageTextView.textContainer?.lineFragmentPadding = 0.0
        messageTextView.isEditable = false
    }

    override func viewWillAppear() {
        presentData()
    }

    override func viewDidAppear() {
        view.makeMeFirstResponder()
        // Needed to handle key presses after AddressBar resigns first responder
        NotificationCenter.default.publisher(for: MainWindow.firstResponderDidChangeNotification, object: view.window)
            .sink { [weak self] _ in
                if let firstResponder = self?.view.window?.firstResponder, firstResponder is WebView {
                    self?.view.makeMeFirstResponder()
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidDisappear() {
        // Defensive action in case of erroneous failure to deinit
        cancellables.removeAll()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            if viewModel.isCancelButtonHidden {
                cancelAction(self)
                return
            }
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let messageHeight = messageTextView.textSize.height
        scrollViewHeight.constant = messageHeight

        if messageHeight <= scrollView.frame.height {
            scrollView.verticalScrollElasticity = .none
            scrollView.hasVerticalScroller = false
        } else {
            scrollView.verticalScrollElasticity = .automatic
            scrollView.hasVerticalScroller = true
        }

        guard let windowContentView = view.window?.contentView else {
            return
        }
        let windowCenter = CGPoint(x: windowContentView.frame.midX, y: windowContentView.frame.midY)
        let windowPoint = windowContentView.convert(windowCenter, to: view)
        let viewCenter = CGPoint(x: view.frame.midX, y: view.frame.midY)
        alertCenterYAlignment.constant = viewCenter.y - windowPoint.y
    }

    @objc func okAction(_ sender: NSButton) {
        dehighlightTextField()
        viewModel.confirm(text: inputTextField.stringValue)
    }

    @objc func cancelAction(_ sender: Any?) {
        dehighlightTextField()
        viewModel.cancel()
    }

    override func cancelOperation(_ sender: Any?) {
        cancelAction(sender)
    }

    private func presentData() {
        okButton.title = viewModel.okButtonText
        cancelButton.title = viewModel.cancelButtonText
        titleTextField.stringValue = viewModel.titleText
        messageTextView.string = viewModel.messageText

        cancelButton.isHidden = viewModel.isCancelButtonHidden
        scrollView.isHidden = viewModel.isMessageScrollViewHidden
        inputTextField.isHidden = viewModel.isTextFieldHidden
        let scrollViewSpacing = viewModel.isTextFieldHidden ? verticalStackView.spacing : Constants.scrollViewToTextfieldSpacing
        verticalStackView.setCustomSpacing(scrollViewSpacing, after: scrollView)
        inputTextField.stringValue = viewModel.textFieldDefaultText
        view.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
    }

    private func dehighlightTextField() {
        view.window?.endEditing(for: nil)
        inputTextField.focusRingType = .none // prevents dodgy animation out
    }
}

extension JSAlertController: NSViewControllerPresentationAnimator {
    func animatePresentation(of _: NSViewController, from fromViewController: NSViewController) {
        fromViewController.addAndLayoutChild(self)
        backgroundView.layer?.opacity = 0.0
        alertView.layer?.transform = Constants.initialTransformScale
        alertView.layer?.opacity = 0.0

        // This delayed dispatch seems to be necessary to allow the animation to be visible. Without, the view just suddenly appears into view which is quite jarring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateIn { [weak self] in
                guard let self else { return }
                if !self.viewModel.isTextFieldHidden {
                    self.inputTextField.makeMeFirstResponder()
                }
            }
        }
    }

    func animateDismissal(of _: NSViewController, from _: NSViewController) {
        animateOut { [weak self] in
            self?.removeCompletely()
        }
    }

    private func animateIn(_ completion: @escaping () -> Void) {
        setAlertAnchorPoint()
        animate(
            transform: Animation(fromValue: Constants.initialTransformScale, toValue: CATransform3DIdentity),
            backgroundOpacity: Animation(fromValue: 0.0, toValue: 1.0),
            alertOpacity: Animation(fromValue: 0.75, toValue: 1.0),
            duration: Constants.appearAnimationDuration,
            completion: completion
        )
    }

    private func animateOut(_ completion: @escaping () -> Void) {
        animate(
            transform: Animation(fromValue: CATransform3DIdentity, toValue: Constants.initialTransformScale),
            backgroundOpacity: Animation(fromValue: 1.0, toValue: 0.0),
            alertOpacity: Animation(fromValue: 1.0, toValue: 0.0),
            duration: Constants.dismissAnimationDuration,
            completion: completion
        )
    }

    private struct Animation<Value> {
        let fromValue: Value
        let toValue: Value
    }

    private func animate(
        transform: Animation<CATransform3D>,
        backgroundOpacity: Animation<Float>,
        alertOpacity: Animation<Float>,
        duration: CFTimeInterval,
        completion: @escaping () -> Void
    ) {
        CATransaction.setCompletionBlock(completion)
        CATransaction.begin()

        alertView.layer?.transform = transform.toValue
        alertView.layer?.opacity = alertOpacity.toValue
        backgroundView.layer?.opacity = backgroundOpacity.toValue

        let scaleAnimation = CABasicAnimation(keyPath: "transform")
        scaleAnimation.fromValue = transform.fromValue
        scaleAnimation.toValue = transform.toValue

        let alertOpacity = CABasicAnimation(keyPath: "opacity")
        alertOpacity.fromValue = alertOpacity.fromValue
        alertOpacity.toValue = alertOpacity.toValue

        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.animations = [scaleAnimation, alertOpacity]

        alertView.layer?.add(group, forKey: "scaleAndOpacity")

        let backgroundOpacity = CABasicAnimation(keyPath: "opacity")
        backgroundOpacity.fromValue = backgroundOpacity.fromValue
        backgroundOpacity.toValue = backgroundOpacity.toValue

        backgroundView.layer?.add(backgroundOpacity, forKey: "opacity")

        CATransaction.commit()
    }

    /*
     Explained here: https://stackoverflow.com/a/1971723.
     Anchor point is set to the center so the scale animation appears to "zoom in"
     (similar to system alerts) and not from one corner. Because the position is relative
     to the anchorPoint of the layer, changing that anchorPoint while maintaining the same
     position moves the layer. In order to prevent this movement, you need to adjust the layer's
     position to account for the new anchorPoint.
     */
    private func setAlertAnchorPoint() {
        let anchorPoint = CGPoint(x: 0.5, y: 0.5)
        guard let alertViewLayer = alertView.layer else { return }

        let initialNewPoint = CGPoint(
            x: alertView.bounds.midX,
            y: alertView.bounds.midY
        )
        let initialOldPoint = CGPoint(
            x: alertView.bounds.size.width * alertViewLayer.anchorPoint.x,
            y: alertView.bounds.size.height * alertViewLayer.anchorPoint.y
        )

        let newPoint = initialNewPoint.applying(CATransform3DGetAffineTransform(alertViewLayer.transform))
        let oldPoint = initialOldPoint.applying(CATransform3DGetAffineTransform(alertViewLayer.transform))

        var position = alertViewLayer.position

        position.x -= oldPoint.x
        position.x += newPoint.x

        position.y -= oldPoint.y
        position.y += newPoint.y

        alertView.layer?.position = position
        alertView.layer?.anchorPoint = anchorPoint
    }
}
