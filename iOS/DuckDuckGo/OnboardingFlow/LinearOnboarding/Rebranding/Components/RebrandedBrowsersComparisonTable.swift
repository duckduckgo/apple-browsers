import SwiftUI
import DesignResourcesKit
import Onboarding

private enum ComparisonTableMetrics {
    // Header
    static let headerIconSize: CGFloat = 64

    // Row layout
    static let rowSpacing: CGFloat = 0
    static let cellHeight: CGFloat = 56
    static let cellCornerRadius: CGFloat = 12
    static let cellInsets: EdgeInsets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 4)

    // Feature section (left)
    static let featureIconSize: CGFloat = 32
    static let featureTextSpacing: CGFloat = 8

    // Status section (right)
    static let availabilityIconSize: CGFloat = 24
    static let statusColumnWidth: CGFloat = 36
    static let statusColumnSpacing: CGFloat = 8

    // Separator
    static let separatorColor = Color(singleUseColor: .rebranding(.comparisonSeparator))
    static let separatorWidth: CGFloat = 1
}

struct RebrandedBrowsersComparisonTable: View {

    var body: some View {
        VStack(spacing: ComparisonTableMetrics.rowSpacing) {
            ComparisonHeader()

            ForEach(Array(RebrandedBrowsersComparisonModel.features.enumerated()), id: \.element.type) { index, feature in
                FeatureRow(feature: feature, index: index)
            }
        }
    }
}

// MARK: - Header

private struct ComparisonHeader: View {

    var body: some View {
        // NOTE: Negative spacing/padding compensates for built-in padding in the icon PDFs (shadow regions from export).
        HStack(spacing: -10) {
            Spacer()

            OnboardingRebrandingImages.Comparison.safariIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ComparisonTableMetrics.headerIconSize, height: ComparisonTableMetrics.headerIconSize)

            OnboardingRebrandingImages.Comparison.ddgIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ComparisonTableMetrics.headerIconSize, height: ComparisonTableMetrics.headerIconSize)
        }
        .padding(.trailing, -10)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let feature: RebrandedBrowsersComparisonModel.Feature
    let index: Int

    private var backgroundColor: Color {
        index % 2 == 0 ? Color(singleUseColor: .rebranding(.accentAltGlowPrimary)) : Color.clear
    }

    var body: some View {
        ZStack(alignment: .leading) {
            backgroundColor
                .cornerRadius(ComparisonTableMetrics.cellCornerRadius)

            HStack {
                HStack(alignment: .center, spacing: ComparisonTableMetrics.featureTextSpacing) {
                    feature.type.icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ComparisonTableMetrics.featureIconSize, height: ComparisonTableMetrics.featureIconSize)

                    Text(feature.type.title)
                        .font(onboardingTheme.typography.rowDetails)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: ComparisonTableMetrics.statusColumnSpacing) {
                    feature.safariAvailability.image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ComparisonTableMetrics.availabilityIconSize, height: ComparisonTableMetrics.availabilityIconSize)
                        .frame(width: ComparisonTableMetrics.statusColumnWidth)

                    Rectangle()
                        .fill(ComparisonTableMetrics.separatorColor)
                        .frame(width: ComparisonTableMetrics.separatorWidth)

                    feature.ddgAvailability.image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ComparisonTableMetrics.availabilityIconSize, height: ComparisonTableMetrics.availabilityIconSize)
                        .frame(width: ComparisonTableMetrics.statusColumnWidth)
                }
            }
            .padding(ComparisonTableMetrics.cellInsets)
        }
        .frame(height: ComparisonTableMetrics.cellHeight)
        .clipShape(RoundedRectangle(cornerRadius: ComparisonTableMetrics.cellCornerRadius))
    }
}
