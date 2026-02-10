import SwiftUI
import Onboarding

struct RebrandedBrowsersComparisonModel {

    struct Feature: Equatable {
        let type: FeatureType
        let safariAvailability: Availability
        let ddgAvailability: Availability

        enum FeatureType: Equatable {
            case privateSearch
            case blockTrackers
            case blockCookies
            case blockAds
            case eraseData

            var title: String {
                switch self {
                case .privateSearch:
                    return UserText.RebrandedOnboarding.BrowsersComparison.privateSearch
                case .blockTrackers:
                    return UserText.RebrandedOnboarding.BrowsersComparison.blockTrackers
                case .blockCookies:
                    return UserText.RebrandedOnboarding.BrowsersComparison.blockCookies
                case .blockAds:
                    return UserText.RebrandedOnboarding.BrowsersComparison.blockAds
                case .eraseData:
                    return UserText.RebrandedOnboarding.BrowsersComparison.eraseData
                }
            }

            var icon: Image {
                switch self {
                case .privateSearch:
                    return OnboardingRebrandingImages.Comparison.privateSearchIcon
                case .blockTrackers:
                    return OnboardingRebrandingImages.Comparison.blockTrackersIcon
                case .blockCookies:
                    return OnboardingRebrandingImages.Comparison.blockCookiesIcon
                case .blockAds:
                    return OnboardingRebrandingImages.Comparison.blockAdsIcon
                case .eraseData:
                    return OnboardingRebrandingImages.Comparison.eraseDataIcon
                }
            }
        }

        enum Availability {
            case available
            case partial
            case unavailable

            var image: Image {
                switch self {
                case .available:
                    return OnboardingRebrandingImages.Comparison.availableIcon
                case .partial:
                    return OnboardingRebrandingImages.Comparison.partialIcon
                case .unavailable:
                    return OnboardingRebrandingImages.Comparison.unavailableIcon
                }
            }
        }
    }

    static let features: [Feature] = [
        Feature(
            type: .privateSearch,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        ),
        Feature(
            type: .blockTrackers,
            safariAvailability: .partial,
            ddgAvailability: .available
        ),
        Feature(
            type: .blockCookies,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        ),
        Feature(
            type: .blockAds,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        ),
        Feature(
            type: .eraseData,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        )
    ]
}
