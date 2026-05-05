//
//  BrowsingMenuViewController.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

enum BrowsingMenuEntry {

    var tag: BrowsingMenuModel.Entry.Tag? {
        switch self {
        case .regular(_, _, _, _, _, _, _, let tag, _):
            return tag
        default: return nil
        }
    }

    case regular(name: String, accessibilityLabel: String? = nil, image: UIImage, showNotificationDot: Bool = false, customDotColor: UIColor? = nil, detailText: String? = nil, detailBadge: String? = nil, tag: BrowsingMenuModel.Entry.Tag? = nil, action: () -> Void)

    case separator
}

final class BrowsingMenuViewController: UIViewController {
    
    private enum Contants {
        static let arrowLayerKey = "arrowLayer"
        static let entryCellReuseIdentifier = "BrowsingMenuEntryViewCell"
        static let separatorCellReuseIdentifier = "BrowsingMenuSeparatorViewCell"
    }
    
    typealias DismissHandler = () -> Void
    
    private let backgroundTapButton = UIButton(type: .custom)
    let menuView = UIView()
    private let arrowView = UIView()
    private let verticalStackView = UIStackView()
    private let horizontalContainer = UIView()
    private let horizontalStackView = UIStackView()
    private let separator = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)

    // Height to accomodate all content, can be constrained by parent view.
    private var tableViewHeight: NSLayoutConstraint!
    private var flexibleWidthConstraint: NSLayoutConstraint!
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var rightConstraint: NSLayoutConstraint!
    private var topConstraintIPad: NSLayoutConstraint!
    private var bottomConstraintIPad: NSLayoutConstraint!
    private var preferredWidth: NSLayoutConstraint!
    private var separatorHeight: NSLayoutConstraint!

    // Width to accomodate all entries as a single line of text, can be constrained by parent view.
    private let animator = BrowsingMenuAnimator()

    private var headerButtons: [BrowsingMenuButton] = []
    private let headerEntries: [BrowsingMenuEntry]
    private let menuEntries: [BrowsingMenuEntry]
    private let daxDialogsManager: DaxDialogsManaging
    private let appSettings: AppSettings
    private let productSurfaceTelemetry: ProductSurfaceTelemetry
    private var wasActionSelected: Bool = false

    var onDismiss: ((_ wasActionSelected: Bool) -> Void)?

    var isUsingSingleBar: Bool = false

    class func instantiate(headerEntries: [BrowsingMenuEntry], menuEntries: [BrowsingMenuEntry], daxDialogsManager: DaxDialogsManaging, appSettings: AppSettings = AppDependencyProvider.shared.appSettings, productSurfaceTelemetry: ProductSurfaceTelemetry) -> BrowsingMenuViewController {
        BrowsingMenuViewController(headerEntries: headerEntries,
                                   menuEntries: menuEntries,
                                   daxDialogsManager: daxDialogsManager,
                                   appSettings: appSettings,
                                   productSurfaceTelemetry: productSurfaceTelemetry)
    }

    init(headerEntries: [BrowsingMenuEntry], menuEntries: [BrowsingMenuEntry], daxDialogsManager: DaxDialogsManaging, appSettings: AppSettings, productSurfaceTelemetry: ProductSurfaceTelemetry) {
        self.headerEntries = headerEntries
        self.menuEntries = menuEntries
        self.daxDialogsManager = daxDialogsManager
        self.appSettings = appSettings
        self.productSurfaceTelemetry = productSurfaceTelemetry
        super.init(nibName: nil, bundle: nil)
        self.transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupHierarchy()
        setupConstraints()
        setupTableView()

        configureHeader()

        decorate()
    }

    private func setupViews() {
        view.backgroundColor = .clear

        backgroundTapButton.translatesAutoresizingMaskIntoConstraints = false
        backgroundTapButton.accessibilityIdentifier = "browsingMenuBackground"
        backgroundTapButton.tintColor = .clear
        backgroundTapButton.addTarget(self, action: #selector(backgroundTapped(_:)), for: .touchUpInside)

        menuView.translatesAutoresizingMaskIntoConstraints = false
        menuView.insetsLayoutMarginsFromSafeArea = false

        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.backgroundColor = .systemBackground

        verticalStackView.translatesAutoresizingMaskIntoConstraints = false
        verticalStackView.axis = .vertical

        horizontalContainer.translatesAutoresizingMaskIntoConstraints = false
        horizontalContainer.backgroundColor = .systemBackground

        horizontalStackView.translatesAutoresizingMaskIntoConstraints = false
        horizontalStackView.clipsToBounds = true
        horizontalStackView.spacing = 12
        horizontalStackView.insetsLayoutMarginsFromSafeArea = false

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.insetsLayoutMarginsFromSafeArea = false
        tableView.alwaysBounceVertical = true
        tableView.separatorStyle = .none
        tableView.sectionHeaderHeight = 1
        tableView.sectionFooterHeight = 1
        tableView.backgroundColor = .systemBackground
        if #available(iOS 11.0, *) {
            tableView.contentInsetAdjustmentBehavior = .never
        }
    }

    private func setupHierarchy() {
        view.addSubview(backgroundTapButton)
        view.addSubview(menuView)

        menuView.addSubview(arrowView)
        menuView.addSubview(verticalStackView)

        verticalStackView.addArrangedSubview(horizontalContainer)
        verticalStackView.addArrangedSubview(separator)
        verticalStackView.addArrangedSubview(tableView)

        horizontalContainer.addSubview(horizontalStackView)
    }

    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide

        separatorHeight = separator.heightAnchor.constraint(equalToConstant: 1)
        tableViewHeight = tableView.heightAnchor.constraint(equalToConstant: 1000)
        tableViewHeight.priority = .defaultHigh

        preferredWidth = menuView.widthAnchor.constraint(equalToConstant: 280)
        preferredWidth.priority = .defaultHigh

        let horizontalContainerPreferredHeight = horizontalContainer.heightAnchor.constraint(equalToConstant: 85)
        horizontalContainerPreferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backgroundTapButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundTapButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundTapButton.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundTapButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            menuView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor),

            verticalStackView.leadingAnchor.constraint(equalTo: menuView.leadingAnchor),
            verticalStackView.trailingAnchor.constraint(equalTo: menuView.trailingAnchor),
            verticalStackView.topAnchor.constraint(equalTo: menuView.topAnchor),
            menuView.bottomAnchor.constraint(equalTo: verticalStackView.bottomAnchor),

            horizontalStackView.topAnchor.constraint(equalTo: horizontalContainer.topAnchor),
            horizontalContainer.layoutMarginsGuide.trailingAnchor.constraint(equalTo: horizontalStackView.trailingAnchor),
            horizontalContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 85),
            horizontalContainer.bottomAnchor.constraint(equalTo: horizontalStackView.bottomAnchor),
            horizontalStackView.leadingAnchor.constraint(equalTo: horizontalContainer.layoutMarginsGuide.leadingAnchor),
            horizontalContainerPreferredHeight,

            horizontalContainer.widthAnchor.constraint(equalTo: separator.widthAnchor),

            arrowView.widthAnchor.constraint(equalToConstant: 15),
            arrowView.heightAnchor.constraint(equalToConstant: 30),
            arrowView.leadingAnchor.constraint(equalTo: verticalStackView.trailingAnchor),
            arrowView.leadingAnchor.constraint(equalTo: menuView.trailingAnchor),
            arrowView.topAnchor.constraint(equalTo: menuView.topAnchor, constant: 21),

            separatorHeight,
            tableViewHeight,
            preferredWidth
        ])

        flexibleWidthConstraint = menuView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30)
        flexibleWidthConstraint.priority = UILayoutPriority(950)
        topConstraint = menuView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor)
        bottomConstraint = view.bottomAnchor.constraint(equalTo: menuView.bottomAnchor, constant: -10)
        rightConstraint = safeArea.trailingAnchor.constraint(equalTo: menuView.trailingAnchor)
        topConstraintIPad = menuView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 27)
        bottomConstraintIPad = view.bottomAnchor.constraint(greaterThanOrEqualTo: menuView.bottomAnchor)
        topConstraintIPad.isActive = false
        bottomConstraintIPad.isActive = false

        NSLayoutConstraint.activate([
            flexibleWidthConstraint,
            topConstraint,
            bottomConstraint,
            rightConstraint
        ])
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(BrowsingMenuEntryViewCell.self, forCellReuseIdentifier: Contants.entryCellReuseIdentifier)
        tableView.register(BrowsingMenuSeparatorViewCell.self, forCellReuseIdentifier: Contants.separatorCellReuseIdentifier)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        productSurfaceTelemetry.menuUsed()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            onDismiss?(wasActionSelected)
        }
    }

    private func configureHeader() {
        horizontalContainer.isHidden = headerEntries.isEmpty
        separator.isHidden = headerEntries.isEmpty

        for entry in headerEntries {
            let button = BrowsingMenuButton.make()
            button.configure(with: entry) { [weak self] completion in
                self?.wasActionSelected = true
                self?.dismiss(animated: true, completion: completion)
            }

            horizontalStackView.addArrangedSubview(button)
            button.heightAnchor.constraint(equalTo: horizontalStackView.heightAnchor, multiplier: 1.0).isActive = true
            headerButtons.last?.widthAnchor.constraint(equalTo: button.widthAnchor, multiplier: 1.0).isActive = true

            headerButtons.append(button)
        }

        separatorHeight.constant = 1.0 / UIScreen.main.scale
    }

    private func configureArrow(with color: UIColor) {
        guard isUsingSingleBar else {
            arrowView.isHidden = true
            return
        }
        arrowView.isHidden = false
        arrowView.backgroundColor = .clear
        
        arrowView.layer.sublayers?.first { $0.name == Contants.arrowLayerKey }?.removeFromSuperlayer()
        
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        let bezierPath = UIBezierPath(roundedRect: bounds,
                                      byRoundingCorners: .allCorners,
                                      cornerRadii: CGSize(width: 3, height: 3))

        let shape = CAShapeLayer()
        shape.bounds = bounds
        shape.position = CGPoint(x: -2, y: 19)
        shape.path = bezierPath.cgPath
        shape.fillColor = color.cgColor
        shape.name = Contants.arrowLayerKey
        
        shape.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat.pi / 4))

        arrowView.layer.addSublayer(shape)
    }
    
    private func configureShadow(for theme: Theme) {
        horizontalContainer.clipsToBounds = true
        horizontalContainer.layer.cornerRadius = 10
        tableView.layer.cornerRadius = 10

        Self.applyShadowTo(view: menuView, for: theme)
    }

    class func applyShadowTo(view: UIView, for theme: Theme) {
        view.layer.cornerRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius = 20

        switch view.traitCollection.userInterfaceStyle {
        case .dark:
            view.layer.shadowOpacity = 0.5
        default:
            view.layer.shadowOpacity = 0.25
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        recalculatePreferredWidthConstraint()
        recalculateHeightConstraints()
        guideView.map(recalculateMenuConstraints(with:))

        if tableView.bounds.height < tableView.contentSize.height + tableView.contentInset.top + tableView.contentInset.bottom {
            tableView.isScrollEnabled = true
        } else {
            tableView.isScrollEnabled = false
        }
    }

    private weak var guideView: UIView?
    private var guideViewFrameObserver: NSKeyValueObservation?
    func bindConstraints(to guideView: UIView?) {
        self.guideView = guideView
        self.guideViewFrameObserver = guideView?.observe(\.frame, options: [.initial]) { [weak self] guideView, _ in
            self?.recalculateMenuConstraints(with: guideView)
        }
    }

    @objc func backgroundTapped(_ sender: Any) {
        if !daxDialogsManager.shouldShowFireButtonPulse {
            ViewHighlighter.hideAll()
        }
        dismiss(animated: true)
    }

    func highlightAddFavorite() {
        guard let index = menuEntries.firstIndex(where: { $0.tag == .favorite }) else { return }
        highlightCell(atIndex: IndexPath(row: index, section: 0))
    }

    func highlightFireButton() {
        guard let index = menuEntries.firstIndex(where: { $0.tag == .fire }) else { return }
        highlightCell(atIndex: IndexPath(row: index, section: 0))
    }

    private func highlightCell(atIndex index: IndexPath) {
        guard let cell = tableView.cellForRow(at: index) as? BrowsingMenuEntryViewCell,
              let window = view.window else {
            return
        }

        ViewHighlighter.showIn(window, focussedOnView: cell.entryImage)
    }

    func flashScrollIndicatorsIfNeeded() {
        if tableView.bounds.height < tableView.contentSize.height {
            tableView.flashScrollIndicators()
        }
    }

    private func recalculateMenuConstraints(with guideView: UIView) {
        guard let frame = guideView.superview?.convert(guideView.frame, to: guideView.window),
              let windowBounds = guideView.window?.bounds
        else { return }

        let isIPhoneLandscape = traitCollection.containsTraits(in: UITraitCollection(verticalSizeClass: .compact))

        topConstraint.isActive = !isUsingSingleBar
        topConstraintIPad.isActive = isUsingSingleBar
        bottomConstraint.isActive = !isUsingSingleBar
        bottomConstraintIPad.isActive = isUsingSingleBar

        // Make it go above WebView in Landscape
        topConstraint.constant = (isIPhoneLandscape ? 10 : 0)
        // Move menu up in Landscape, as bottom toolbar shrinks

        bottomConstraint.constant = windowBounds.maxY - frame.maxY - (isIPhoneLandscape ? 2 : 10)
        rightConstraint.constant = isUsingSingleBar ? 67 : 10

        recalculatePreferredWidthConstraint()
    }

    private func recalculatePreferredWidthConstraint() {
        let longestEntry = menuEntries.reduce("") { (result, entry) -> String in
            guard case BrowsingMenuEntry.regular(let name, _, _, _, _, _, _, _, _) = entry else { return result }
            if result.length() < name.length() {
                return name
            }
            return result
        }

        preferredWidth.constant = BrowsingMenuEntryViewCell.preferredWidth(for: longestEntry)
    }

    private func recalculateHeightConstraints() {
        tableView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        tableView.reloadData()

        // Layout the table view so the contentSize is known
        tableView.layoutIfNeeded()
        tableViewHeight.constant = tableView.contentSize.height + tableView.contentInset.bottom + tableView.contentInset.top

        // Layout the view so the tableViewHeight is applied properly (e.g. before transition)
        view.layoutIfNeeded()
    }
}

