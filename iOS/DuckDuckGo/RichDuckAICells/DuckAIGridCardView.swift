//
//  DuckAIGridCardView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

/// View rendering the rich Duck.ai tab grid card body (title + content + type chip).
final class DuckAIGridCardView: UIView {

    private enum Metrics {
        static let contentTopInset: CGFloat = 12
        static let contentHorizontalInset: CGFloat = 8
        static let snippetLeadingInset: CGFloat = 8
        static let snippetTrailingInset: CGFloat = 16
        static let contentBottomInset: CGFloat = 8
        static let titleSnippetSpacing: CGFloat = 4
        static let imageVerticalSpacing: CGFloat = 12
        static let snippetChipSpacing: CGFloat = 4
        static let chipHeight: CGFloat = 22
        static let thumbnailCornerRadius: CGFloat = 16
        static let voiceMascotVerticalSpacing: CGFloat = 8
        static let voiceMascotHeight: CGFloat = 80
        static let emptyLogoHeight: CGFloat = 64
        static let voiceStatusIconSize: CGFloat = 16
        static let voiceStatusIconSpacing: CGFloat = 4
    }
    
    private enum Colors {
        static let backgroundColor = UIColor(lightColor: UIColor(designSystemColor: .accentAltGlowPrimary),
                                             darkColor: UIColor(designSystemColor: .surfaceSecondary))
    }

    private let titleLabel = UILabel()
    private let statusIconImageView = UIImageView()
    private let snippetLabel = UILabel()
    private let chipView = ChipView()
    private let thumbnailImageView = UIImageView()
    private let mascotImageView = UIImageView()
    private let logoImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
        setupAccessibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Apply the supplied grid item to the view.
    /// Callers pass `nil` when they want the screenshot fallback
    func configure(with item: DuckAIGridItem) {
        resetAppearance() // the `.voice` arm overrides for the dark card
        configureSnippet(for: item)
        configureTitle(for: item)
        configureThumbnail(for: item)
        configureLogo(for: item)
        configureChip(for: item)
        configureVoiceUIIfNeeded(for: item)
        updateAccessibility(for: item)
    }

    /// Fills the thumbnail for the `.image` variant. Pass `nil` to clear (e.g. on cell reuse
    /// before the async load completes).
    func setThumbnail(_ image: UIImage?) {
        thumbnailImageView.image = image
    }

    /// Whether the `.image` thumbnail is already populated — lets the snapshot path skip a redundant load.
    var hasThumbnail: Bool { thumbnailImageView.image != nil }

    /// Resets to the default light appearance. Called on cell reuse so a recycled `.voice` (dark)
    /// card never lingers in dark state if shown before the next `configure(with:)`.
    func resetAppearance() {
        backgroundColor = Colors.backgroundColor
        overrideUserInterfaceStyle = .unspecified
        setMascotVisible(false)
        setLogoVisible(false)
        statusIconImageView.isHidden = true
    }

    private func configureTitle(for item: DuckAIGridItem) {
        switch item {
        case .text(let title, _), .transcript(let title, _), .image(let title, _):
            titleLabel.text = title
            titleLabel.isHidden = false
        case .voice:
            titleLabel.text = UserText.aiChatTabSwitcherCardVoiceListening
            titleLabel.isHidden = false
        case .empty(let title, _):
            titleLabel.text = title
            titleLabel.isHidden = (title == nil)
        }
    }
    
    private func configureSnippet(for item: DuckAIGridItem) {
        switch item {
        case .text(_, let snippet), .transcript(_, let snippet):
            snippetLabel.attributedText = snippetAttributedText(snippet)
            snippetLabel.isHidden = false
        default:
            snippetLabel.attributedText = nil
            snippetLabel.isHidden = true
        }
    }

