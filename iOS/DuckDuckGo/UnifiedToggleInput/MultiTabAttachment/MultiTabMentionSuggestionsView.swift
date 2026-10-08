//
//  MultiTabMentionSuggestionsView.swift
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
import UIComponents
import UIKit

final class MultiTabMentionSuggestionsView: UIView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 28
        static let minimumRowHeight: CGFloat = 44
        static let rowVerticalPadding: CGFloat = 14
        static let trailingPadding: CGFloat = 16
        static let leadingPadding: CGFloat = 24
        static let faviconSize: CGFloat = 20
        static let faviconCornerRadius: CGFloat = 4
        static let faviconTextSpacing: CGFloat = 10
        static let titleDomainSpacing: CGFloat = 8
        static let maximumDomainWidthRatio: CGFloat = 1.0 / 3.0
        static let shadowMaskOutset: CGFloat = 96
        static var titleFont: UIFont { .daxSubheadRegular() }
        static var domainFont: UIFont { .daxCaption1() }
    }

    var onSelect: ((MultiTabAttachmentCandidate) -> Void)?
    var onDismiss: (() -> Void)?

    var preferredContentHeight: CGFloat { CGFloat(suggestions.count) * tableView.rowHeight }
    var minimumVisibleHeight: CGFloat { tableView.rowHeight }

    private let showsGlassShadow: Bool
    private let shadowView = CompositeShadowView()
    private let outerShadowMask = CAShapeLayer()
    private let glassView = UIVisualEffectView()
    private let contentView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private lazy var tableHeightConstraint = tableView.heightAnchor.constraint(equalToConstant: 0)
    private var suggestions: [MultiTabMentionController.Suggestion] = []
    private var isSelectingTab = false
    private var isDismissing = false

    private static var shadows: [CompositeShadowView.Shadow] {
        [
            .init(id: "outer", color: UIColor(designSystemColor: .shadowSecondary),
                  radius: 32, offset: CGSize(width: 0, height: 8)),
            .init(id: "rim", color: UIColor(designSystemColor: .shadowTertiary),
                  radius: 16, offset: CGSize(width: 0, height: 2)),
        ]
    }

    init(showsGlassShadow: Bool) {
        self.showsGlassShadow = showsGlassShadow
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = false
        accessibilityIdentifier = "AIChat.TabMention.Suggestions"

        setupSurface()
        setupTable()
        updateSurfaceAppearance()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSurfaceAppearance),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                                               object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with suggestions: [MultiTabMentionController.Suggestion]) {
        guard self.suggestions != suggestions else { return }
        self.suggestions = suggestions
        updateTableHeight()
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOuterShadowMask()
        tableView.isScrollEnabled = CGFloat(suggestions.count) * tableView.rowHeight > bounds.height
    }

    func dismiss() {
        guard isSelectingTab else {
            removeFromSuperview()
            return
        }
        isDismissing = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        tableHeightConstraint.constant = 0
        if glassView.effect != nil {
            // Glass dematerializes through its effect; fading its ancestor breaks backdrop rendering.
            glassView.effect = nil
            contentView.alpha = 0
            shadowView.alpha = 0
        } else {
            alpha = 0
        }
        superview?.layoutIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            shadowView.shadows = Self.shadows
            updateSurfaceAppearance()
        }
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        updateTableHeight()
        tableView.reloadData()
    }

    override func accessibilityPerformEscape() -> Bool {
        onDismiss?()
        return true
    }

    private func setupSurface() {
        shadowView.shadows = Self.shadows
        shadowView.isUserInteractionEnabled = false
        shadowView.accessibilityElementsHidden = true
        shadowView.backgroundColor = UIColor(designSystemColor: .surfaceSecondary)
        shadowView.layer.cornerRadius = Metrics.cornerRadius
        shadowView.layer.cornerCurve = .continuous
        outerShadowMask.fillRule = .evenOdd
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.layer.cornerRadius = Metrics.cornerRadius
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        // Content clips independently so the outer shadow can extend beyond the panel.
        let cardViews: [UIView] = [shadowView, glassView]
        for view in cardViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        glassView.contentView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(singleUseColor: .inputContentSeparator)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: Metrics.leadingPadding + Metrics.faviconSize + Metrics.faviconTextSpacing,
                                               bottom: 0, right: Metrics.trailingPadding)
        tableView.keyboardDismissMode = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.scrollsToTop = false
        tableView.delaysContentTouches = false
        tableView.estimatedRowHeight = 0
        tableView.sectionHeaderTopPadding = 0
        tableView.tableFooterView = UIView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(Cell.self, forCellReuseIdentifier: Cell.reuseIdentifier)
        contentView.addSubview(tableView)

        tableHeightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            tableHeightConstraint,
        ])
        updateTableHeight()
    }

    @objc private func updateSurfaceAppearance() {
        guard !isDismissing else { return }
        if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
            glassView.cornerConfiguration = .corners(radius: .fixed(Metrics.cornerRadius))
            glassView.effect = UIGlassEffect(style: .regular)
            contentView.backgroundColor = .clear
            // Cut out the opaque backing so only the outer shadow sits behind the glass.
            shadowView.layer.cornerCurve = .circular
            shadowView.layer.mask = outerShadowMask
            updateOuterShadowMask()
            shadowView.isHidden = !showsGlassShadow
        } else {
            glassView.effect = nil
            contentView.backgroundColor = UIColor(designSystemColor: .surfaceSecondary)
            shadowView.layer.cornerCurve = .continuous
            shadowView.layer.mask = nil
            shadowView.isHidden = false
        }
    }

    private func updateOuterShadowMask() {
        guard shadowView.layer.mask != nil else { return }
        let outset = Metrics.shadowMaskOutset
        let maskFrame = bounds.insetBy(dx: -outset, dy: -outset)
        let path = UIBezierPath(rect: CGRect(origin: .zero, size: maskFrame.size))
        path.append(UIBezierPath(roundedRect: bounds.offsetBy(dx: outset, dy: outset), cornerRadius: Metrics.cornerRadius))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outerShadowMask.frame = maskFrame
        outerShadowMask.path = path.cgPath
        CATransaction.commit()
    }

    private func updateTableHeight() {
        guard !isDismissing else { return }
        tableView.rowHeight = max(Metrics.minimumRowHeight,
                                 max(Metrics.titleFont.lineHeight, Metrics.domainFont.lineHeight) + Metrics.rowVerticalPadding)
        tableHeightConstraint.constant = CGFloat(suggestions.count) * tableView.rowHeight
    }

    private func selectTab(_ candidate: MultiTabAttachmentCandidate) {
        guard window != nil else {
            onSelect?(candidate)
            return
        }
        superview?.layoutIfNeeded()
        // Attachment layout and the panel's collapse share the footer's animation transaction.
        UTIFooterController.animateWithSpring({
            self.isSelectingTab = true
            defer { self.isSelectingTab = false }
            self.onSelect?(candidate)
        }, completion: { [weak self] _ in
            guard let self, self.isDismissing else { return }
            self.removeFromSuperview()
        })
    }

    private final class Cell: UITableViewCell {
        static let reuseIdentifier = "TabMentionSuggestionCell"

        private let faviconView = UIImageView()
        private let titleLabel = UILabel()
        private let domainLabel = UILabel()

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = .clear
            isAccessibilityElement = true
            faviconView.contentMode = .scaleAspectFit
            faviconView.layer.cornerRadius = Metrics.faviconCornerRadius
            faviconView.clipsToBounds = true
            faviconView.tintColor = UIColor(designSystemColor: .iconsSecondary)
            titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            domainLabel.textColor = UIColor(designSystemColor: .textSecondary)
            domainLabel.adjustsFontForContentSizeCategory = true
            domainLabel.lineBreakMode = .byTruncatingMiddle
            domainLabel.textAlignment = .right
            domainLabel.setContentHuggingPriority(.required, for: .horizontal)
            let rowSubviews: [UIView] = [faviconView, titleLabel, domainLabel]
            for view in rowSubviews {
                view.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(view)
            }
            NSLayoutConstraint.activate([
                faviconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.leadingPadding),
                faviconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                faviconView.widthAnchor.constraint(equalToConstant: Metrics.faviconSize),
                faviconView.heightAnchor.constraint(equalToConstant: Metrics.faviconSize),
                titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: Metrics.faviconTextSpacing),
                titleLabel.trailingAnchor.constraint(equalTo: domainLabel.leadingAnchor, constant: -Metrics.titleDomainSpacing),
                titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                domainLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.trailingPadding),
                domainLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
                domainLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: Metrics.maximumDomainWidthRatio),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateConfiguration(using state: UICellConfigurationState) {
            super.updateConfiguration(using: state)
            guard #available(iOS 26.0, *) else { return }
            var background = UIBackgroundConfiguration.clear()
            background.cornerRadius = 10
            background.backgroundInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
            if (state.isHighlighted || state.isSelected) && selectionStyle != .none {
                background.backgroundColor = UIColor(designSystemColor: .controlsFillSecondary)
            }
            backgroundConfiguration = background
        }

        func configure(with suggestion: MultiTabMentionController.Suggestion) {
            let candidate = suggestion.candidate
            let displayDomain = candidate.url.host?.droppingWwwPrefix()
            titleLabel.font = Metrics.titleFont
            titleLabel.text = candidate.title
            domainLabel.font = Metrics.domainFont
            domainLabel.text = displayDomain
            faviconView.image = FaviconsHelper.loadFaviconSync(forDomain: candidate.url.host,
                                                             usingCache: .tabs,
                                                             useFakeFavicon: true).image?.withRenderingMode(.alwaysOriginal)
                ?? DesignSystemImages.Glyphs.Size16.globe.withRenderingMode(.alwaysTemplate)
            contentView.alpha = suggestion.isEnabled ? 1 : 0.4
            selectionStyle = suggestion.isEnabled ? .default : .none
            accessibilityTraits = suggestion.isEnabled ? [.button] : [.button, .notEnabled]
            accessibilityLabel = [candidate.title, displayDomain].compactMap { $0 }.joined(separator: ", ")
            accessibilityIdentifier = "AIChat.TabMention.Suggestions.\(candidate.tabId)"
        }
    }
}

extension MultiTabMentionSuggestionsView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        suggestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: Cell.reuseIdentifier, for: indexPath) as? Cell else {
            return UITableViewCell()
        }
        cell.configure(with: suggestions[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        suggestions[indexPath.row].isEnabled ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let suggestion = suggestions[indexPath.row]
        guard suggestion.isEnabled else { return }
        selectTab(suggestion.candidate)
    }
}