extension BrowsingMenuViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch menuEntries[indexPath.row] {
        case .separator:
            return 20
        case .regular:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        switch menuEntries[indexPath.row] {
        case .regular(_, _, _, _, _, _, _, _, let action):
            wasActionSelected = true
            dismiss(animated: true) {
                action()
            }
        case .separator:
            break
        }
    }

}

extension BrowsingMenuViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return menuEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let theme = ThemeManager.shared.currentTheme
        
        switch menuEntries[indexPath.row] {
        case .regular(let name, let accessibilityLabel, let image, let showNotificationDot, let customDotColor, _, _, _, _):
            guard let cell = tableView.dequeueReusableCell(withIdentifier: Contants.entryCellReuseIdentifier,
                                                           for: indexPath) as? BrowsingMenuEntryViewCell else {
                fatalError("Cell should be dequeued")
            }
            
            cell.configure(image: image, label: name, accessibilityLabel: accessibilityLabel, showNotificationDot: showNotificationDot, customDotColor: customDotColor)
            return cell
        case .separator:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: Contants.separatorCellReuseIdentifier,
                                                           for: indexPath) as? BrowsingMenuSeparatorViewCell else {
                fatalError("Cell should be dequeued")
            }
            
            cell.separator.backgroundColor = theme.browsingMenuSeparatorColor
            cell.backgroundColor = theme.browsingMenuBackgroundColor
            return cell
        }
    }
}