    /// Renders the snippet markdown (bold/italic) and tightens inter-line spacing.
    private func snippetAttributedText(_ snippet: String) -> NSAttributedString {
        let result: NSMutableAttributedString
        if let markdown = try? AttributedString(markdown: snippet) {
            result = NSMutableAttributedString(attributedString: NSAttributedString(markdown))
        } else {
            result = NSMutableAttributedString(string: snippet)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 0.9
        result.addAttribute(.paragraphStyle,
                            value: paragraph,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
    
    private func configureThumbnail(for item: DuckAIGridItem) {
        switch item {
        case .image:
            setThumbnailVisible(true)
        default:
            setThumbnailVisible(false)
        }
    }
    
    private func configureChip(for item: DuckAIGridItem) {
        guard let kind = item.chipKind else {
            chipView.isHidden = true
            return
        }
        switch kind {
        case .chat:
            chipView.configure(icon: DesignSystemImages.Glyphs.Size12.chat,
                               label: UserText.aiChatTabSwitcherCardChipChat)
        case .transcript:
            chipView.configure(icon: DesignSystemImages.Glyphs.Size12.voice,
                               label: UserText.aiChatTabSwitcherCardChipTranscript)
        case .voice:
            chipView.configure(icon: DesignSystemImages.Glyphs.Size12.voice,
                               label: UserText.aiChatTabSwitcherCardChipVoice)
        }
        chipView.isHidden = false
    }

    private func configureLogo(for item: DuckAIGridItem) {
        switch item {
        case .empty: setLogoVisible(true)
        default: setLogoVisible(false)
        }
    }
    
    private func configureVoiceUIIfNeeded(for item: DuckAIGridItem) {
        guard item == .voice else { return }
        // Dark, static live-voice card: "Listening…" status + centred mascot + "Voice" chip.
        // Forcing the subtree to `.dark` flips the reused DRK colours to light-on-dark.
        backgroundColor = UIColor(singleUseColor: .duckAIVoiceCellBackground)
        overrideUserInterfaceStyle = .dark
        setMascotVisible(true)
        statusIconImageView.isHidden = false
    }

    private func setThumbnailVisible(_ visible: Bool) {
        thumbnailImageView.isHidden = !visible
        if !visible { thumbnailImageView.image = nil }
    }

    private func setMascotVisible(_ visible: Bool) {
        mascotImageView.isHidden = !visible
    }

    private func setLogoVisible(_ visible: Bool) {
        logoImageView.isHidden = !visible
    }

    private func setupSubviews() {
        // Corner radius is owned by the host cell (`TabViewGridCell`), which matches it to the
        // screenshot preview's slot. Only the curve + clipping live here.
        backgroundColor = Colors.backgroundColor
        layer.cornerCurve = .continuous
        clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .daxSubheadSemibold()
        titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        // Leading status glyph for the live-voice card; shown only by `configureVoiceUIIfNeeded`.
        statusIconImageView.translatesAutoresizingMaskIntoConstraints = false
        statusIconImageView.image = DesignSystemImages.Glyphs.Size16.permissionMicrophone.withRenderingMode(.alwaysTemplate)
        statusIconImageView.tintColor = UIColor(designSystemColor: .icons)
        statusIconImageView.contentMode = .scaleAspectFit
        statusIconImageView.isHidden = true
        statusIconImageView.setContentHuggingPriority(.required, for: .horizontal)
        statusIconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Title row = optional status icon + title. The icon collapses out of the stack when
        // hidden, so non-voice cards keep a full-width title and only voice shows the 4pt gap.
        let titleStack = UIStackView(arrangedSubviews: [statusIconImageView, titleLabel])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = Metrics.voiceStatusIconSpacing
        addSubview(titleStack)

        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.font = .daxFootnoteRegular()
        snippetLabel.textColor = UIColor(designSystemColor: .textSecondary)
        snippetLabel.numberOfLines = 0
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.adjustsFontForContentSizeCategory = true
        // On short cells the snippet yields before the title/chip (which keep their size).
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(snippetLabel)

        chipView.translatesAutoresizingMaskIntoConstraints = false
        chipView.setContentHuggingPriority(.required, for: .horizontal)
        chipView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(chipView)

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.layer.cornerRadius = Metrics.thumbnailCornerRadius
        thumbnailImageView.layer.cornerCurve = .continuous
        thumbnailImageView.isHidden = true
        // On short cells the thumbnail yields before the title/chip (which keep their size).
        thumbnailImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(thumbnailImageView)

        mascotImageView.translatesAutoresizingMaskIntoConstraints = false
        mascotImageView.contentMode = .scaleAspectFit
        mascotImageView.image = UIImage(resource: .duckAIVoiceChatFace)
        mascotImageView.isHidden = true
        addSubview(mascotImageView)

        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.image = DesignSystemImages.Color.Size96.daxDuckAIStacked
        logoImageView.isHidden = true
        addSubview(logoImageView)
        let logoAspectRatio = logoImageView.image.map { $0.size.height > 0 ? $0.size.width / $0.size.height : 1 } ?? 1

        // Snippet may have to shrink so the chip stays anchored to the bottom; let
        // it lose against the chip's bottom anchor instead of breaking the layout.
        let snippetBottom = snippetLabel.bottomAnchor.constraint(lessThanOrEqualTo: chipView.topAnchor,
                                                                 constant: -Metrics.snippetChipSpacing)
        snippetBottom.priority = .defaultHigh

        // Target 80pt, but yield on short cells so the clamps below win instead of breaking.
        let mascotHeight = mascotImageView.heightAnchor.constraint(equalToConstant: Metrics.voiceMascotHeight)
        mascotHeight.priority = .defaultHigh

        // The thumbnail fills the gap between title and chip, but yields on short cells so the
        // title's top pin and the chip stay anchored rather than the layout breaking.
        let thumbnailTop = thumbnailImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.imageVerticalSpacing)
        let thumbnailBottom = thumbnailImageView.bottomAnchor.constraint(equalTo: chipView.topAnchor, constant: -Metrics.imageVerticalSpacing)
        thumbnailTop.priority = .defaultHigh
        thumbnailBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.contentTopInset),
            titleStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentHorizontalInset),
            titleStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentHorizontalInset),

