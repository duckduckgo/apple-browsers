import PixelKit

enum AutoconsentPixel: PixelKitEventV2 {

    case acInit
    case missedPopup
    case errorMultiplePopups
    case errorOptoutFailed
    case popupFound
    case done
    case doneCosmetic
    case animationShown
    case animationShownCosmetic
    case disabledForSite
    case detectedByPatterns
    case detectedByBoth
    case detectedOnlyRules
    case selfTestOk
    case selfTestFail

    case summary(events: [String: Int])

    static var summaryPixels = [AutoconsentPixel] (
        arrayLiteral: .acInit,
        .missedPopup,
        .errorMultiplePopups,
        .errorOptoutFailed,
        .popupFound,
        .done,
        .doneCosmetic,
        .animationShown,
        .animationShownCosmetic,
        .disabledForSite,
        .detectedByPatterns,
        .detectedByBoth,
        .detectedOnlyRules,
        .selfTestOk,
        .selfTestFail
    )

    var name: String {
        switch self {
        case .acInit: "autoconsent_init"
        case .missedPopup: "autoconsent_missed-popup"
        case .errorMultiplePopups: "autoconsent_error_multiple-popups"
        case .errorOptoutFailed: "autoconsent_error_optout"
        case .popupFound: "autoconsent_popup-found"
        case .done: "autoconsent_done"
        case .doneCosmetic: "autoconsent_done_cosmetic"
        case .animationShown: "autoconsent_animation-shown"
        case .animationShownCosmetic: "autoconsent_animation-shown_cosmetic"
        case .disabledForSite: "autoconsent_disabled-for-site"
        case .detectedByPatterns: "autoconsent_detected-by-patterns"
        case .detectedByBoth: "autoconsent_detected-by-both"
        case .detectedOnlyRules: "autoconsent_detected-only-rules"
        case .selfTestOk: "autoconsent_self-test-ok"
        case .selfTestFail: "autoconsent_self-test-fail"
        case .summary: "autoconsent_summary"
        }
    }

    var key: String {
        return String(name.dropFirst(12))
    }

    var parameters: [String: String]? {
        switch self {
        case let .summary(events):
            Dictionary(uniqueKeysWithValues: AutoconsentPixel.summaryPixels.map { pixel in
            (pixel.key, "\(events[pixel.key] ?? 0)")
            })
        default: [:]
        }
    }

    var error: (any Error)? {
        nil
    }
}