extension BrowsingMenuViewController: UIViewControllerTransitioningDelegate {

    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return nil
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return nil
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return animator
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return animator
    }

}

extension BrowsingMenuViewController {
    
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        configureArrow(with: theme.browsingMenuBackgroundColor)
        configureShadow(for: theme)
        
        for headerButton in headerButtons {
            headerButton.image.tintColor = theme.browsingMenuIconsColor
            headerButton.label.textColor = theme.browsingMenuTextColor
            headerButton.highlight.backgroundColor = theme.browsingMenuHighlightColor
            headerButton.backgroundColor = theme.browsingMenuBackgroundColor
        }
        
        horizontalContainer.backgroundColor = theme.browsingMenuBackgroundColor
        tableView.backgroundColor = theme.browsingMenuBackgroundColor
        menuView.backgroundColor = theme.browsingMenuBackgroundColor

        separator.backgroundColor = theme.browsingMenuSeparatorColor
        
        tableView.reloadData()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        DispatchQueue.main.async { [weak self] in
            self?.flashScrollIndicatorsIfNeeded()
        }

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            configureArrow(with: ThemeManager.shared.currentTheme.browsingMenuBackgroundColor)
        }
    }
}

extension BrowsingMenuEntry {
    var isSeparator: Bool {
        switch self {
        case .separator: return true
        default: return false
        }
    }
}