            statusIconImageView.widthAnchor.constraint(equalToConstant: Metrics.voiceStatusIconSize),
            statusIconImageView.heightAnchor.constraint(equalToConstant: Metrics.voiceStatusIconSize),

            snippetLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleSnippetSpacing),
            snippetLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.snippetLeadingInset),
            snippetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.snippetTrailingInset),
            snippetBottom,

            chipView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentHorizontalInset),
            chipView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.contentBottomInset),
            chipView.heightAnchor.constraint(equalToConstant: Metrics.chipHeight),

            thumbnailTop,
            thumbnailImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.contentHorizontalInset),
            thumbnailImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.contentHorizontalInset),
            thumbnailBottom,

            // Voice mascot: fixed-height, centred, clamped so it never collides with the status
            // row or chip (aspect-fit, dark card only).
            mascotImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            mascotImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            mascotHeight,
            mascotImageView.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: Metrics.voiceMascotVerticalSpacing),
            mascotImageView.bottomAnchor.constraint(lessThanOrEqualTo: chipView.topAnchor, constant: -Metrics.voiceMascotVerticalSpacing),

            // Empty-state Duck.ai logo: fixed height, centred; width follows the asset's aspect ratio.
            logoImageView.heightAnchor.constraint(equalToConstant: Metrics.emptyLogoHeight),
            logoImageView.widthAnchor.constraint(equalTo: logoImageView.heightAnchor, multiplier: logoAspectRatio),
            logoImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    private func updateAccessibility(for item: DuckAIGridItem) {
        switch item {
        case .text(let title, let snippet), .transcript(let title, let snippet):
            accessibilityLabel = title
            accessibilityValue = snippet
        case .image(let title, _):
            accessibilityLabel = title
            accessibilityValue = nil
        case .voice:
            accessibilityLabel = UserText.aiChatTabSwitcherCardVoiceListeningAccessibilityLabel
            accessibilityValue = nil
        case .empty(let title, _):
            accessibilityLabel = title ?? UserText.omnibarFullAIChatModeDisplayTitle
            accessibilityValue = nil
        }
    }
}

// MARK: - Chip

/// Border-only pill rendered at the bottom-leading of the rich card identifying
/// the chat type.
private final class ChipView: UIView {

    private enum Metrics {
        static let cornerRadius: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let iconLabelSpacing: CGFloat = 6
        static let iconSize: CGFloat = 11
        static let borderWidth: CGFloat = 1
    }

    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(icon: UIImage, label: String) {
        iconView.image = icon
        self.label.text = label
    }

    private func setupSubviews() {
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = Metrics.borderWidth
        applyBorderColor()

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(designSystemColor: .icons)
        addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .daxCaptionMedium()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.adjustsFontForContentSizeCategory = true
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor,
                                              constant: Metrics.horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor,
                                           constant: Metrics.iconLabelSpacing),
            label.trailingAnchor.constraint(equalTo: trailingAnchor,
                                            constant: -Metrics.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyBorderColor()
        }
    }

    private func applyBorderColor() {
        // CGColor doesn't auto-resolve against the trait collection — refresh in
        // traitCollectionDidChange so dark mode doesn't end up with a stale colour.
        layer.borderColor = UIColor(designSystemColor: .containerBorderPrimary)
            .resolvedColor(with: traitCollection)
            .cgColor
    }
}
