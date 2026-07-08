//
//  TabViewController.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import AVFoundation
import WebKit
import Core
import Combine
import CombineExtensions
import StoreKit
import LocalAuthentication
import BrowserServicesKit
import Navigation
import SwiftUI
import Bookmarks
import Persistence
import Common
import FoundationExtensions
import DDGSync
import PrivacyDashboard
import UserScript
import ContentBlocking
import TrackerRadarKit
import Networking
import SecureStorage
import History
import ContentScopeScripts
import SpecialErrorPages
import VPN
import Onboarding
import os.log
import Subscription
import WKAbstractions
import SERPSettings
import AIChat
import PixelKit
import PrivacyConfig
import WebExtensions
import DesignResourcesKitIcons

class TabViewController: UIViewController {

    private struct Constants {
        static let frameLoadInterruptedErrorCode = 102
        static let trackerNetworksAnimationDelay: TimeInterval = 0.7
        static let secGPCHeader = "Sec-GPC"
        static let navigationExpectationInterval = 3.0
    }

    /// Set by `loadVoiceMode()` so that `refreshUnifiedToggleInput` can suppress
    /// auto-expand even before the `?mode=voice` URL is committed to the web view.
    var isVoiceModeRequested = false

    lazy var borderView = StyledTopBottomBorderView()

    var privacyDashboardAnchor: UIView!
    var error: UIView!
    
    var errorInfoImage: UIImageView!
    var errorHeader: UILabel!
    var errorMessage: UILabel!
    
    var containerStackView: UIStackView!
    var outerContainer: UIView!
    var webViewContainer: UIView!
    var webViewBottomAnchorConstraint: NSLayoutConstraint?
    var daxContextualOnboardingController: UIViewController?
    var lastPresentedContextualOnboardingSpec: DaxDialogs.BrowsingSpec?
    
    /// Stores the visual state of the web view
    /// Used by DuckPlayer to save and restore view appearance when switching between normal browsing and fullscreen (portrail/landscape) video modes.
    private struct ViewSettings {
        
        let viewBackground: UIColor?
        let webViewBackground: UIColor?
        let webViewOpaque: Bool
        let scrollViewBackground: UIColor?
        
        /// Default view settings        
        static var `default`: ViewSettings {
            ViewSettings(
                viewBackground: .systemBackground,
                webViewBackground: nil,
                webViewOpaque: true,
                scrollViewBackground: .systemBackground
            )
        }
    }
    private var savedViewSettings: ViewSettings?
    private var cachedMapper: TrackerProtectionEventMapper?
    private var cachedMapperVendor: String?
    private var cachedMapperAttributionTrackerData: TrackerData?

    var showBarsTapGestureRecogniser: UITapGestureRecognizer!

    private let instrumentation = TabInstrumentation()
    let tabInteractionStateSource: TabInteractionStateSource?

    var isLinkPreview = false

    // A workaround for an issue when in some cases webview reports `isLoading == true` when it was stoppped.
    var isLoading: Bool {
        webView.isLoading && !wasLoadingStoppedExternally
    }

    var preventUniversalLinksOnce = false
    private var shouldUseSafariOnlyUserAgentForNextMainFrameNavigation = false
    private var safariRedirectLoopErrorURL: URL?
    private var defaultErrorHeaderText = ""
    lazy var errorActionButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.addTarget(self, action: #selector(onOpenInSafariFromErrorPage), for: .touchUpInside)
        return button
    }()
    lazy var errorReportBrokenSiteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.addTarget(self, action: #selector(onReportBrokenSiteFromErrorPage), for: .touchUpInside)
        return button
    }()
    var jsAlertContainerView: UIView!

    var openedByPage = false
    weak var openingTab: TabViewController? {
        didSet {
            delegate?.tabLoadingStateDidChange(tab: self)
        }
    }
    
    weak var delegate: TabDelegate?
    var aiChatContentHandlingDelegate: AIChatContentHandlingDelegate? {
        get {
            aiChatContentHandler.delegate
        }
        set {
            aiChatContentHandler.delegate = newValue
        }
    }
    weak var chromeDelegate: BrowserChromeDelegate?

    var findInPage: FindInPage? {
        get { return findInPageScript?.findInPage }
        set { findInPageScript?.findInPage = newValue }
    }
    
    var daxEasterEggHandler: DaxEasterEggHandling?
    var logoCache: DaxEasterEggLogoCaching = DaxEasterEggLogoCache()

    let favicons: FaviconManaging
    let progressWorker = WebProgressWorker()

    private(set) var webView: WKWebView!
    private lazy var appRatingPrompt: AppRatingPrompt = AppRatingPrompt(featureFlagger: self.featureFlagger)
    let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    public weak var privacyDashboard: PrivacyDashboardViewController?
    
    private var storageCache: StorageCache = AppDependencyProvider.shared.storageCache
    let appSettings: AppSettings

    let privacyConfigurationManager: PrivacyConfigurationManaging

    var featureFlagger: FeatureFlagger
    let contentScopeExperimentsManager: ContentScopeExperimentsManaging
    private lazy var internalUserDecider = AppDependencyProvider.shared.internalUserDecider

    private lazy var autofillNeverPromptWebsitesManager = AppDependencyProvider.shared.autofillNeverPromptWebsitesManager
    private lazy var autofillWebsiteAccountMatcher = AutofillWebsiteAccountMatcher(autofillUrlMatcher: AutofillDomainNameUrlMatcher(),
                                                                                   tld: TabViewController.tld)
    private(set) lazy var extensionPromotionManager: AutofillExtensionPromotionManaging = AutofillExtensionPromotionManager(keyValueStore: keyValueStore)
    private(set) var tabModel: Tab
    private(set) var viewModel: TabViewModel
    private(set) var privacyInfo: PrivacyInfo?
    private var previousPrivacyInfosByURL: [URL: PrivacyInfo] = [:]
    
    private let requeryLogic = RequeryLogic()

    private static let tld = AppDependencyProvider.shared.storageCache.tld
    private let adClickAttributionDetection = ContentBlocking.shared.makeAdClickAttributionDetection(tld: tld)
    let adClickExternalOpenDetector: AdClickExternalOpenDetector
    let adClickAttributionLogic = ContentBlocking.shared.makeAdClickAttributionLogic(tld: tld)

    private var httpsForced: Bool = false
    private(set) lazy var safariRedirectHandler: SafariRedirectHandler = {
        let handler = SafariRedirectHandler(tld: AppDependencyProvider.shared.storageCache.tld)
        handler.delegate = self
        return handler
    }()
    private var lastUpgradedURL: URL?
    private var httpsUpgradeTask: Task<Void, Never>?
    private var lastError: Error?
    private var lastHttpStatusCode: Int?
    private var shouldReloadOnError = false
    private var failingUrls = Set<String>()
    private var urlProvidedBasicAuthCredential: (credential: URLCredential, url: URL)?
    private var emailProtectionSignOutCancellable: AnyCancellable?

    public var inferredOpenerContext: BrokenSiteReport.OpenerContext?
    private var refreshCountSinceLoad: Int = 0
    private var breakageReportingSubfeature: BreakageReportingSubfeature?
    private var siteLoadingPerformanceSubfeature: SiteLoadingPerformanceSubfeature?

    private var detectedLoginURL: URL?
    private var fireproofingWorker: FireproofingWorking?

    private var trackersInfoWorkItem: DispatchWorkItem?
    private var lastVisitedTrackerAnimationDomain: String?
    private var lastNotifiedTrackerAnimationDomain: String?
    var shouldSuppressTrackerAnimationOnFirstLoad: Bool = false
    
    private var tabURLInterceptor: TabURLInterceptor
    private var currentlyLoadedURL: URL?

    private var addressBarURLFilter: AddressBarURLFiltering

    private let netPConnectionObserver: ConnectionStatusObserver = AppDependencyProvider.shared.connectionObserver
    private var netPConnectionObserverCancellable: AnyCancellable?
    private var netPConnectionStatus: ConnectionStatus = .default
    private var netPConnected: Bool {
        switch netPConnectionStatus {
        case .connected:
            return true
        default:
            break
        }

        return false
    }

    let subscriptionDataReporter: SubscriptionDataReporting

    // Required to know when to disable autofill, see SaveLoginViewModel / SaveCreditCardViewModel for details
    // Stored in memory on TabViewController for privacy reasons
    private var domainSaveLoginPromptLastShownOn: String?
    private var domainSaveCreditCardPromptLastShownOn: String?
    // Required to allow grace period between authentication prompts when autofilling credit cards
    // where forms are split into multiple iframes, requiring multiple prompts
    private var domainFillCreditCardPromptLastShownOn: String?
    // Required to prevent fireproof prompt presenting before autofill save login prompt
    private var saveLoginPromptLastDismissed: Date?
    private var saveLoginPromptIsPresenting: Bool = false
    // Required to determine whether to show credit card prompt or keyboard accessory
    private var fillCreditCardsPromptIsPresenting: Bool = false
    private var shouldShowCreditCardPrompt: Bool = true
    private var shouldShowAutofillExtensionPrompt: Bool = false

    private var cachedRuntimeConfigurationForDomain: [String: String?] = [:]

    // If no trackers dax dialog was shown recently in this tab, ie without the user navigating somewhere else, e.g. backgrounding or tab switcher
    private var woShownRecently = false

    // Temporary to gather some data.  Fire a follow up if no trackers dax dialog was shown and then trackers appear.
    private var fireWoFollowUp = false

    // Indicates if there was an external call to stop loading current request. Resets on new load request, refresh and failures.
    private var wasLoadingStoppedExternally = false

    // In certain conditions we try to present a dax dialog when one is already showing, so check to ensure we don't
    var isShowingFullScreenDaxDialog = false
    
    var temporaryDownloadForPreviewedFile: Download?
    var mostRecentAutoPreviewDownloadID: UUID?
    private var pendingCalendarPreview: CalendarEventPreviewHelper?
    private var pendingContactPreview: ContactPreviewHelper?
    private var blobDownloadTargetFrame: WKFrameInfo?

    // Recent request's URL if its WKNavigationAction had shouldPerformDownload set to true
    private var recentNavigationActionShouldPerformDownloadURL: URL?

    let userAgentManager: UserAgentManaging = DefaultUserAgentManager.shared
    
    let bookmarksDatabase: CoreDataDatabase
    lazy var faviconUpdater = FireproofFaviconUpdater(bookmarksDatabase: bookmarksDatabase,
                                                      tab: tabModel,
                                                      favicons: favicons,
                                                      sharedSecureVault: sharedSecureVault)

    private let refreshControl = UIRefreshControl()

    private let certificateTrustEvaluator: CertificateTrustEvaluating
    var storedSpecialErrorPageUserScript: SpecialErrorPageUserScript?
    let syncService: DDGSyncing

    let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>

    private let daxDialogsDebouncer = Debouncer(mode: .common)
    var pullToRefreshViewAdapter: PullToRefreshViewAdapter?

    lazy var autofillCreditCardAccessoryView: CreditCardInputAccessoryView? = {
        let initialFrame = CGRect(x: 0, y: 0, width: view.frame.width, height: 58)
        let creditCardInputAccessoryView = CreditCardInputAccessoryView(frame: initialFrame)
        creditCardInputAccessoryView.onCardManagementSelected = { [weak self] in
            guard let self = self else { return }
            self.dismissKeyboardIfPresent()
            self.delegate?.tabDidRequestSettingsToCreditCardManagement(self, source: .creditCardKeyboardShortcut)
        }
        return creditCardInputAccessoryView
    }()

    lazy var credentialsImportManager: AutofillCredentialsImportPresentationManager = {
        let manager = AutofillCredentialsImportPresentationManager(loginImportStateProvider: AutofillLoginImportState(keyValueStore: keyValueStore))
        return manager
    }()

    private let urlSubject = CurrentValueSubject<URL?, Never>(nil)
    var urlPublisher: AnyPublisher<URL?, Never> {
        urlSubject.eraseToAnyPublisher()
    }
    private let didFinishURLSubject = CurrentValueSubject<URL?, Never>(nil)
    var didFinishURLPublisher: AnyPublisher<URL?, Never> {
        didFinishURLSubject.eraseToAnyPublisher()
    }

    public var url: URL? {
        willSet {
            if newValue != url {
                delegate?.closeFindInPage(tab: self)
            }
        }
        didSet {
            updateTabModel()
            delegate?.tabLoadingStateDidChange(tab: self)
            checkLoginDetectionAfterNavigation()
            updateTrackerAnimationDomainState(for: url)
            urlSubject.send(url)
        }
    }
    
    override var title: String? {
        didSet {
            updateTabModel()
            delegate?.tabLoadingStateDidChange(tab: self)
            if let url {
                let finalURL = duckPlayerNavigationHandler.getDuckURLFor(url)
                viewModel.captureTitleDidChange(title, for: finalURL)
            }
        }
    }

    public var isError: Bool {
        return !error.isHidden
    }
    
    public var errorText: String? {
        return errorMessage.text
    }
    
    public var link: Core.Link? {
        if isError {
            if let url = url ?? webView.url ?? URL(string: "") {
                return Link(title: errorText, url: url)
            }
        }
        
        guard let url = url else {
            return tabModel.link
        }
                        
        let finalURL = duckPlayerNavigationHandler.getDuckURLFor(url)
        let activeLink = Link(title: title, url: finalURL)
        guard let storedLink = tabModel.link else {
            return activeLink
        }
        
        return activeLink.merge(with: storedLink)
    }
    
    /// Convenience property which passes back the value of `isAITab` from the underlying `TabModel`
    var isAITab: Bool {
        tabModel.isAITab
    }

    var emailManager: EmailManager? {
        return (parent as? MainViewController)?.emailManager
    }

    lazy var vaultManager: SecureVaultManager = {
        let manager = SecureVaultManager(shouldAllowPartialFormSaves: featureFlagger.isFeatureOn(.autofillPartialFormSaves),
                                         tld: AppDependencyProvider.shared.storageCache.tld)
        manager.delegate = self
        return manager
    }()

    private lazy var credentialIdentityStoreManager: AutofillCredentialIdentityStoreManager = {
        return AutofillCredentialIdentityStoreManager(reporter: SecureVaultReporter(),
                                                      tld: AppDependencyProvider.shared.storageCache.tld)
    }()

    private static let debugEvents = EventMapping<AMPProtectionDebugEvents> { event, _, params, onComplete in
        let domainEvent: Pixel.Event
        switch event {
        case .ampBlockingRulesCompilationFailed:
            domainEvent = .ampBlockingRulesCompilationFailed
        }
        Pixel.fire(pixel: domainEvent,
                   withAdditionalParameters: params ?? [:],
                   onComplete: onComplete)
    }
    
    private lazy var linkProtection: LinkProtection = {
        LinkProtection(privacyManager: privacyConfigurationManager,
                       contentBlockingManager: ContentBlocking.shared.contentBlockingManager,
                       errorReporting: Self.debugEvents)
    }()
    
    private lazy var referrerTrimming: ReferrerTrimming = {
        ReferrerTrimming(privacyManager: privacyConfigurationManager,
                         contentBlockingManager: ContentBlocking.shared.contentBlockingManager,
                         tld: AppDependencyProvider.shared.storageCache.tld)
    }()
        
    private var canDisplayJavaScriptAlert: Bool {
        return presentedViewController == nil
            && delegate?.tabCheckIfItsBeingCurrentlyPresented(self) ?? false
            && !(jsAlertView?.isShown ?? false)
    }

    func present(_ alert: WebJSAlert) {
        setupJSAlertViewIfNeeded()
        jsAlertView.present(alert)
    }

    private func dismissJSAlertIfNeeded() {
        if jsAlertView?.isShown == true {
            jsAlertView?.dismiss(animated: false)
        }
    }

    private let rulesCompilationMonitor = RulesCompilationMonitor.shared
    
    private var lastRenderedURL: URL?

    static func loadFromStoryboard(model: Tab,
                                   privacyConfigurationManager: PrivacyConfigurationManaging,
                                   appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
                                   bookmarksDatabase: CoreDataDatabase,
                                   historyManager: HistoryManaging,
                                   syncService: DDGSyncing,
                                   userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
                                   contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
                                   subscriptionDataReporter: SubscriptionDataReporting,
                                   contextualOnboardingPresenter: ContextualOnboardingPresenting,
                                   contextualOnboardingLogic: ContextualOnboardingLogic,
                                   onboardingPixelReporter: OnboardingCustomInteractionPixelReporting,
                                   featureFlagger: FeatureFlagger,
                                   contentScopeExperimentManager: ContentScopeExperimentsManaging,
                                   textZoomCoordinator: TextZoomCoordinating,
                                   autoconsentManagement: AutoconsentManaging,
                                   websiteDataManager: WebsiteDataManaging,
                                   fireproofing: Fireproofing,
                                   favicons: FaviconManaging,
                                   tabInteractionStateSource: TabInteractionStateSource?,
                                   specialErrorPageNavigationHandler: SpecialErrorPageManaging,
                                   featureDiscovery: FeatureDiscovery,
                                   keyValueStore: ThrowingKeyValueStoring,
                                   daxDialogsManager: DaxDialogsManaging,
                                   aiChatSettings: AIChatSettingsProvider,
                                   productSurfaceTelemetry: ProductSurfaceTelemetry,
                                   sharedSecureVault: (any AutofillSecureVault)? = nil,
                                   privacyStats: PrivacyStatsProviding,
                                   voiceSearchHelper: VoiceSearchHelperProtocol,
                                   darkReaderFeatureSettings: DarkReaderFeatureSettings,
                                   autoplaySettings: AutoplaySettings,
                                   duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
                                   duckAiFireModeStorageHandler: DuckAiNativeStorageHandling? = nil,
                                   adBlockingAvailability: AdBlockingAvailabilityProviding) -> TabViewController {

        return TabViewController(tabModel: model,
                                 privacyConfigurationManager: privacyConfigurationManager,
                                 appSettings: appSettings,
                                 bookmarksDatabase: bookmarksDatabase,
                                 historyManager: historyManager,
                                 syncService: syncService,
                                 userScriptsDependencies: userScriptsDependencies,
                                 contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
                                 subscriptionDataReporter: subscriptionDataReporter,
                                 contextualOnboardingPresenter: contextualOnboardingPresenter,
                                 contextualOnboardingLogic: contextualOnboardingLogic,
                                 onboardingPixelReporter: onboardingPixelReporter,
                                 featureFlagger: featureFlagger,
                                 contentScopeExperimentManager: contentScopeExperimentManager,
                                 textZoomCoordinator: textZoomCoordinator,
                                 autoconsentManagement: autoconsentManagement,
                                 fireproofing: fireproofing,
                                 favicons: favicons,
                                 websiteDataManager: websiteDataManager,
                                 tabInteractionStateSource: tabInteractionStateSource,
                                 specialErrorPageNavigationHandler: specialErrorPageNavigationHandler,
                                 featureDiscovery: featureDiscovery,
                                 keyValueStore: keyValueStore,
                                 daxDialogsManager: daxDialogsManager,
                                 aiChatSettings: aiChatSettings,
                                 productSurfaceTelemetry: productSurfaceTelemetry,
                                 sharedSecureVault: sharedSecureVault,
                                 privacyStats: privacyStats,
                                 voiceSearchHelper: voiceSearchHelper,
                                 darkReaderFeatureSettings: darkReaderFeatureSettings,
                                 autoplaySettings: autoplaySettings,
                                 duckAiNativeStorageHandler: duckAiNativeStorageHandler,
                                 duckAiFireModeStorageHandler: duckAiFireModeStorageHandler,
                                 adBlockingAvailability: adBlockingAvailability)
    }

    private var userContentController: UserContentController {
        (webView.configuration.userContentController as? UserContentController)!
    }


    let historyManager: HistoryManaging
    let adBlockingAvailability: AdBlockingAvailabilityProviding

    private(set) lazy var adBlockingNavigationHandler: AdBlockingNavigationHandling = {
        return AdBlockingNavigationHandler(
            availability: adBlockingAvailability,
            onShouldShowAdBlockingAnimation: { [weak self] in
                guard let self else { return }
                self.delegate?.tabDidRequestPresentingYouTubeAdBlockAnimation(tab: self)
            },
            onShouldShowAdBlockUnavailableDialog: { [weak self] in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard let self else { return }
                    // Re-check the URL after the delay so the dialog doesn't
                    // present if the user navigated away from a playable
                    // YouTube video during the 2-second wait.
                    guard self.webView.url?.isPlayableYoutubeVideoContent == true else { return }
                    self.delegate?.tabDidRequestYouTubeAdBlockUnavailableDialog(tab: self)
                }
            }
        )
    }()

    private lazy var duckPlayerNavigationHandler: DuckPlayerNavigationHandling = {
        let duckPlayer = DuckPlayer(settings: DuckPlayerSettingsDefault(),
                                    featureFlagger: AppDependencyProvider.shared.featureFlagger,
                                    userScriptsDependencies: userScriptsDependencies)

        if duckPlayer.settings.nativeUI {
            let handler = NativeDuckPlayerNavigationHandler(duckPlayer: duckPlayer,
                                         appSettings: appSettings,
                                         tabNavigationHandler: self)

            // Set up constraint handling if using native UI
            if let presenter = duckPlayer.nativeUIPresenter as? DuckPlayerNativeUIPresenter {
                setupDuckPlayerConstraintHandling(publisher: presenter.constraintUpdates)
            }

            return handler
        } else {
            return WebDuckPlayerNavigationHandler(duckPlayer: duckPlayer,
                                         appSettings: appSettings,
                                         tabNavigationHandler: self)
        }
    }()

    let contextualOnboardingPresenter: ContextualOnboardingPresenting
    let contextualOnboardingLogic: ContextualOnboardingLogic
    let onboardingPixelReporter: OnboardingCustomInteractionPixelReporting
    let textZoomCoordinator: TextZoomCoordinating
    let autoconsentManagement: AutoconsentManaging
    let fireproofing: Fireproofing
    let websiteDataManager: WebsiteDataManaging
    let specialErrorPageNavigationHandler: SpecialErrorPageManaging
    let featureDiscovery: FeatureDiscovery
    let productSurfaceTelemetry: ProductSurfaceTelemetry
    let keyValueStore: ThrowingKeyValueStoring
    let daxDialogsManager: DaxDialogsManaging
    let aiChatSettings: AIChatSettingsProvider
    let aiChatFullModeFeature: AIChatFullModeFeatureProviding
    let sharedSecureVault: (any AutofillSecureVault)?
    let privacyStats: PrivacyStatsProviding

    private(set) var aiChatContentHandler: AIChatContentHandling
    private(set) var voiceSearchHelper: VoiceSearchHelperProtocol
    let darkReaderFeatureSettings: DarkReaderFeatureSettings
    let autoplaySettings: AutoplaySettings
    let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?
    let duckAiFireModeStorageHandler: DuckAiNativeStorageHandling?
    lazy var aiChatContextualSheetCoordinator: AIChatContextualSheetCoordinator = {
        let pageContextHandler = AIChatPageContextHandler(
            webViewProvider: { [weak self] in self?.webView },
            userScriptProvider: { [weak self] in self?.userScripts?.pageContextUserScript },
            faviconProvider: { [weak self] url in self?.getFaviconBase64(for: url) }
        )
        let coordinator = AIChatContextualSheetCoordinator(
            voiceSearchHelper: voiceSearchHelper,
            aiChatSettings: aiChatSettings,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: featureDiscovery,
            featureFlagger: featureFlagger,
            unifiedToggleInputFeature: unifiedToggleInputFeature,
            pageContextHandler: pageContextHandler,
            tabURLPublishers: AIChatTabURLPublishers(originating: urlPublisher, didFinish: didFinishURLPublisher),
            isFireTab: tabModel.fireTab,
            duckAiNativeStorageHandler: duckAiNativeStorageHandler,
            duckAiFireModeStorageHandler: duckAiFireModeStorageHandler
        )
        coordinator.delegate = self
        return coordinator
    }()
    let subscriptionAIChatStateHandler: SubscriptionAIChatStateHandling

    init(tabModel: Tab,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         appSettings: AppSettings,
         bookmarksDatabase: CoreDataDatabase,
         historyManager: HistoryManaging,
         syncService: DDGSyncing,
         userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         certificateTrustEvaluator: CertificateTrustEvaluating = CertificateTrustEvaluator(),
         subscriptionDataReporter: SubscriptionDataReporting,
         contextualOnboardingPresenter: ContextualOnboardingPresenting,
         contextualOnboardingLogic: ContextualOnboardingLogic,
         onboardingPixelReporter: OnboardingCustomInteractionPixelReporting,
         urlCredentialCreator: URLCredentialCreating = URLCredentialCreator(),
         featureFlagger: FeatureFlagger,
         contentScopeExperimentManager: ContentScopeExperimentsManaging,
         textZoomCoordinator: TextZoomCoordinating,
         autoconsentManagement: AutoconsentManaging,
         fireproofing: Fireproofing,
         favicons: FaviconManaging,
         websiteDataManager: WebsiteDataManaging,
         tabInteractionStateSource: TabInteractionStateSource?,
         specialErrorPageNavigationHandler: SpecialErrorPageManaging,
         featureDiscovery: FeatureDiscovery,
         keyValueStore: ThrowingKeyValueStoring,
         daxDialogsManager: DaxDialogsManaging,
         adClickExternalOpenDetector: AdClickExternalOpenDetector = AdClickExternalOpenDetector(),
         aiChatSettings: AIChatSettingsProvider,
         productSurfaceTelemetry: ProductSurfaceTelemetry,
         aiChatFullModeFeature: AIChatFullModeFeatureProviding = AIChatFullModeFeature(),
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature(),
         sharedSecureVault: (any AutofillSecureVault)? = nil,
         privacyStats: PrivacyStatsProviding,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         darkReaderFeatureSettings: DarkReaderFeatureSettings,
         autoplaySettings: AutoplaySettings,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
         duckAiFireModeStorageHandler: DuckAiNativeStorageHandling? = nil,
         addressBarURLFilter: AddressBarURLFiltering = AddressBarURLFilter(),
         adBlockingAvailability: AdBlockingAvailabilityProviding) {

        self.tabModel = tabModel
        self.viewModel = TabViewModel(tab: tabModel, historyManager: historyManager)
        self.privacyConfigurationManager = privacyConfigurationManager
        self.appSettings = appSettings
        self.bookmarksDatabase = bookmarksDatabase
        self.historyManager = historyManager
        self.syncService = syncService
        self.userScriptsDependencies = userScriptsDependencies
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.certificateTrustEvaluator = certificateTrustEvaluator
        self.subscriptionDataReporter = subscriptionDataReporter
        self.contextualOnboardingPresenter = contextualOnboardingPresenter
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.onboardingPixelReporter = onboardingPixelReporter
        self.featureFlagger = featureFlagger
        self.contentScopeExperimentsManager = contentScopeExperimentManager
        self.textZoomCoordinator = textZoomCoordinator
        self.autoconsentManagement = autoconsentManagement
        self.fireproofing = fireproofing
        self.favicons = favicons
        self.websiteDataManager = websiteDataManager
        self.tabInteractionStateSource = tabInteractionStateSource
        self.specialErrorPageNavigationHandler = specialErrorPageNavigationHandler
        self.featureDiscovery = featureDiscovery
        self.keyValueStore = keyValueStore
        self.adClickExternalOpenDetector = adClickExternalOpenDetector
        self.daxDialogsManager = daxDialogsManager
        self.sharedSecureVault = sharedSecureVault
        self.privacyStats = privacyStats
        self.tabURLInterceptor = TabURLInterceptorDefault(featureFlagger: featureFlagger) {
            return AppDependencyProvider.shared.subscriptionManager.isSubscriptionPurchaseEligible
        }
        
        self.aiChatSettings = aiChatSettings
        self.aiChatFullModeFeature = aiChatFullModeFeature
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
        self.aiChatContentHandler = AIChatContentHandler(aiChatSettings: aiChatSettings,
                                                         featureDiscovery: featureDiscovery,
                                                         productSurfaceTelemetry: productSurfaceTelemetry,
                                                         unifiedToggleInputFeature: unifiedToggleInputFeature)
        self.subscriptionAIChatStateHandler = SubscriptionAIChatStateHandler()
        self.voiceSearchHelper = voiceSearchHelper
        self.darkReaderFeatureSettings = darkReaderFeatureSettings
        self.autoplaySettings = autoplaySettings
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
        self.duckAiFireModeStorageHandler = duckAiFireModeStorageHandler
        self.addressBarURLFilter = addressBarURLFilter
        self.adBlockingAvailability = adBlockingAvailability

        self.productSurfaceTelemetry = productSurfaceTelemetry

        super.init(nibName: nil, bundle: nil)

        // Reload AI Chat when subscription state changes
        subscriptionAIChatStateHandler.onSubscriptionStateChanged = { [weak self] in
            self?.reloadFullModeAIChatIfNeeded()
            self?.reloadContextualAIChatIfNeeded()
        }

        // Assign itself as tabNavigationHandler for DuckPlayer
        duckPlayerNavigationHandler.tabNavigationHandler = self

        // Assign itself as specialErrorPageNavigationDelegate for SpecialErrorPages
        specialErrorPageNavigationHandler.delegate  = self

        self.adClickExternalOpenDetector.mitigationHandler = { [weak self] in
            guard let self else { return }
            if self.tabModel.link?.title == nil {
                self.closeTab()
            } else if self.url != self.webView.url {
                self.url = self.webView.url
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func loadView() {
        configureRootView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Note: JSAlertView is intentionally NOT set up here. Instantiating its
        // UIVisualEffectView eagerly triggers a first-time CoreMaterial bundle
        // scan on the cold-launch critical path, which can trip the scene-create watchdog
        // (0x8BADF00D). It is now lazily created on first use via setupJSAlertViewIfNeeded().

        fireproofingWorker = FireproofingWorking(controller: self, fireproofing: fireproofing, favicons: favicons)
        initAttributionLogic()
        decorate()
        defaultErrorHeaderText = errorHeader.text ?? ""
        setupErrorActionButton()
        setupErrorReportBrokenSiteButton()
        addTextZoomObserver()

        subscribeToEmailProtectionSignOutNotification()
        registerForDownloadsNotifications()
        registerForAddressBarLocationNotifications()
        registerForAutofillNotifications()

        if #available(iOS 18.4, *) {
            registerForWebExtensionNotifications()
        }

        if #available(iOS 16.4, *) {
            registerForInspectableWebViewNotifications()
        }

        observeNetPConnectionStatusChanges()

        // Link DuckPlayer to current Tab
        duckPlayerNavigationHandler.setHostViewController(self)

        // Read tracker animation suppression flag from Tab model on first load
        // This ensures background tabs get the flag when they're loaded for the first time
        if tabModel.shouldSuppressTrackerAnimationOnFirstLoad {
            shouldSuppressTrackerAnimationOnFirstLoad = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForResignActive()
        registerForKeyboardNotifications()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        duckPlayerNavigationHandler.updateDuckPlayerForWebViewDisappearance(self)

        unregisterFromResignActive()
        unregisterFromKeyboardNotifications()
        tabInteractionStateSource?.saveState(webView.interactionState, for: tabModel)
    }

    private func registerForAddressBarLocationNotifications() {
        NotificationCenter.default.addObserver(self, selector:
                                                #selector(onAddressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
    }

    @available(iOS 18.4, *)
    private func registerForWebExtensionNotifications() {
        NotificationCenter.default
            .publisher(for: .webExtensionAutoconsentDashboardStateRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleWebExtensionDashboardStateRefresh(notification)
            }
            .store(in: &cancellables)
    }

    @available(iOS 18.4, *)
    private func handleWebExtensionDashboardStateRefresh(_ notification: Notification) {
        guard let url = notification.userInfo?[AutoconsentNotification.UserInfoKeys.url] as? URL,
              let consentStatus = notification.userInfo?[AutoconsentNotification.UserInfoKeys.consentStatus] as? ConsentStatusInfo else {
            return
        }

        privacyInfo?.updateCookieConsentManagedForWebExtensionDashboardState(url: url, consentStatus: consentStatus)
    }

    @available(iOS 16.4, *)
    private func registerForInspectableWebViewNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateWebViewInspectability),
                                               name: AppUserDefaults.Notifications.inspectableWebViewsToggled,
                                               object: nil)
    }

    @available(iOS 16.4, *) @objc
    private func updateWebViewInspectability() {
#if DEBUG
        webView.isInspectable = true
#else
        webView.isInspectable = AppUserDefaults().inspectableWebViewEnabled
#endif
    }

    @objc
    private func onAddressBarPositionChanged() {
        if FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled {
            borderView.isHidden = true
            borderView.isTopVisible = false
            borderView.isBottomVisible = false
        } else {
            borderView.isHidden = false
            borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        }
        updateWebViewBottomAnchor()
    }

    private func updateWebViewBottomAnchor() {
        updateWebViewBottomAnchor(for: 1.0)
    }

    func updateWebViewBottomAnchor(for barsVisibilityPercent: CGFloat) {
        let isUnifiedToggleInputAffectingBottomLayout = isAITab && unifiedToggleInputFeature.isAvailable
        if appSettings.currentAddressBarPosition == .bottom && !isUnifiedToggleInputAffectingBottomLayout {
            if chromeDelegate?.isInMinimalChromeLayout == true {
                // Minimal chrome: inset follows the bars so the slot is reclaimed when hidden. The
                // iOS 26 fixed inset is skipped; in landscape it leaves a visible gap once the bar
                // scrolls away (contentContainer is exactly the screen height).
                let targetHeight = chromeDelegate?.barsMaxHeight ?? 0.0
                webViewBottomAnchorConstraint?.constant = -targetHeight * barsVisibilityPercent
            } else {
                /// When address bar is at bottom on iPhone, offset webview to make room for the bars.
                /// AI tabs skip this inset only when unifiedToggleInput is active — that feature
                /// manages its own native bottom layout via the UnifiedToggleInput container.
                let targetHeight = chromeDelegate?.barsMaxHeight ?? 0.0
                let effectiveBarsVisibilityPercent: CGFloat
                if #available(iOS 26, *),
                   featureFlagger.isFeatureOn(.bottomBarViewportFixedElementsWorkaround) {
                    /// iOS 26 regressed fixed-bottom webpage elements when the browser continuously
                    /// resizes the webview's bottom inset while chrome hides/shows. Keep the inset
                    /// stable in bottom-address-bar mode to avoid pushing page-fixed footers offscreen.
                    effectiveBarsVisibilityPercent = 1.0
                } else {
                    effectiveBarsVisibilityPercent = barsVisibilityPercent
                }
                webViewBottomAnchorConstraint?.constant = -targetHeight * effectiveBarsVisibilityPercent
            }
        } else {
            webViewBottomAnchorConstraint?.constant = 0
        }
        if FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled {
            webViewBottomAnchorConstraint?.constant = 0
            borderView.bottomAlpha = 0
            borderView.isHidden = true
            borderView.isTopVisible = false
            borderView.isBottomVisible = false
            updateFloatingTopContentInset(for: barsVisibilityPercent)
        } else {
            borderView.isHidden = false
            borderView.bottomAlpha = AppWidthObserver.shared.isLargeWidth ? 0 : barsVisibilityPercent
        }
    }

    /// In floating top mode the web content spans the full height behind the glass omnibar. Inset
    /// the scroll view so content rests below the bar at rest and underflows it on scroll. The inset
    /// scales with `barsVisibilityPercent` so it collapses to zero in lock-step as the bar hides.
    private func updateFloatingTopContentInset(for barsVisibilityPercent: CGFloat) {
        let topInset: CGFloat
        // AI tabs with the unified toggle input manage their own top layout (the content container
        // stays anchored below the chrome), so adding a top inset there would double-offset.
        let isUnifiedToggleInputAffectingTopLayout = isAITab && unifiedToggleInputFeature.isAvailable
        if FloatingUILayoutPolicy.shouldApplyFloatingTopContentInset(
            isFloatingUIEnabled: true,
            addressBarPosition: appSettings.currentAddressBarPosition,
            isUnifiedToggleInputAffectingLayout: isUnifiedToggleInputAffectingTopLayout
        ) {
            let omniBarHeight = chromeDelegate?.omniBar.barView.expectedHeight ?? 0
            topInset = omniBarHeight * barsVisibilityPercent
        } else {
            topInset = 0
        }
        guard webView.scrollView.contentInset.top != topInset else { return }
        webView.scrollView.contentInset.top = topInset
        webView.scrollView.verticalScrollIndicatorInsets.top = topInset
    }

    private func observeNetPConnectionStatusChanges() {
        netPConnectionObserverCancellable = netPConnectionObserver.publisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.netPConnectionStatus, onWeaklyHeld: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The email manager is pulled from the main view controller, so reconnect it now, otherwise, it's nil
        userScripts?.autofillUserScript.emailDelegate = emailManager

        woShownRecently = false // don't fire if the user goes somewhere else first
        updateWebViewBottomAnchor()
        resetNavigationBar()
        delegate?.tabDidRequestShowingMenuHighlighter(tab: self)
        tabModel.viewed = true

        // Update DuckPlayer when WebView appears
        duckPlayerNavigationHandler.updateDuckPlayerForWebViewAppearance(self)

        checkWebViewVisibilityConsistency()
    }

    override func buildActivities() -> [UIActivity] {
        let viewModel = MenuBookmarksViewModel(bookmarksDatabase: bookmarksDatabase, syncService: syncService)
        viewModel.favoritesDisplayMode = appSettings.favoritesDisplayMode

        var activities: [UIActivity] = [SaveBookmarkActivity(controller: self,
                                                             viewModel: viewModel)]

        activities.append(SaveBookmarkActivity(controller: self,
                                               isFavorite: true,
                                               viewModel: viewModel))
        activities.append(FindInPageActivity(controller: self))

        return activities
    }
    
    func initAttributionLogic() {
        adClickAttributionLogic.delegate = self
        adClickAttributionDetection.delegate = adClickAttributionLogic
    }
    
    func updateTabModel() {
        if let url = url {
            let hasTitle = title != nil && !title!.isEmpty
            let previousTitle = (tabModel.link?.url == url) ? tabModel.link?.title : nil
            let link = Link(title: hasTitle ? title : previousTitle, url: url)
            tabModel.link = link
        } else {
            tabModel.link = nil
        }
    }
        
    @objc func onApplicationWillResignActive() {
        shouldReloadOnError = true

        tabInteractionStateSource?.saveState(webView.interactionState, for: tabModel)
    }
    
    func applyInheritedAttribution(_ attribution: AdClickAttributionLogic.State?) {
        adClickAttributionLogic.applyInheritedAttribution(state: attribution)
    }

    private func checkWebViewVisibilityConsistency() {
        if webView.isHidden && error.isHidden {
            DailyPixel.fireDailyAndCount(pixel: .debugWebViewInVisibleTabHidden)
            
            // Fix inconsistent state - if webView is hidden but no error shown, show webView
            // https://app.asana.com/1/137249556945/project/414709148257752/task/1210155968610460?focus=true
            hideErrorMessage()
        }
    }

    // The `consumeCookies` is legacy behaviour from the previous Fireproofing implementation. Cookies no longer need to be consumed after invocations
    // of the Fire button, but the app still does so in the event that previously persisted cookies have not yet been consumed.
    func attachWebView(configuration: WKWebViewConfiguration,
                       interactionStateData: Data? = nil,
                       andLoadRequest request: URLRequest?,
                       consumeCookies: Bool,
                       loadingInitiatedByParentTab: Bool = false,
                       customWebView: ((WKWebViewConfiguration) -> WKWebView)? = nil) {
        instrumentation.willPrepareWebView()

        let userContentController = UserContentController(assetsPublisher: contentBlockingAssetsPublisher,
                                                          privacyConfigurationManager: privacyConfigurationManager)
        configuration.userContentController = userContentController
        userContentController.delegate = self

        if let customWebView {
            webView = customWebView(configuration)
            view.layoutIfNeeded()
        } else {
            webView = WebView(frame: view.bounds, configuration: configuration)
        }
        if FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled {
            webView.scrollView.clipsToBounds = false
            webView.clipsToBounds = false
            outerContainer.clipsToBounds = false
        }
        textZoomCoordinator.onWebViewCreated(applyToWebView: webView)
        specialErrorPageNavigationHandler.attachWebView(webView)

        webView.allowsLinkPreview = true
        webView.allowsBackForwardNavigationGestures = true
        webView.preventFlashOnLoad()

        addObservers()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        webViewContainer.addSubview(webView)
        if FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled {
            webViewContainer.clipsToBounds = false
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webViewBottomAnchorConstraint = webView.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
            webViewBottomAnchorConstraint!,
            webView.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor)
        ])

        pullToRefreshViewAdapter = PullToRefreshViewAdapter(with: webView.scrollView,
                                                            pullableView: webViewContainer,
                                                            onRefresh: { [weak self] in
            self?.handlePullToRefresh()
        })

        if isAITab {
            pullToRefreshViewAdapter?.setRefreshControlEnabled(false)
            webView.scrollView.alwaysBounceVertical = false
            (webView as? WebView)?.setInputAccessoryViewHidden(true)
        }

        updateContentMode()

        if #available(iOS 16.4, *) {
            updateWebViewInspectability()
        }

        let didRestoreWebViewState = restoreInteractionStateToWebView(interactionStateData)

        instrumentation.didPrepareWebView()

        // Initialize DuckPlayerNavigationHandler
        if let webView = webView {
            duckPlayerNavigationHandler.handleAttach(webView: webView)
        }

        if consumeCookies {
            consumeCookiesThenLoadRequest(request)
        } else if !didRestoreWebViewState, let urlRequest = request {
            var loadingStopped = false
            linkProtection.getCleanURLRequest(from: urlRequest, onStartExtracting: { [weak self] in
                if loadingInitiatedByParentTab {
                    // stop parent-initiated URL loading only if canonical URL extraction process has started
                    loadingStopped = true
                    self?.webView.stopLoading()
                }
                self?.showProgressIndicator()
            }, onFinishExtracting: {}, completion: { [weak self] cleanURLRequest in
                // restart the cleaned-up URL loading here if:
                //   link protection provided an updated URL
                //   OR if loading was stopped for a popup loaded by its parent
                //   OR for any other navigation which is not a popup loaded by its parent
                // the check is here to let an (about:blank) popup which has its loading
                // initiated by its parent to keep its active request, otherwise we would
                // break a js-initiated popup request such as printing from a popup
                guard self?.url != cleanURLRequest.url || loadingStopped || !loadingInitiatedByParentTab else { return }
                self?.load(urlRequest: cleanURLRequest)

            })
        }

#if DEBUG
        webView.onDeinit { [weak self] in
            self?.assertObjectDeallocated(after: 4.0)
        }
        webView.configuration.processPool.onDeinit { [weak userContentController] in
            userContentController?.assertObjectDeallocated(after: 1.0)
        }
#endif

        borderView.insertSelf(into: webView)
        updateBorderViewForFloatingUIIfNeeded()
    }

    private func updateBorderViewForFloatingUIIfNeeded() {
        if FloatingUIManager(featureFlagger: featureFlagger).isFloatingUIEnabled {
            borderView.isHidden = true
            borderView.isTopVisible = false
            borderView.isBottomVisible = false
            borderView.bottomAlpha = 0
        } else {
            borderView.isHidden = false
            borderView.updateForAddressBarPosition(appSettings.currentAddressBarPosition)
        }
    }

    private func addObservers() {
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.isLoading), options: .new, context: nil)
    }

    private func configureRefreshControl(_ control: UIRefreshControl) {
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.handlePullToRefresh()
        }, for: .valueChanged)
        refreshControl.tintColor = .label
    }

    private func consumeCookiesThenLoadRequest(_ request: URLRequest?) {

        func doLoad() {
            if let request = request {
                load(urlRequest: request)
            }

            if request != nil {
                delegate?.tabLoadingStateDidChange(tab: self)
                onWebpageDidStartLoading(httpsForced: false)
            }
        }

        Task { @MainActor in
            await webView.configuration.websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            await websiteDataManager.consumeCookies(into: HTTPCookieStoreWrapper(wrapped: cookieStore))
            doLoad()
        }
    }

    public func executeBookmarklet(url: URL) {
        if let js = url.toDecodedBookmarklet() {
            webView.evaluateJavaScript(js)
        }
    }

    public func load(url: URL) {
        wasLoadingStoppedExternally = false
        addressBarURLFilter.beginUserNavigation()
        webView.stopLoading()
        dismissJSAlertIfNeeded()
        safariRedirectHandler.reset()
        shouldUseSafariOnlyUserAgentForNextMainFrameNavigation = false

        load(url: url, didUpgradeURL: false)
    }
    
    public func load(backForwardListItem: WKBackForwardListItem) {
        addressBarURLFilter.beginUserNavigation()
        webView.stopLoading()
        dismissJSAlertIfNeeded()

        updateContentMode()
        webView.go(to: backForwardListItem)
    }
    
    private func load(url: URL, didUpgradeURL: Bool) {
        if !didUpgradeURL {
            lastUpgradedURL = nil
            privacyInfo?.connectionUpgradedTo = nil
        }

        var url = url
        if let credential = url.basicAuthCredential {
            url = url.removingBasicAuthCredential()
            self.urlProvidedBasicAuthCredential = (credential, url)
        }

        if !url.isBookmarklet() {
            self.url = url
        }
        
        lastError = nil
        updateContentMode()
        linkProtection.getCleanURL(from: url,
                                   onStartExtracting: { showProgressIndicator() },
                                   onFinishExtracting: { },
                                   completion: { [weak self] url in
            self?.load(urlRequest: .userInitiated(url))
        })
    }

    func prepareForDataClearing() {
        httpsUpgradeTask?.cancel()
        httpsUpgradeTask = nil

        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        delegate = nil
        
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
    
    private func load(urlRequest: URLRequest) {
        loadViewIfNeeded()

        if let url = urlRequest.url, !shouldReissueSearch(for: url) {
            requeryLogic.onNewNavigation(url: url)
        }

        assert(urlRequest.attribution == .user, "WebView requests should be user attributed")

        refreshCountSinceLoad = 0

        webView.stopLoading()
        dismissJSAlertIfNeeded()
        webView.load(urlRequest)
    }
    
    // swiftlint:disable block_based_kvo
    open override func observeValue(forKeyPath keyPath: String?,
                                    of object: Any?,
                                    change: [NSKeyValueChangeKey: Any]?,
                                    context: UnsafeMutableRawPointer?) {
        // swiftlint:enable block_based_kvo

        guard let keyPath = keyPath,
              let webView = webView else { return }

        switch keyPath {

        case #keyPath(WKWebView.isLoading):
            if webView.isLoading, isTabCurrentlyPresented() {
                delegate?.showBars()
            }
            if #available(iOS 18.4, *) {
                notifyWebExtensionOfPropertyChange([.loading])
            }

        case #keyPath(WKWebView.estimatedProgress):
            if isTabCurrentlyPresented() {
                progressWorker.progressDidChange(webView.estimatedProgress)
            }

        case #keyPath(WKWebView.url):
            // A short delay is required here, because the URL takes some time
            // to propagate to the webView.url property accessor and might not
            // be immediately available in the observer
            let previousURL = self.url
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.webViewUrlHasChanged(previousURL: previousURL, newURL: self.webView.url)
                self.pullToRefreshViewAdapter?.setRefreshControlEnabled(!self.isAITab)
                self.webView.scrollView.alwaysBounceVertical = !self.isAITab
                (self.webView as? WebView)?.setInputAccessoryViewHidden(self.isAITab)
                if #available(iOS 18.4, *) {
                    self.notifyWebExtensionOfPropertyChange([.URL])
                }
            }

        case #keyPath(WKWebView.canGoBack):
            delegate?.tabLoadingStateDidChange(tab: self)

        case #keyPath(WKWebView.canGoForward):
            delegate?.tabLoadingStateDidChange(tab: self)

        case #keyPath(WKWebView.title):
            title = webView.title
            if #available(iOS 18.4, *) {
                notifyWebExtensionOfPropertyChange([.title])
            }
        default:
            Logger.general.debug("Unhandled keyPath \(keyPath)")
        }
    }
    
    func webViewUrlHasChanged(previousURL: URL? = nil, newURL: URL? = nil) {
        // Handle DuckPlayer Navigation URL changes
        if let currentURL = newURL ?? webView.url,
           shouldHandleUpdate(previousURL, newURL) {
            adBlockingNavigationHandler.handleURLChange(previousURL: previousURL, newURL: currentURL)
            _ = duckPlayerNavigationHandler.handleURLChange(webView: webView, previousURL: previousURL, newURL: currentURL, isNavigationError: lastError != nil)
        }

        guard let newURL = newURL else { return }

        if url == nil {
            url = newURL
        } else if addressBarURLFilter.shouldUpdate(for: newURL) {
            url = newURL
        }
    }

    @available(iOS 18.4, *)
    private func notifyWebExtensionOfPropertyChange(_ properties: WKWebExtension.TabChangedProperties) {
        (delegate as? MainViewController)?.webExtensionEventsCoordinator?.didChangeTabProperties(properties, for: self)
    }

    func enableFireproofingForDomain(_ domain: String) {
        let displayDomain = fireproofing.displayDomain(for: domain)
        FireproofingAlert.showConfirmFireproofWebsite(usingController: self, forDomain: displayDomain) { [weak self] in
            Pixel.fire(pixel: .browsingMenuFireproof)
            self?.fireproofingWorker?.handleUserEnablingFireproofing(forDomain: domain)
        }
    }
    
    func disableFireproofingForDomain(_ domain: String) {
        fireproofingWorker?.handleUserDisablingFireproofing(forDomain: domain)
    }

    func dismissContextualDaxFireDialog() {
        guard contextualOnboardingLogic.isShowingFireDialog else { return }
        dismissContextualOnboardingIfNeeded()
    }

    func presentDuckAIOnboardingFireDialog() {
        contextualOnboardingLogic.setLastShownDialog(type: .fire(.duckAIOnboarding))
        let fireSpec = DaxDialogs.BrowsingSpec.fireDuckAIOnboarding
        presentContextualOnboarding(for: fireSpec)
    }

    private func presentContextualOnboarding(for spec: DaxDialogs.BrowsingSpec) {
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(true)
        contextualOnboardingPresenter.presentContextualOnboarding(for: spec, in: self)
    }

    private func dismissContextualOnboardingIfNeeded() {
        contextualOnboardingPresenter.dismissContextualOnboardingIfNeeded(from: self)
        chromeDelegate?.setUnifiedInputContentOverlaySuppressed(false)
    }

    private func shouldHandleUpdate(_ previousURL: URL?, _ newURL: URL?) -> Bool {
        guard let previousURL, let newURL,
              previousURL.isYoutube,
              newURL.isYoutube,
              previousURL.youtubeVideoID == newURL.youtubeVideoID,
              newURL.getParameter(named: "ra") != nil
        else { return true }

        return previousURL != newURL.removingParameters(named: ["ra"])
    }

    private func checkForReloadOnError() {
        guard shouldReloadOnError else { return }
        shouldReloadOnError = false
        reload()
    }
    
    private func shouldReissueDDGStaticNavigation(for url: URL) -> Bool {
        guard url.isDuckDuckGoStatic else { return false }
        return !url.hasCorrectSearchHeaderParams
    }
    
    private func reissueNavigationWithSearchHeaderParams(for url: URL) {
        load(url: url.applyingSearchHeaderParams())
    }
    
    private func shouldReissueSearch(for url: URL) -> Bool {
        guard url.isDuckDuckGoSearch else { return false }
        
        var shouldReissue = !url.hasCorrectMobileStatsParams || !url.hasCorrectSearchHeaderParams
        let isAIChatEnabled = delegate?.isAIChatEnabled ?? true
        shouldReissue = shouldReissue || !url.hasCorrectDuckAIParams(isDuckAIEnabled: isAIChatEnabled)
        return shouldReissue
    }

    private func reissueSearchWithRequiredParams(for url: URL) {
        var mobileSearch = url.applyingStatsParams()
        let isAIChatEnabled = delegate?.isAIChatEnabled ?? true
        mobileSearch = mobileSearch.applyingDuckAIParams(isAIChatEnabled: isAIChatEnabled)

        reissueNavigationWithSearchHeaderParams(for: mobileSearch)
    }

    private func showProgressIndicator() {
        progressWorker.didStartLoading()
    }

    private func handlePullToRefresh() {
        reload()
        delegate?.tabDidRequestRefresh(tab: self)
        Pixel.fire(pixel: .pullToRefresh)
        if let url = webView.url {
            AppDependencyProvider.shared.pageRefreshMonitor.register(for: url)
        }
    }

    private func hideProgressIndicator() {
        progressWorker.didFinishLoading()
        webView.scrollView.refreshControl?.endRefreshing()
        pullToRefreshViewAdapter?.endRefreshing()
    }

    public func reload() {
        safariRedirectHandler.reset()
        wasLoadingStoppedExternally = false
        addressBarURLFilter.beginUserReload()
        updateContentMode()
        cachedRuntimeConfigurationForDomain = [:]
        adBlockingNavigationHandler.handleReload()
        duckPlayerNavigationHandler.handleReload(webView: webView)
        delegate?.tabLoadingStateDidChange(tab: self)
        resetCreditCardPrompt()
    }
    
    func updateContentMode() {
        webView.configuration.defaultWebpagePreferences.preferredContentMode = tabModel.isDesktop ? .desktop : .mobile
    }

    func goBack() {
        addressBarURLFilter.beginUserNavigation()
        dismissJSAlertIfNeeded()

        // Clear navigation error when going back
        lastError = nil
        
        if let url = url, url.isDuckPlayer {
            webView.stopLoading()
            if webView.canGoBack {
                duckPlayerNavigationHandler.handleGoBack(webView: webView)
                webView.goBack()
                chromeDelegate?.omniBar.endEditing()
                return
            }
            if openingTab != nil {
                delegate?.tabDidRequestClose(self)
                return
            }
        }

        if isError {
            hideErrorMessage()
            if let url = webView.url, safariRedirectHandler.isAfterSuppressedXSafariRedirect(for: url), webView.canGoBack {
                webView.goBack()
            }
            url = webView.url
            onWebpageDidStartLoading(httpsForced: false)
            onWebpageDidFinishLoading()
            return
        }
        
        if webView.canGoBack {
            webView.goBack()
            duckPlayerNavigationHandler.handleGoBack(webView: webView)
            chromeDelegate?.omniBar.endEditing()
            return
        }

        if openingTab != nil {
            delegate?.tabDidRequestClose(self)
        }
        
    }
    
    func goForward() {
        addressBarURLFilter.beginUserNavigation()
        dismissJSAlertIfNeeded()

        // Clear navigation error when going forward
        lastError = nil

        if webView.goForward() != nil {
            duckPlayerNavigationHandler.handleGoForward(webView: webView)
            chromeDelegate?.omniBar.endEditing()
        }
    }
    
    private func showError(message: String) {
        webView.isHidden = true
        error.isHidden = false
        setErrorInfoImage()
        errorHeader.text = defaultErrorHeaderText
        errorMessage.text = formattedErrorMessage(message)
        errorActionButton.isHidden = true
        errorReportBrokenSiteButton.isHidden = true
        safariRedirectLoopErrorURL = nil
        error.layoutIfNeeded()
    }

    private func formattedErrorMessage(_ message: String) -> String {
        // The English NSURLErrorCannotFindHost description wraps awkwardly; break it after
        // "hostname" so it reads as two balanced lines.
        return message.replacingOccurrences(
            of: "A server with the specified hostname could not be found",
            with: "A server with the specified hostname\ncould not be found"
        )
    }

    private func hideErrorMessage() {
        error.isHidden = true
        webView.isHidden = false
        setErrorInfoImage()
        errorHeader.text = defaultErrorHeaderText
        errorActionButton.isHidden = true
        errorReportBrokenSiteButton.isHidden = true
        safariRedirectLoopErrorURL = nil
    }

    private func showSafariRedirectLoopError(for url: URL) {
        safariRedirectLoopErrorURL = url
        webView.isHidden = true
        error.isHidden = false
        setErrorInfoImage(resource: .shieldAlert96)
        errorHeader.text = UserText.generalPageProblemTitle
        errorMessage.text = UserText.generalPageProblemMessage
        errorActionButton.setTitle(UserText.generalPageProblemOpenInBrowserButton, for: .normal)
        errorActionButton.isHidden = false
        errorReportBrokenSiteButton.setTitle(UserText.actionReportBrokenSite, for: .normal)
        errorReportBrokenSiteButton.isHidden = false
        error.layoutIfNeeded()
        webpageDidFailToLoad()
    }

    private func setErrorInfoImage(resource: ImageResource = AppRebrand.isAppRebranded() ? .daxAccident : .daxAccidentLegacy) {
        errorInfoImage.image = UIImage(resource: resource)
        errorInfoImage.isHidden = false
    }

    private func isDuckDuckGoUrl() -> Bool {
        guard let url = url else { return false }
        return url.isDuckDuckGo
    }

    var jsAlertView: JSAlertView!

    private func addTextZoomObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onTextZoomChange),
                                               name: AppUserDefaults.Notifications.textZoomChange,
                                               object: nil)
    }


    private func subscribeToEmailProtectionSignOutNotification() {
        emailProtectionSignOutCancellable = NotificationCenter.default.publisher(for: .emailDidSignOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onDuckDuckGoEmailSignOut(notification)
            }
    }

    @objc func onTextZoomChange() {
        textZoomCoordinator.onTextZoomChange(applyToWebView: webView)
    }

    @objc func onDuckDuckGoEmailSignOut(_ notification: Notification) {
        guard let url = webView.url else { return }
        if url.isDuckDuckGoEmailProtection {
            webView.evaluateJavaScript("window.postMessage({ emailProtectionSignedOut: true }, window.origin);")
        }
    }

    private func resetNavigationBar() {
        chromeDelegate?.setNavigationBarHidden(false)
    }

    @IBAction func onBottomOfScreenTapped(_ sender: UITapGestureRecognizer) {
        showBars()
    }

    private func showBars(animated: Bool = true) {
        // resetBars syncs BarsAnimator's state; setBarsHidden alone leaves it stale and the chrome can stick hidden.
        chromeDelegate?.resetBars(animated: animated)
    }

    private func hideBars(animated: Bool = true) {
        chromeDelegate?.setBarsHidden(true, animated: animated, customAnimationDuration: nil)
    }

    func showPrivacyDashboard() {
        Pixel.fire(pixel: .privacyDashboardOpened, withAdditionalParameters: featureDiscovery.addToParams([:], forFeature: .privacyDashboard))
        let webExtManager = (delegate as? MainViewController)?.webExtensionManager
        let controller = PrivacyDashboardViewController(
            privacyInfo: privacyInfo,
            entryPoint: .dashboard,
            privacyConfigurationManager: privacyConfigurationManager,
            contentBlockingManager: ContentBlocking.shared.contentBlockingManager,
            breakageAdditionalInfo: makeBreakageAdditionalInfo(webExtensionManager: webExtManager))

        guard let chromeDelegate = chromeDelegate else { return }

        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.preferredContentSize = .init(width: 375, height: 650)
            controller.modalPresentationStyle = .popover
        } else {
            controller.modalPresentationStyle = .formSheet
        }
        present(controller: controller, fromView: chromeDelegate.omniBar.barView.privacyIconView  ?? privacyDashboardAnchor)
        self.privacyDashboard = controller

        featureDiscovery.setWasUsedBefore(.privacyDashboard)
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        pullToRefreshViewAdapter?.setRefreshControlEnabled(isEnabled)
    }

    private var didGoBackForward: Bool = false {
        didSet {
            if didGoBackForward {
                dismissContextualOnboardingIfNeeded()
            }
        }
    }

    private lazy var navigationPixelResponder = NavigationPixelNavigationResponder(
        isErrorPageReload: { [weak self] navigationAction in
            // Keyed on URL — not just `isSpecialErrorPageVisible` — so the "error page reload" gate
            // only catches reload-like `.other` navs the error page issues against the same URL, not a
            // user-typed URL (or back/forward) initiated from the error page, which targets a different
            // URL and represents a real navigation we want to measure.
            guard let self,
                  self.specialErrorPageNavigationHandler.isSpecialErrorPageVisible,
                  let failedURL = self.specialErrorPageNavigationHandler.failedURL else {
                return false
            }
            return navigationAction.request.url == failedURL
        },
        isLoadingErrorPage: { [weak self] navigationAction in
            // Keyed on URL — not just the flag — so an unrelated main-frame nav (back/forward, URL bar)
            // initiated while the simulated error-page request is in flight isn't also dropped. The
            // simulated request always uses `failedURL` (set alongside `isSpecialErrorPageRequest`).
            guard let self,
                  self.specialErrorPageNavigationHandler.isSpecialErrorPageRequest,
                  let failedURL = self.specialErrorPageNavigationHandler.failedURL else {
                return false
            }
            return navigationAction.request.url == failedURL
        }
    )

    private func resetDashboardInfo() {
        if let url = url {
            if didGoBackForward, let privacyInfo = previousPrivacyInfosByURL[url] {
                self.privacyInfo = privacyInfo
                didGoBackForward = false
            } else {
                privacyInfo = makePrivacyInfo(url: url, shouldCheckServerTrust: true)
            }
        } else {
            privacyInfo = nil
        }
        onPrivacyInfoChanged()
    }
    
    public func makePrivacyInfo(url: URL, shouldCheckServerTrust: Bool = false) -> PrivacyInfo? {
        guard let host = url.host else { return nil }
        
        let entity = ContentBlocking.shared.trackerDataManager.trackerData.findParentEntityOrFallback(forHost: host)

        let privacyInfo = PrivacyInfo(url: url,
                                      parentEntity: entity,
                                      protectionStatus: makeProtectionStatus(for: host),
                                      malicousSiteThreatKind: specialErrorPageNavigationHandler.currentThreatKind,
                                      shouldCheckServerTrust: shouldCheckServerTrust,
                                      allActiveContentScopeExperiments: contentScopeExperimentsManager.allActiveContentScopeExperiments)
        privacyInfo.cookieConsentManaged = CookieConsentInfo.initialCPMDiagnostics
        let isCertificateInvalid = certificateTrustEvaluator
            .evaluateCertificateTrust(trust: webView.serverTrust)
            .map { !$0 }
        let serverTrustEvaluation = ServerTrustEvaluation(securityTrust: webView.serverTrust, isCertificateInvalid: isCertificateInvalid)
        privacyInfo.serverTrustEvaluation = serverTrustEvaluation
        privacyInfo.isSpecialErrorPageVisible = specialErrorPageNavigationHandler.isSpecialErrorPageVisible

        previousPrivacyInfosByURL[url] = privacyInfo
        
        return privacyInfo
    }
    
    private func makeProtectionStatus(for host: String) -> ProtectionStatus {
        let config = privacyConfigurationManager.privacyConfig
        
        let isTempUnprotected = config.isTempUnprotected(domain: host)
        let isAllowlisted = config.isUserUnprotected(domain: host)
        
        var enabledFeatures: [String] = []
        
        if !config.isInExceptionList(domain: host, forFeature: .contentBlocking) {
            enabledFeatures.append(PrivacyFeature.contentBlocking.rawValue)
        }
        
        return ProtectionStatus(unprotectedTemporary: isTempUnprotected,
                                enabledFeatures: enabledFeatures,
                                allowlisted: isAllowlisted,
                                denylisted: false)
    }
 
    private func onPrivacyInfoChanged() {
        delegate?.tab(self, didChangePrivacyInfo: privacyInfo)
        privacyDashboard?.updatePrivacyInfo(privacyInfo)
    }
    
    func didLaunchBrowsingMenu() {
        daxDialogsManager.resumeRegularFlow()
    }

    private func openExternally(url: URL) {
        self.url = webView.url
        delegate?.tabLoadingStateDidChange(tab: self)
        UIApplication.shared.open(url) { opened in
            if !opened {
                let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
                ActionMessageView.present(message: UserText.failedToOpenExternally,
                                          presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom))
            }

            // just showing a blank tab at this point, so close it
            if self.webView.url == nil {
                self.delegate?.tabDidRequestClose(self)
            }
        }
    }
    
    func presentOpenInExternalAppAlert(url: URL) {
        if safariRedirectHandler.isAfterSuppressedXSafariRedirect(for: url) { return }

        let title = UserText.customUrlSchemeTitle
        let message = UserText.customUrlSchemeMessage
        let open = UserText.customUrlSchemeOpen
        let dontOpen = UserText.customUrlSchemeDontOpen

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: dontOpen, style: .cancel, handler: { _ in
            if self.webView.url == nil {
                self.delegate?.tabDidRequestClose(self)
            } else {
                self.url = self.webView.url
            }
        }))
        alert.addAction(UIAlertAction(title: open, style: .destructive, handler: { _ in
            self.openExternally(url: url)
        }))
        delegate?.tab(self, didRequestPresentingAlert: alert)
    }

    func dismiss() {
        privacyDashboard?.dismiss(animated: true)
        progressWorker.progressBar = nil
        chromeDelegate?.omniBar.cancelAllAnimations()
        cancelTrackerNetworksAnimation()
        willMove(toParent: nil)
        removeFromParent()
        view.removeFromSuperview()
    }

    private func removeObservers() {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.title))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
    }

    public func makeBreakageAdditionalInfo(webExtensionManager: WebExtensionManaging? = nil) -> PrivacyDashboardViewController.BreakageAdditionalInfo? {

        guard let currentURL = url else {
            return nil
        }

        var loadedWebExtensions: String?
        var adBlockingScriptletsVersion: String?
        var cpmExtensionLoaded = false
        var cpmExtensionDroppedCallbacks = 0
        if #available(iOS 18.4, *), let webExtensionManager {
            loadedWebExtensions = webExtensionManager.loadedWebExtensionsString()
            adBlockingScriptletsVersion = webExtensionManager.adBlockingScriptletsVersion()
            cpmExtensionLoaded = webExtensionManager.isAutoconsentExtensionLoaded
            cpmExtensionDroppedCallbacks = webExtensionManager.eventsListener.droppedCallbacksCount
        }

        return PrivacyDashboardViewController.BreakageAdditionalInfo(currentURL: currentURL,
                                                                     httpsForced: httpsForced,
                                                                     ampURLString: linkProtection.lastAMPURLString ?? "",
                                                                     urlParametersRemoved: linkProtection.urlParametersRemoved,
                                                                     isDesktop: tabModel.isDesktop,
                                                                     error: lastError,
                                                                     httpStatusCode: lastHttpStatusCode,
                                                                     openerContext: inferredOpenerContext,
                                                                     vpnOn: netPConnected,
                                                                     userRefreshCount: refreshCountSinceLoad,
                                                                     breakageReportingSubfeature: breakageReportingSubfeature,
                                                                     isForceDarkModeEnabled: darkReaderFeatureSettings.isForceDarkModeEnabled,
                                                                     autoplayBlockingMode: autoplaySettings.currentAutoplayBlockingMode.rawValue,
                                                                     isAfterSuppressedXSafariRedirect: safariRedirectHandler.isAfterSuppressedXSafariRedirect(for: currentURL),
                                                                     loadedWebExtensions: loadedWebExtensions,
                                                                     adBlockingExtensionScriptletsVersion: adBlockingScriptletsVersion,
                                                                     cpmExtensionLoaded: cpmExtensionLoaded,
                                                                     cpmExtensionDroppedCallbacks: cpmExtensionDroppedCallbacks)
    }

    public func print() {
        let printFormatter = webView.viewPrintFormatter()

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = Bundle.main.infoDictionary!["CFBundleName"] as? String ?? "DuckDuckGo"
        printInfo.outputType = .general
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printFormatter = printFormatter
        printController.present(animated: true, completionHandler: nil)
    }
    
    func onCopyAction(forUrl url: URL) {
        let copyText: String
        if url.isDuckDuckGo {
            let cleanURL = url.removingInternalSearchParameters()
            copyText = cleanURL.absoluteString
        } else {
            copyText = url.absoluteString
        }
        
        onCopyAction(for: copyText)
    }
    
    func onCopyAction(for text: String) {
        UIPasteboard.general.string = text
    }

    func stopLoading() {
        webView.stopLoading()
        wasLoadingStoppedExternally = true

        hideProgressIndicator()
        delegate?.tabLoadingStateDidChange(tab: self)
    }

    private func cleanUpBeforeClosing() {
        let job = { [weak webView, userContentController] in
            userContentController.cleanUpBeforeClosing()

            webView?.assertObjectDeallocated(after: 4.0)
        }
        guard Thread.isMainThread else {
            DispatchQueue.main.async(execute: job)
            return
        }
        job()
    }

    deinit {
        rulesCompilationMonitor.tabWillClose(tabModel.uid)
        removeObservers()
        temporaryDownloadForPreviewedFile?.cancel()
        cleanUpBeforeClosing()
    }

    private var cancellables = Set<AnyCancellable>()
}

// MARK: - LoginFormDetectionDelegate
extension TabViewController: LoginFormDetectionDelegate {
    
    func loginFormDetectionUserScriptDetectedLoginForm(_ script: LoginFormDetectionUserScript) {
        detectedLoginURL = webView.url
    }
    
}

// MARK: - WKNavigationDelegate
extension TabViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            performHTTPAuthentication(protectionSpace: challenge.protectionSpace, completionHandler: completionHandler)

        case NSURLAuthenticationMethodServerTrust:
            // Handle SSL challenge and present Special Error page if issues with SSL certificates are detected
            specialErrorPageNavigationHandler.handleWebView(webView, didReceive: challenge, completionHandler: completionHandler)

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func performHTTPAuthentication(protectionSpace: URLProtectionSpace,
                                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let urlProvidedBasicAuthCredential,
           urlProvidedBasicAuthCredential.url.matches(protectionSpace) {

            completionHandler(.useCredential, urlProvidedBasicAuthCredential.credential)
            self.urlProvidedBasicAuthCredential = nil
            return
        }

        // Update the address bar instantly when page presents a dialog to prevent spoofing attacks
        // https://app.asana.com/0/414709148257752/1208060693227754/f
        self.url = webView.url
        let isHttps = protectionSpace.protocol == "https"
        let alert = BasicAuthenticationAlert(host: protectionSpace.host,
                                             isEncrypted: isHttps,
                                             logInCompletion: { (login, password) in
            completionHandler(.useCredential, URLCredential(user: login, password: password, persistence: .forSession))
        }, cancelCompletion: {
            completionHandler(.rejectProtectionSpace, nil)
        })

        delegate?.tab(self, didRequestPresentingAlert: alert)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url {
            let finalURL = duckPlayerNavigationHandler.getDuckURLFor(url)
            viewModel.captureWebviewDidCommit(finalURL)
            instrumentation.willLoad(url: url)
        }

        addressBarURLFilter.commitNavigation(for: webView.url)

        url = webView.url
        let tld = storageCache.tld
        let httpsForced = tld.domain(lastUpgradedURL?.host) == tld.domain(webView.url?.host)
        onWebpageDidStartLoading(httpsForced: httpsForced)
        textZoomCoordinator.onNavigationCommitted(applyToWebView: webView)
        
        // Check cache for instant logo display during back navigation
        checkDaxEasterEggCacheIfDuckDuckGoSearch(webView)

    }

    private func onWebpageDidStartLoading(httpsForced: Bool) {
        Logger.general.debug("webpageLoading started")

        // Only fire when on the same page that the without trackers Dax Dialog was shown
        self.fireWoFollowUp = false

        self.httpsForced = httpsForced

        resetDashboardInfo()

        tabModel.link = link
        delegate?.tabLoadingStateDidChange(tab: self)

        appRatingPrompt.registerUsage()

        if let scene = self.view.window?.windowScene,
           webView.url?.isDuckDuckGoSearch == true,
           appRatingPrompt.shouldPrompt() {
            SKStoreReviewController.requestReview(in: scene)
            appRatingPrompt.shown()
        }
        
        duckPlayerNavigationHandler.handleDidStartLoading(webView: webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let httpResponse = navigationResponse.response as? HTTPURLResponse
        let didMarkAsInternal = internalUserDecider.markUserAsInternalIfNeeded(forUrl: webView.url, response: httpResponse)
        if didMarkAsInternal {
            Pixel.fire(pixel: .featureFlaggingInternalUserAuthenticated)
            NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.didVerifyInternalUser))
        }

        // If the navigation has been handled by the special error page handler, cancel navigating to the new content as the special error page will be shown.
        if !specialErrorPageNavigationHandler.isSpecialErrorPageRequest, await specialErrorPageNavigationHandler.handleDecidePolicy(for: navigationResponse, webView: webView) {
            return .cancel
        } else {
            return await handleNavigationResponse(navigationResponse)
        }
    }

    private func handleNavigationResponse(_ navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let httpResponse = navigationResponse.response as? HTTPURLResponse
        let mimeType = MIMEType(from: navigationResponse.response.mimeType, fileExtension: navigationResponse.response.url?.pathExtension)
        let urlSchemeType = navigationResponse.response.url.map { SchemeHandler.schemeType(for: $0) } ?? .unknown
        let urlNavigationalScheme = navigationResponse.response.url?.scheme.map { URL.NavigationalScheme(rawValue: $0) }

        let isSuccessfulResponse = httpResponse?.isSuccessfulResponse ?? false
        lastHttpStatusCode = httpResponse?.statusCode

        let shape = NavigationResponseRouter.ResponseShape(
            url: navigationResponse.response.url,
            mimeType: mimeType,
            canShowMIMEType: navigationResponse.canShowMIMEType,
            suggestedFilename: navigationResponse.response.suggestedFilename,
            isContentDispositionAttachment: httpResponse?.shouldDownload ?? false,
            didNavigationActionRequestDownload: recentNavigationActionShouldPerformDownloadURL != nil
                && recentNavigationActionShouldPerformDownloadURL == navigationResponse.response.url,
            urlSchemeType: urlSchemeType,
            urlNavigationalScheme: urlNavigationalScheme,
            hasTemporaryBlobDownload: temporaryDownloadForPreviewedFile?.url == navigationResponse.response.url
        )
        let router = NavigationResponseRouter(featureFlagger: featureFlagger)

        switch router.decide(for: shape) {
        case .blobAllow:
            blobDownloadTargetFrame = nil
            return .allow

        case .blobDownload:
            return .download

        case .autoPreviewPersist:
            // Legacy URLSession path. ICS persists to Downloads. Transient types fall here when the
            // walletPassDownload failsafe is off.
            let (policy, download) = await startDownload(with: navigationResponse)
            mostRecentAutoPreviewDownloadID = download?.id
            return policy

        case .autoPreviewTransient:
            // Modern WKDownload path. The didBecome download: handler picks up the response and routes
            // it through transfer() with isTemporary: true, preserving POST and session state.
            return .download

        case .dataSchemeDownload:
            return .download

        case .userPromptDownload:
            guard let downloadMetadata = try? AppDependencyProvider.shared.downloadManager.downloadMetaData(for: navigationResponse.response) else {
                // Preserve pre-extraction behavior: if metadata cannot be built, fall through to the
                // webViewPreview branch when canShowMIMEType, otherwise allow.
                if navigationResponse.canShowMIMEType {
                    return await handleWebViewPreviewBranch(navigationResponse, isSuccessfulResponse: isSuccessfulResponse)
                }
                return .allow
            }
            switch await presentSaveToDownloadsAlert(with: downloadMetadata) {
            case .success:
                let (policy, _) = await startDownload(with: navigationResponse)
                return policy
            case .cancelled:
                return .cancel
            }

        case .webViewPreview:
            return await handleWebViewPreviewBranch(navigationResponse, isSuccessfulResponse: isSuccessfulResponse)

        case .allowDefault:
            return .allow
        }
    }

    private func handleWebViewPreviewBranch(_ navigationResponse: WKNavigationResponse, isSuccessfulResponse: Bool) async -> WKNavigationResponsePolicy {
        url = webView.url
        if navigationResponse.isForMainFrame, let decision = setupOrClearTemporaryDownload(for: navigationResponse.response) {
            return decision
        }
        if navigationResponse.isForMainFrame && isSuccessfulResponse {
            adClickAttributionDetection.on2XXResponse(url: url)
        }
        await adClickAttributionLogic.onProvisionalNavigation()
        return .allow
    }

    private func shouldTriggerDownloadAction(for navigationResponse: WKNavigationResponse) -> Bool {
        let mimeType = MIMEType(from: navigationResponse.response.mimeType, fileExtension: navigationResponse.response.url?.pathExtension)
        let httpResponse = navigationResponse.response as? HTTPURLResponse

        // HTTP response has "Content-Disposition: attachment" header
        let hasContentDispositionAttachment = httpResponse?.shouldDownload ?? false

        // If preceding WKNavigationAction requested to start the download (e.g. link `download` attribute or BLOB object)
        let hasNavigationActionRequestedDownload = (recentNavigationActionShouldPerformDownloadURL != nil) && recentNavigationActionShouldPerformDownloadURL == navigationResponse.response.url

        // File can be rendered by web view or in custom preview handled by FilePreviewHelper
        let canLoadOrPreviewTheFile = navigationResponse.canShowMIMEType || FilePreviewHelper.canAutoPreviewMIMEType(mimeType)

        return hasContentDispositionAttachment || hasNavigationActionRequestedDownload || !canLoadOrPreviewTheFile
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationPixelResponder.didStart(navigation)
        lastError = nil
        lastRenderedURL = webView.url
        cancelTrackerNetworksAnimation()
        shouldReloadOnError = false
        hideErrorMessage()
        showProgressIndicator()
        linkProtection.cancelOngoingExtraction()
        linkProtection.setMainFrameUrl(webView.url)
        referrerTrimming.onBeginNavigation(to: webView.url)
        adClickAttributionDetection.onStartNavigation(url: webView.url)
        adClickExternalOpenDetector.startNavigation()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationPixelResponder.didFinish(navigation)
        self.preventUniversalLinksOnce = false
        self.currentlyLoadedURL = webView.url
        didFinishURLSubject.send(webView.url)
        onTextZoomChange()
        adClickAttributionDetection.onDidFinishNavigation(url: webView.url)
        adClickExternalOpenDetector.finishNavigation()
        adClickAttributionLogic.onDidFinishNavigation(host: webView.url?.host)
        hideProgressIndicator()
        onWebpageDidFinishLoading()
        adBlockingNavigationHandler.handleURLChange(previousURL: nil, newURL: webView.url)
        extractDaxEasterEggLogoIfDuckDuckGoSearch(webView)
        instrumentation.didLoadURL()
        checkLoginDetectionAfterNavigation()
        trackSecondSiteVisitIfNeeded(url: webView.url)

        fireProductTelemetry(for: webView)
        
        // definitely finished with any potential login cycle by this point, so don't try and handle it any more
        detectedLoginURL = nil
        updatePreview()
        linkProtection.setMainFrameUrl(nil)
        referrerTrimming.onFinishNavigation()
        urlProvidedBasicAuthCredential = nil

        if webView.url?.isDuckDuckGoSearch == true, case .connected = netPConnectionStatus {
            DailyPixel.fireDailyAndCount(pixel: .networkProtectionEnabledOnSearch,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes)
        }

        // Notify Special Error Page Navigation handler that webview successfully finished loading
        specialErrorPageNavigationHandler.handleWebView(webView, didFinish: navigation)
    }

    /// Fires product telemetry related to the current URL
    private func fireProductTelemetry(for webView: WKWebView) {
        guard let url = webView.url else { return }

        if url.isDuckAIURL {
            aiChatContentHandler.fireAIChatTelemetry()
        } else {
            productSurfaceTelemetry.navigationCompleted(url: webView.url)
        }
    }

    var specialErrorPageUserScript: SpecialErrorPageUserScript? {
        get {
            return storedSpecialErrorPageUserScript ?? userScripts?.specialErrorPageUserScript
        }
        set {
            storedSpecialErrorPageUserScript = newValue
        }
    }

    func preparePreview(completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView,
                  webView.bounds.height > 0 && webView.bounds.width > 0 else { completion(nil); return }
            
            let size = CGSize(width: webView.frame.size.width,
                              height: webView.frame.size.height - webView.scrollView.contentInset.top - webView.scrollView.contentInset.bottom)
            
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                context.cgContext.translateBy(x: 0, y: -webView.scrollView.contentInset.top)
                webView.drawHierarchy(in: webView.bounds, afterScreenUpdates: true)
                if let jsAlertView = self?.jsAlertView {
                    jsAlertView.drawHierarchy(in: jsAlertView.bounds, afterScreenUpdates: false)
                }
            }

            completion(image)
        }
    }

    private func updatePreview() {
        guard isTabCurrentlyPresented() else { return }

        preparePreview { image in
            if let image = image {
                self.delegate?.tab(self, didUpdatePreview: image)
            }
        }
    }
    
    private func onWebpageDidFinishLoading() {
        Logger.general.debug("webpageLoading finished")

        // Flash prevention sets this false, but that breaks some websites.
        webView?.isOpaque = true

        tabModel.link = link
        delegate?.tabLoadingStateDidChange(tab: self)
        delegate?.tabDidFinishNavigation(self)

        // Present the Dax dialog with a delay to mitigate issue where user script detec trackers after the dialog is show to the user
        // Debounce to avoid showing multiple animations on redirects. e.g. !image baby ducklings
        daxDialogsDebouncer.debounce(for: 0.8) { [weak self] in
            self?.showDaxDialogOrStartTrackerNetworksAnimationIfNeeded()
        }

        // DuckPlayer finish loading actions
        duckPlayerNavigationHandler.handleDidFinishLoading(webView: webView)

        Task { @MainActor in
            if await webView.isCurrentSiteReferredFromDuckDuckGo {
                inferredOpenerContext = .serp
            }
        }
        
        tabInteractionStateSource?.saveState(webView.interactionState, for: tabModel)

        showDuckPlayerToastIfNeeded()
    }

    private func showDuckPlayerToastIfNeeded() {
        guard let url = webView.url,
              url.isYoutube,
              webView?.canGoBack == false else { return }

        let sanitizedURL = url.removingParameters(named: [
            WebDuckPlayerNavigationHandler.Constants.newTabParameter,
            WebDuckPlayerNavigationHandler.Constants.duckPlayerReferrerParameter,
            WebDuckPlayerNavigationHandler.Constants.allowFirstVideoParameter
        ])

        guard let youTubeAppLink = sanitizedURL.replacing(scheme: "youtube"),
              UIApplication.shared.canOpenURL(youTubeAppLink) else { return }

        ActionMessageView.present(message: UserText.duckPlayerOpenInYouTubeApp, actionTitle: UserText.actionOpen, onAction: {
            UIApplication.shared.open(youTubeAppLink)
        })

    }

    /// Check cache for DaxEasterEgg logo on commit (instant display for back navigation)
    private func checkDaxEasterEggCacheIfDuckDuckGoSearch(_ webView: WKWebView) {
        guard featureFlagger.isFeatureOn(.daxEasterEggLogos) else { return }
        
        guard let url = webView.url, url.isDuckDuckGoSearch else {
            // Clear logo when navigating away from DuckDuckGo search
            if tabModel.daxEasterEggLogoURL != nil {
                delegate?.tab(self, didExtractDaxEasterEggLogoURL: nil)
            }
            return
        }
        
        // Check cache for instant logo display
        if let searchQuery = url.searchQuery,
           let cachedLogoURL = logoCache.getLogo(for: searchQuery) {
            Logger.daxEasterEgg.debug("Using cached logo on commit for query '\(searchQuery)': \(cachedLogoURL)")
            delegate?.tab(self, didExtractDaxEasterEggLogoURL: cachedLogoURL)
        }
    }
    
    /// Trigger DaxEasterEgg extraction with cache fallback on DuckDuckGo search pages
    private func extractDaxEasterEggLogoIfDuckDuckGoSearch(_ webView: WKWebView) {
        guard featureFlagger.isFeatureOn(.daxEasterEggLogos) else { return }
        
        guard let url = webView.url, url.isDuckDuckGoSearch else {
            // Clear logo when navigating away from DuckDuckGo search
            if tabModel.daxEasterEggLogoURL != nil {
                delegate?.tab(self, didExtractDaxEasterEggLogoURL: nil)
            }
            return
        }
        
        // Check cache first - if found, use it and skip extraction
        if let searchQuery = url.searchQuery,
           let cachedLogoURL = logoCache.getLogo(for: searchQuery) {
            Logger.daxEasterEgg.debug("Using cached logo on finish for query '\(searchQuery)': \(cachedLogoURL)")
            delegate?.tab(self, didExtractDaxEasterEggLogoURL: cachedLogoURL)
            return
        }
        
        // Cache miss - proceed with JavaScript extraction
        // Ensure handler is created for new tabs that navigate directly to DuckDuckGo
        if daxEasterEggHandler == nil {
            daxEasterEggHandler = DaxEasterEggHandler(webView: webView, logoCache: logoCache)
            daxEasterEggHandler?.delegate = self
            Logger.daxEasterEgg.debug("Created DaxEasterEggHandler for new tab")
        }
        
        Logger.daxEasterEgg.debug("Extracting for tab - URL: \(url.shortDescription)")
        daxEasterEggHandler?.extractLogosForCurrentPage()
    }

    func trackSecondSiteVisitIfNeeded(url: URL?) {
        // Track second non-SERP webpage visit
        guard url?.isDuckDuckGoSearch == false else { return }
        onboardingPixelReporter.measureSecondSiteVisit()
    }

    func showDaxDialogOrStartTrackerNetworksAnimationIfNeeded() {
        guard !isLinkPreview else { return }

        if daxDialogsManager.isAddFavoriteFlow {
            delegate?.tabDidRequestShowingMenuHighlighter(tab: self)
            return
        }
              
        /// Never show onboarding Dax on Duck.ai, Youtube or DuckPlayer (unless DuckPlayer is disabled)
        guard let url = link?.url,
              !url.isDuckAIURL,
              !url.isDuckPlayer,
              !(url.isYoutube && duckPlayerNavigationHandler.duckPlayer.settings.mode != .disabled) else {
            // Do not dismiss while the fire onboarding dialog is up
            if !contextualOnboardingLogic.isShowingFireDialog {
                dismissContextualOnboardingIfNeeded()
            }
            scheduleTrackerNetworksAnimation(collapsing: true)
            return
        }

        guard let privacyInfo = self.privacyInfo,
              !isShowingFullScreenDaxDialog else {

            scheduleTrackerNetworksAnimation(collapsing: true)
            return
        }
        
        if let url = link?.url, url.isDuckDuckGoEmailProtection {
            scheduleTrackerNetworksAnimation(collapsing: true)
            return
        }
        guard let spec = daxDialogsManager.nextBrowsingMessageIfShouldShow(for: privacyInfo) else {

            // Dismiss Contextual onboarding if there's no message to show.
            dismissContextualOnboardingIfNeeded()
            // Dismiss privacy dashbooard pulse animation when no browsing dialog to show.
            delegate?.tabDidRequestPrivacyDashboardButtonPulse(tab: self, animated: false)

            if daxDialogsManager.shouldShowFireButtonPulse {
                delegate?.tabDidRequestFireButtonPulse(tab: self)
            }
            
            scheduleTrackerNetworksAnimation(collapsing: true)
            return
        }

        // In new onboarding we do not highlight the address bar so collapsing is default to true.
        scheduleTrackerNetworksAnimation(collapsing: true)
        let daxDialogSourceURL = self.url

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.presentContextualOnboardingIfURLUnchanged(spec: spec, sourceURL: daxDialogSourceURL)
        }
    }

    private func presentContextualOnboardingIfURLUnchanged(spec: DaxDialogs.BrowsingSpec, sourceURL: URL?) {
        // https://app.asana.com/0/414709148257752/1201620790053163/f
        if self.url != sourceURL && self.url?.isSameDuckDuckGoSearchURL(other: sourceURL) == false {
            daxDialogsManager.overrideShownFlagFor(spec, flag: false)
            self.isShowingFullScreenDaxDialog = false
            return
        }

        self.chromeDelegate?.omniBar.endEditing()
        self.chromeDelegate?.setBarsHidden(false, animated: true, customAnimationDuration: nil)

        // Present the contextual onboarding
        presentContextualOnboarding(for: spec)

        if spec == DaxDialogs.BrowsingSpec.withoutTrackers {
            self.woShownRecently = true
            self.fireWoFollowUp = true
        }
    }

    private func scheduleTrackerNetworksAnimation(collapsing: Bool) {
        let trackersWorkItem = DispatchWorkItem {
            guard let privacyInfo = self.privacyInfo else { return }
            guard self.shouldShowTrackersAnimation(for: privacyInfo) else { return }
            self.delegate?.tab(self, didRequestPresentingTrackerAnimation: privacyInfo, isCollapsing: collapsing)
        }
        trackersInfoWorkItem = trackersWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.trackerNetworksAnimationDelay,
                                      execute: trackersWorkItem)
    }
    
    private func cancelTrackerNetworksAnimation() {
        trackersInfoWorkItem?.cancel()
        trackersInfoWorkItem = nil
    }

    private func trackerAnimationDomain(for url: URL?) -> String? {
        guard let host = url?.host?.lowercased() else { return nil }
        return storageCache.tld.eTLDplus1(host) ?? host
    }

    private func updateTrackerAnimationDomainState(for url: URL?) {
        let currentDomain = trackerAnimationDomain(for: url)

        // Pre-set domain on first load to suppress tracker animation on cold start
        if shouldSuppressTrackerAnimationOnFirstLoad && url != nil {
            lastNotifiedTrackerAnimationDomain = currentDomain
            lastVisitedTrackerAnimationDomain = currentDomain
            shouldSuppressTrackerAnimationOnFirstLoad = false
            return
        }

        guard currentDomain != lastVisitedTrackerAnimationDomain else {
            return
        }
        lastVisitedTrackerAnimationDomain = currentDomain
        lastNotifiedTrackerAnimationDomain = nil
    }

    private func shouldShowTrackersAnimation(for privacyInfo: PrivacyInfo) -> Bool {
        guard appSettings.showTrackersBlockedAnimation else { return false }
        guard !privacyInfo.url.isDuckDuckGoSearch else { return false }
        guard !privacyInfo.trackerInfo.trackersBlocked.isEmpty else { return false }

        guard let currentDomain = trackerAnimationDomain(for: privacyInfo.url),
              currentDomain != lastNotifiedTrackerAnimationDomain else {
            return false
        }

        lastNotifiedTrackerAnimationDomain = currentDomain
        return true
    }
    
    private func checkLoginDetectionAfterNavigation() {
        if fireproofingWorker?.handleLoginDetection(detectedURL: detectedLoginURL,
                                                    currentURL: url,
                                                    isAutofillEnabled: AutofillSettingStatus.isAutofillEnabledInSettings,
                                                    saveLoginPromptLastDismissed: saveLoginPromptLastDismissed,
                                                    saveLoginPromptIsPresenting: saveLoginPromptIsPresenting,
                                                    shouldShowAutofillExtensionPrompt: shouldShowAutofillExtensionPrompt) ?? false {
            if shouldShowAutofillExtensionPrompt {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.presentAutofillExtensionPrompt()
                }
            }
            detectedLoginURL = nil
            saveLoginPromptLastDismissed = nil
            saveLoginPromptIsPresenting = false
            shouldShowAutofillExtensionPrompt = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.general.debug("didFailNavigation; error: \(error)")
        adClickAttributionDetection.onDidFailNavigation()
        adClickExternalOpenDetector.failNavigation(error: error)
        hideProgressIndicator()
        webpageDidFailToLoad()
        checkForReloadOnError()
        scheduleTrackerNetworksAnimation(collapsing: true)
        linkProtection.setMainFrameUrl(nil)
        referrerTrimming.onFailedNavigation()

        // Skip the site-loading failure pixel for download handoffs (WebKit error 102) — same exclusion
        // as `didFailProvisionalNavigation`.
        let nsError = error as NSError
        let isDownloadHandoff = nsError.code == 102 && nsError.domain == "WebKitErrorDomain"
        if !isDownloadHandoff {
            navigationPixelResponder.didFail(navigation, error: error)
        }

        notifyDelegateIfDuckAINavigationFailed(error: error)
    }

    private func webpageDidFailToLoad() {
        Logger.general.debug("webpageLoading failed")

        wasLoadingStoppedExternally = false

        if isError {
            showBars(animated: true)
            privacyInfo = PrivacyInfo(url: .empty, parentEntity: nil, protectionStatus: .init(unprotectedTemporary: false, enabledFeatures: [], allowlisted: false, denylisted: false), isSpecialErrorPageVisible: true)
            onPrivacyInfoChanged()
        }

        self.delegate?.tabLoadingStateDidChange(tab: self)
        self.delegate?.tabDidFinishNavigation(self)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.general.debug("didFailProvisionalNavigation; error: \(error)")
        adClickAttributionDetection.onDidFailNavigation()
        adClickExternalOpenDetector.failNavigation(error: error)
        hideProgressIndicator()
        linkProtection.setMainFrameUrl(nil)
        referrerTrimming.onFailedNavigation()
        urlProvidedBasicAuthCredential = nil
        lastError = error
        let error = error as NSError

        // Ignore Frame Load Interrupted that will be caused when a download starts
        if error.code == 102 && error.domain == "WebKitErrorDomain" {
            return
        }

        if let url = url,
           let domain = url.host,
           error.code == Constants.frameLoadInterruptedErrorCode {
            // prevent loops where a site keeps redirecting to itself (e.g. bbc)
            failingUrls.insert(domain)

            // Reset the URL, e.g if opened externally
            self.url = webView.url
        }

        // Fire the site-loading failure pixel after the download-handoff guard above so WebKit error 102
        // isn't miscounted as a failure. User cancellations are counted intentionally.
        navigationPixelResponder.didFail(navigation, error: error)

        // Bail out before showing error when navigation was cancelled by the user
        if error.code == NSURLErrorCancelled && error.domain == NSURLErrorDomain {
            webpageDidFailToLoad()

            // Reset url to current one, as navigation was not successful
            self.url = webView.url
            return
        }

        // wait before showing errors in case they recover automatically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showErrorNow()
        }

        // Notify Special Error page that webview navigation failed and show special error page if needed.
        specialErrorPageNavigationHandler.handleWebView(webView, didFailProvisionalNavigation: navigation, withError: error)

        notifyDelegateIfDuckAINavigationFailed(error: error)
    }

    private func notifyDelegateIfDuckAINavigationFailed(error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled || nsError.domain != NSURLErrorDomain else { return }

        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
            ?? webView.url
            ?? url

        guard let failingURL, failingURL.isDuckAIURL else { return }
        delegate?.tab(self, didFailDuckAINavigationFor: failingURL, error: error)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        self.privacyInfo = makePrivacyInfo(url: url)
        onPrivacyInfoChanged()

        if addressBarURLFilter.shouldUpdate(for: url) {
            self.url = url
        }

        checkLoginDetectionAfterNavigation()
    }
    
    private func requestForDoNotSell(basedOn incomingRequest: URLRequest) -> URLRequest? {
        let config = privacyConfigurationManager.privacyConfig
        guard var request = GPCRequestFactory().requestForGPC(basedOn: incomingRequest,
                                                              config: config,
                                                              gpcEnabled: appSettings.sendDoNotSell) else {
            return nil
        }
        
        request.attribution = .user

        return request
    }

    // swiftlint:disable cyclomatic_complexity

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        // Capture the site-loading navigation type only at the moment the navigation is actually allowed.
        // Doing it any earlier — e.g. at the top of this function — would race when policy decisions
        // overlap: for instance, the content-blocking wait below can hold nav1's `decisionHandler` while
        // nav2 enters `decidePolicyFor`, and a second `willStart` would overwrite the pending type before
        // nav1's `didStartProvisionalNavigation` consumed it. WebKit serializes delegate callbacks on the
        // main queue, so firing from inside the allow branches guarantees the next event is the matching
        // `didStartProvisional` — no other `decidePolicyFor` can interleave between them.
        //
        // `determineAllowPolicy()` may also return the private `WKNavigationActionPolicy(rawValue: 3)`
        // (`_WKNavigationActionPolicyAllowWithoutTryingAppLink`) to disable Universal Links handling
        // (set via `preventUniversalLinksOnce` — notably after a tab restoration). WebKit still produces
        // a `didStartProvisional` for it, so `willStart` must fire just like for the public `.allow` value.
        let wrappedHandler: (WKNavigationActionPolicy) -> Void = { [weak self] policy in
            if policy == .allow || policy.rawValue == 3 {
                self?.navigationPixelResponder.willStart(navigationAction)
            }
            decisionHandler(policy)
        }

        // There is an `isUserInitiated` var on navigationAction that uses private API
        //  but this approach is public API.  Unfortunately this means that on iOS 17 and older
        //  if the user visits the a domain where as a loop has already been detected
        //  we'll show the error page but that is a small number at this point already.
        if #available(iOS 18.4, *), navigationAction.buttonNumber.contains(.primary) {
            safariRedirectHandler.reset()
        }

        if let url = navigationAction.request.url {
            if !tabURLInterceptor.allowsNavigatingTo(url: url) {
                wrappedHandler(.cancel)
                // If there is history or a page loaded keep the tab open
                if self.currentlyLoadedURL == nil {
                    delegate?.tabDidRequestClose(self)
                }
                return
            }
        }
        
        if duckPlayerNavigationHandler.handleDelegateNavigation(navigationAction: navigationAction, webView: webView) {
            wrappedHandler(.cancel)
            return
        }
        
        if let url = navigationAction.request.url,
           !url.isDuckDuckGoSearch,
           true == shouldWaitUntilContentBlockingIsLoaded({ [weak self, webView /* decision handler must be called */] in
               guard let self = self else {
                   wrappedHandler(.cancel)
                   return
               }
               self.webView(webView, decidePolicyFor: navigationAction, decisionHandler: wrappedHandler)
           }) {
            // will wait for Content Blocking to load and re-call on completion
            return
        }
        

        didGoBackForward = (navigationAction.navigationType == .backForward)

        if navigationAction.navigationType != .reload && navigationAction.navigationType != .other {
            // Ignore .other actions because refresh can cause a redirect
            // This is also handled in loadRequest(_:)
            refreshCountSinceLoad = 0
        }

        if navigationAction.navigationType != .reload, webView.url != navigationAction.request.mainDocumentURL {
            delegate?.tabDidRequestNavigationToDifferentSite(tab: self)
        }

        switch Self.aiChatNewWindowDecision(currentURL: webView.url, navigationAction: navigationAction) {
        case .loadInTab(let aiChatNewWindowURL):
            wrappedHandler(.cancel)
            load(url: aiChatNewWindowURL)
            return
        case .openInNewTab(let aiChatNewWindowURL):
            wrappedHandler(.cancel)
            delegate?.tab(self,
                          didRequestNewTabForUrl: aiChatNewWindowURL,
                          openedByPage: true,
                          inheritingAttribution: adClickAttributionLogic.state)
            return
        case .ignore:
            break
        }

        // Same-frame boundary-cross link taps spawn a new tab (cross-frame is handled by `aiChatNewWindowDecision` above). Skip when ⌘ is held.
        // Runs before tracking-link/referrer/DNS rewrites — acceptable since the new tab re-runs the full policy pipeline; only originating-frame context is lost, which a boundary cross severs anyway.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame == true,
           let linkURL = navigationAction.request.url,
           let scheme = linkURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           !(delegate?.tabWillRequestNewTab(self)?.contains(.command) ?? false) {
            // Use `self.isAITab` over `webView.url?.isDuckAIURL` — webView.url goes transiently nil during in-flight navigations, losing boundary protection.
            let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
                currentIsAI: isAITab,
                targetIsAI: linkURL.isDuckAIURL,
                unifiedToggleInputAvailable: unifiedToggleInputFeature.isAvailable
            )
            if decision == .openInNewTab {
                wrappedHandler(.cancel)
                delegate?.tab(self,
                              didRequestNewTabForUrl: linkURL,
                              openedByPage: true,
                              inheritingAttribution: adClickAttributionLogic.state)
                return
            }
        }

        // This check needs to happen before GPC checks. Otherwise the navigation type may be rewritten to `.other`
        // which would skip link rewrites.
        if navigationAction.navigationType != .backForward,
           navigationAction.isTargetingMainFrame(),
           !(navigationAction.request.url?.isDuckDuckGoSearch ?? false) {
            let didRewriteLink = linkProtection.requestTrackingLinkRewrite(initiatingURL: webView.url,
                                                                           navigationAction: navigationAction,
                                                                           onStartExtracting: { showProgressIndicator() },
                                                                           onFinishExtracting: { },
                                                                           onLinkRewrite: { [weak self] newRequest, _ in
                guard let self = self else { return }
                self.load(urlRequest: newRequest)
            },
                                                                           policyDecisionHandler: wrappedHandler)

            if didRewriteLink {
                return
            }
        }

        if navigationAction.isTargetingMainFrame(),
           !(navigationAction.request.url?.isCustomURLScheme() ?? false),
           navigationAction.navigationType != .backForward,
           let newRequest = referrerTrimming.trimReferrer(forNavigation: navigationAction,
                                                          originUrl: webView.url ?? navigationAction.sourceFrame.webView?.url) {
            wrappedHandler(.cancel)
            load(urlRequest: newRequest)
            return
        }

        if navigationAction.isTargetingMainFrame(),
           !navigationAction.isSameDocumentNavigation,
           !navigationAction.shouldDownload,
           !(navigationAction.request.url?.isCustomURLScheme() ?? false),
           navigationAction.navigationType != .backForward,
           let request = requestForDoNotSell(basedOn: navigationAction.request) {
            wrappedHandler(.cancel)
            load(urlRequest: request)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let modifierFlags = delegate?.tabWillRequestNewTab(self) {

            if modifierFlags.contains(.command) {
                if modifierFlags.contains(.shift) {
                    wrappedHandler(.cancel)
                    delegate?.tab(self,
                                  didRequestNewTabForUrl: url,
                                  openedByPage: false,
                                  inheritingAttribution: adClickAttributionLogic.state)
                    return
                } else {
                    wrappedHandler(.cancel)
                    delegate?.tab(self, didRequestNewBackgroundTabForUrl: url, inheritingAttribution: adClickAttributionLogic.state)
                    return
                }
            }
        }

        decidePolicyFor(navigationAction: navigationAction) { [weak self] decision in
            if let self = self,
               let url = navigationAction.request.url,
               decision != .cancel,
               navigationAction.isTargetingMainFrame() {
                if url.isDuckDuckGoSearch {

                    if !url.isDuckAIURL {
                        NotificationCenter.default.post(name: .userDidPerformDDGSearch, object: self)
                    }

                    let shouldSkipSearchAtbForDuckAI = url.isDuckAIURL
                    if !shouldSkipSearchAtbForDuckAI {
                        let backgroundAssertion = QRunInBackgroundAssertion(name: "StatisticsLoader background assertion - search",
                                                                            application: UIApplication.shared)
                        StatisticsLoader.shared.refreshSearchRetentionAtb {
                            DispatchQueue.main.async {
                                backgroundAssertion.release()
                            }
                        }
                    }
                    subscriptionDataReporter.saveSearchCount()
                }

                self.delegate?.closeFindInPage(tab: self)
            }
            // If navigating to the URL is allowed and we're not sideloading a special error page, forward the event to
            // the SpecialErrorPageNavigationHandler.
            if let self, decision == .allow, !self.specialErrorPageNavigationHandler.isSpecialErrorPageRequest {
                self.specialErrorPageNavigationHandler.handleDecidePolicy(for: navigationAction, webView: webView)
            }
            wrappedHandler(decision)
        }
    }
    // swiftlint:enable cyclomatic_complexity

    private func shouldWaitUntilContentBlockingIsLoaded(_ completion: @Sendable @escaping @MainActor () -> Void) -> Bool {
        // Ensure Content Blocking Assets (WKContentRuleList&UserScripts) are installed
        if userContentController.contentBlockingAssetsInstalled
            || !privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking) {

            rulesCompilationMonitor.reportNavigationDidNotWaitForRules()
            return false
        }

        Task {
            rulesCompilationMonitor.tabWillWaitForRulesCompilation(tabModel.uid)
            showProgressIndicator()
            await userContentController.awaitContentBlockingAssetsInstalled()
            rulesCompilationMonitor.reportTabFinishedWaitingForRules(tabModel.uid)

            await MainActor.run(body: completion)
        }
        return true
    }

    private func decidePolicyFor(navigationAction: WKNavigationAction, completion: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowPolicy = determineAllowPolicy()

        if navigationAction.navigationType == .linkActivated {
            delegate?.tabDidEngageWithPage(self)
        }

        let tld = storageCache.tld
        
        // If WKNavigationAction requests to shouldPerformDownload prepare for handling it in decidePolicyFor:navigationResponse:
        recentNavigationActionShouldPerformDownloadURL = navigationAction.shouldPerformDownload ? navigationAction.request.url : nil

        if navigationAction.isTargetingMainFrame()
            && tld.domain(navigationAction.request.mainDocumentURL?.host) != tld.domain(lastUpgradedURL?.host) {
            lastUpgradedURL = nil
            privacyInfo?.connectionUpgradedTo = nil
        }

        guard navigationAction.request.mainDocumentURL != nil else {
            completion(allowPolicy)
            return
        }

        guard let url = navigationAction.request.url else {
            completion(allowPolicy)
            return
        }

        if navigationAction.isTargetingMainFrame(), navigationAction.navigationType == .backForward {
            adClickAttributionLogic.onBackForwardNavigation(mainFrameURL: webView.url)
        }

        let schemeType = SchemeHandler.schemeType(for: url)
        self.blobDownloadTargetFrame = nil

        if safariRedirectHandler.handleRedirect(to: url) {
            completion(.cancel)
            return
        }

        switch schemeType {
        case .allow:
            completion(.allow)
            return

        case .navigational:
            performNavigationFor(url: url,
                                 navigationAction: navigationAction,
                                 allowPolicy: allowPolicy,
                                 completion: completion)

        case .external(let action):
            performExternalNavigationFor(url: url, action: action)
            completion(.cancel)

        case .blob:
            performBlobNavigation(navigationAction, completion: completion)
        
        case .duck:
            if navigationAction.isTargetingMainFrame() {
                duckPlayerNavigationHandler.handleDuckNavigation(navigationAction, webView: webView)
            }
            completion(.cancel)

        case .unknown:
            if navigationAction.navigationType == .linkActivated {
                openExternally(url: url)
            } else {
                presentOpenInExternalAppAlert(url: url)
            }
            completion(.cancel)
        }
    }

    private func inferLoadContext(for navigationAction: WKNavigationAction) -> BrokenSiteReport.OpenerContext? {
        guard navigationAction.navigationType != .reload else { return nil }
        guard let currentUrl = webView.url, let newUrl = navigationAction.request.url else { return nil }

        if currentUrl.isDuckDuckGoSearch && !newUrl.isDuckDuckGoSearch {
            return .serp
        } else {
            switch navigationAction.navigationType {
            case .linkActivated, .other, .formSubmitted:
                return .navigation
            default:
                return nil
            }
        }
    }

    private func performNavigationFor(url: URL,
                                      navigationAction: WKNavigationAction,
                                      allowPolicy: WKNavigationActionPolicy,
                                      completion: @escaping (WKNavigationActionPolicy) -> Void) {

        // when navigating to a request with basic auth username/password, cache it and redirect to a trimmed URL
        if navigationAction.isTargetingMainFrame(),
           let credential = url.basicAuthCredential {
            var newRequest = navigationAction.request
            newRequest.url = url.removingBasicAuthCredential()
            self.urlProvidedBasicAuthCredential = (credential, newRequest.url!)

            completion(.cancel)
            self.load(urlRequest: newRequest)
            return

        } else if let urlProvidedBasicAuthCredential,
                  url != urlProvidedBasicAuthCredential.url {
            self.urlProvidedBasicAuthCredential = nil
        }

        inferredOpenerContext = inferLoadContext(for: navigationAction)

        if shouldReissueSearch(for: url) {
            reissueSearchWithRequiredParams(for: url)
            completion(.cancel)
            return
        }

        if shouldReissueDDGStaticNavigation(for: url) {
            reissueNavigationWithSearchHeaderParams(for: url)
            completion(.cancel)
            return
        }

        if isNewTargetBlankRequest(navigationAction: navigationAction) {
            // This will fallback to native WebView handling through webView(_:createWebViewWith:for:windowFeatures:)
            completion(allowPolicy)
            return
        }

        if allowPolicy != WKNavigationActionPolicy.cancel && navigationAction.isTargetingMainFrame() {
            if shouldUseSafariOnlyUserAgentForNextMainFrameNavigation {
                webView.customUserAgent = userAgentManager.safariOnlyUserAgent(isDesktop: tabModel.isDesktop)
                shouldUseSafariOnlyUserAgentForNextMainFrameNavigation = false
            } else {
                userAgentManager.update(webView: webView, isDesktop: tabModel.isDesktop, url: url)
            }
        }

        if !privacyConfigurationManager.privacyConfig.isProtected(domain: url.host) {
            completion(allowPolicy)
            return
        }

        if shouldUpgradeToHttps(url: url, navigationAction: navigationAction) {
            upgradeToHttps(url: url, allowPolicy: allowPolicy, completion: completion)
        } else {
            completion(allowPolicy)
        }
    }

    private func upgradeToHttps(url: URL,
                                allowPolicy: WKNavigationActionPolicy,
                                completion: @escaping (WKNavigationActionPolicy) -> Void) {
        httpsUpgradeTask = Task {
            let result = await PrivacyFeatures.httpsUpgrade.upgrade(url: url)
            guard !Task.isCancelled else {
                completion(.cancel)
                return
            }
            switch result {
            case let .success(upgradedUrl):
                if lastUpgradedURL != upgradedUrl {
                    lastUpgradedURL = upgradedUrl
                    privacyInfo?.connectionUpgradedTo = upgradedUrl
                    load(url: upgradedUrl, didUpgradeURL: true)
                    completion(.cancel)
                } else {
                    completion(allowPolicy)
                }
            case .failure:
                completion(allowPolicy)
            }
        }
    }

    private func shouldUpgradeToHttps(url: URL, navigationAction: WKNavigationAction) -> Bool {
        return !failingUrls.contains(url.host ?? "") && navigationAction.isTargetingMainFrame()
    }

    private func performExternalNavigationFor(url: URL, action: SchemeHandler.Action) {
        switch action {
        case .open:
            openExternally(url: url)
        case .askForConfirmation:
            presentOpenInExternalAppAlert(url: url)
        case .cancel:
            break
        }
    }
    
    private func isNewTargetBlankRequest(navigationAction: WKNavigationAction) -> Bool {
        return navigationAction.navigationType == .linkActivated && navigationAction.targetFrame == nil
    }

    private func determineAllowPolicy() -> WKNavigationActionPolicy {
        let allowWithoutUniversalLinks = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
        if preventUniversalLinksOnce {
            return allowWithoutUniversalLinks
        }
        return AppUserDefaults().allowUniversalLinks ? .allow : allowWithoutUniversalLinks
    }
    
    private func showErrorNow() {
        guard let error = lastError as NSError? else { return }
        hideProgressIndicator()
        ViewHighlighter.hideAll()

        if !(error.failedUrl?.isCustomURLScheme() ?? false) {
            url = error.failedUrl
            showError(message: error.localizedDescription)
            Pixel.fire(pixel: .webViewErrorPageShown)
        }

        webpageDidFailToLoad()
        checkForReloadOnError()
    }
    
    func dismissKeyboardIfPresent() {
        self.webView.evaluateJavaScript("document.activeElement?.blur()")
    }
    
    private func showLoginDetails(with account: SecureVaultModels.WebsiteAccount, source: AutofillSettingsSource) {
        delegate?.tab(self, didRequestAutofillLogins: account, source: source, extensionPromotionManager: extensionPromotionManager)
    }
    
    @objc private func dismissLoginDetails() {
        dismiss(animated: true)
    }

    private func registerForAutofillNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(autofillBreakageReport),
                                               name: .autofillFailureReport,
                                               object: nil)
    }

    private func registerForResignActive() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onApplicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func unregisterFromResignActive() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func registerForKeyboardNotifications() {
        guard isCreditCardAutofillEnabled() else {
            return
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardDidHide),
                                               name: UIResponder.keyboardDidHideNotification,
                                               object: nil)
    }

    private func unregisterFromKeyboardNotifications() {
        guard isCreditCardAutofillEnabled() else {
            return
        }

        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
    }

    @objc private func autofillBreakageReport(_ notification: Notification) {
        guard let tabUid = notification.userInfo?[AutofillLoginListViewModel.UserInfoKeys.tabUid] as? String,
              tabUid == tabModel.uid,
              let url = webView.url?.normalized() else {
            return
        }

        let parameters: [String: String] = [
            "website": url.absoluteString,
            "language": Locale.current.languageCode ?? "en",
            "autofill_enabled": appSettings.autofillCredentialsEnabled ? "true" : "false",
            "privacy_protection": (privacyInfo?.isFor(self.url) ?? false) ? "true" : "false",
            "email_protection": (emailManager?.isSignedIn ?? false) ? "true" : "false",
            "never_prompt": autofillNeverPromptWebsitesManager.hasNeverPromptWebsitesFor(domain: url.host ?? url.absoluteString) ? "true" : "false"
        ]

        Pixel.fire(pixel: .autofillLoginsReportFailure, withAdditionalParameters: parameters)

        ActionMessageView.present(message: UserText.autofillSettingsReportNotWorkingSentConfirmation)
    }

    @objc private func keyboardDidHide(_ notification: Notification) {
        if !fillCreditCardsPromptIsPresenting && isTabCurrentlyPresented() {
            autofillUserScript?.cancelAllPendingReplies()
            cleanupInputAccessoryView()
        }
    }

}

// MARK: - Downloads
extension TabViewController {

    private func performBlobNavigation(_ navigationAction: WKNavigationAction,
                                       completion: @escaping (WKNavigationActionPolicy) -> Void) {
        self.blobDownloadTargetFrame = navigationAction.targetFrame
        completion(.allow)
    }

    private func startDownload(with navigationResponse: WKNavigationResponse) async -> (responsePolicy: WKNavigationResponsePolicy, download: Download?) {
        let downloadManager = AppDependencyProvider.shared.downloadManager
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let url = navigationResponse.response.url!

        if case .blob = SchemeHandler.schemeType(for: url) {
            return (.download, nil)
        } else {
            // ICS files must persist; other auto-previewable types stay temporary.
            let persistICS = FilePreviewHelper.shouldPersistInDownloads(
                mimeType: MIMEType(from: navigationResponse.response.mimeType),
                url: navigationResponse.response.url,
                filename: navigationResponse.response.suggestedFilename,
                featureFlagger: featureFlagger
            )
            do {
                if let download = try downloadManager.makeDownload(navigationResponse: navigationResponse,
                                                                    cookieStore: cookieStore,
                                                                    temporary: persistICS ? false : nil) {
                    downloadManager.startDownload(download)
                    return (.cancel, download)
                }
            } catch let error as DownloadError {
                Logger.general.error("Failed to create download: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
                    ActionMessageView.present(message: UserText.messageDownloadFailed,
                                              presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom))
                }
            } catch {
                assertionFailure("Expected DownloadError")
                Logger.general.error("Failed to create download: Unkown Error)")
            }
            
        }

        return (.cancel, nil)
    }

    /**
     Some files might be previewed by webkit but in order to share them
     we need to download them first.
     This method stores the temporary download or clears it if necessary
     
     - Returns: Navigation policy or nil if it is not a download
     */
    private func setupOrClearTemporaryDownload(for response: URLResponse) -> WKNavigationResponsePolicy? {
        let downloadManager = AppDependencyProvider.shared.downloadManager
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        guard response.url != nil,
              let downloadMetaData = try? downloadManager.downloadMetaData(for: response),
              !downloadMetaData.mimeType.isHTML,
              let download = try? downloadManager.makeDownload(response: response,
                                                               cookieStore: cookieStore,
                                                               temporary: true)
        else {
            temporaryDownloadForPreviewedFile?.cancel()
            temporaryDownloadForPreviewedFile = nil
            return nil
        }

        temporaryDownloadForPreviewedFile = download
        return .allow
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        let delegate = InlineWKDownloadDelegate()
        // temporary delegate held strongly in callbacks
        // after destination decision WKDownload delegate will be set
        // to a WKDownloadSession and passed to Download Manager
        delegate.decideDestinationCallback = { [weak self] _, _, suggestedFilename, callback in
            withExtendedLifetime(delegate) {
                let downloadManager = AppDependencyProvider.shared.downloadManager
                guard let self = self,
                      let downloadMetadata = try? downloadManager.downloadMetaData(for: navigationResponse.response,
                                                                                   suggestedFilename: suggestedFilename)
                else {
                    callback(nil)
                    delegate.decideDestinationCallback = nil
                    delegate.downloadDidFailCallback = nil
                    self?.blobDownloadTargetFrame = nil
                    return
                }

                if self.shouldTriggerDownloadAction(for: navigationResponse) && !FilePreviewHelper.canAutoPreviewMIMEType(downloadMetadata.mimeType) {
                    // Show alert to the file download
                    self.presentSaveToDownloadsAlert(with: downloadMetadata) { [weak self] in
                        guard let self else {
                            callback(nil)
                            return
                        }
                        callback(self.transfer(download,
                                               to: downloadManager,
                                               with: navigationResponse.response,
                                               suggestedFilename: suggestedFilename,
                                               isTemporary: false))
                    } cancelHandler: {
                        callback(nil)
                    }

                    self.temporaryDownloadForPreviewedFile = nil
                } else {
                    // Showing file in the webview or in preview view
                    if FilePreviewHelper.canAutoPreviewMIMEType(downloadMetadata.mimeType) {
                        // If FilePreviewHelper can handle format we do not need to load as it will be handled by setting
                        // temporaryDownloadForPreviewedFile and mostRecentAutoPreviewDownloadID
                    } else if navigationResponse.canShowMIMEType {
                        // To load BLOB in web view we need to restart the request loading as it was interrupted by .download callback
                        self.webView.load(navigationResponse.response.url!, in: self.blobDownloadTargetFrame)
                    }
                    callback(self.transfer(download,
                                           to: downloadManager,
                                           with: navigationResponse.response,
                                           suggestedFilename: suggestedFilename,
                                           isTemporary: true))
                }

                delegate.decideDestinationCallback = nil
                delegate.downloadDidFailCallback = nil
                self.blobDownloadTargetFrame = nil
            }
        }
        delegate.downloadDidFailCallback = { _, _, _ in
            withExtendedLifetime(delegate) {
                delegate.decideDestinationCallback = nil
                delegate.downloadDidFailCallback = nil
            }
        }
        download.delegate = delegate
    }

    private func transfer(_ download: WKDownload,
                          to downloadManager: DownloadManager,
                          with response: URLResponse,
                          suggestedFilename: String,
                          isTemporary: Bool) -> URL? {

        let downloadSession = WKDownloadSession(download)
        let download: Download?
        do {
            download = try downloadManager.makeDownload(response: response,
                                                    suggestedFilename: suggestedFilename,
                                                    downloadSession: downloadSession,
                                                    cookieStore: nil,
                                                    temporary: isTemporary)
        } catch let error as DownloadError {
            Logger.general.error("Failed to transfer download: \(error.description, privacy: .public)")
            DispatchQueue.main.async {
                let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
                ActionMessageView.present(message: UserText.messageDownloadFailed,
                                          presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom))
            }
            return nil
        } catch {
            assertionFailure("Expected DownloadError")
            Logger.general.error("Failed to transfer download: Unkown Error)")
            return nil
        }

        self.temporaryDownloadForPreviewedFile = isTemporary ? download : nil
        self.mostRecentAutoPreviewDownloadID = isTemporary ? download?.id : nil
        if let download = download {
            downloadManager.startDownload(download)
        }

        return downloadSession.localURL
    }

    private func presentSaveToDownloadsAlert(with downloadMetadata: DownloadMetadata,
                                             saveToDownloadsHandler: @escaping () -> Void,
                                             cancelHandler: @escaping (() -> Void)) {
        let alert = SaveToDownloadsAlert.makeAlert(downloadMetadata: downloadMetadata) {
            Pixel.fire(pixel: .downloadStarted,
                       withAdditionalParameters: [PixelParameters.canAutoPreviewMIMEType: "0"])

            if downloadMetadata.mimeType != .octetStream {
                let mimeType = downloadMetadata.mimeTypeSource
                Pixel.fire(pixel: .downloadStartedDueToUnhandledMIMEType,
                           withAdditionalParameters: [PixelParameters.mimeType: mimeType])
            }

            saveToDownloadsHandler()
        } cancelHandler: {
            cancelHandler()
        }
        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }

    enum SaveToDownloadsResult {
        case success
        case cancelled
    }

    private func presentSaveToDownloadsAlert(with downloadMetadata: DownloadMetadata) async -> SaveToDownloadsResult {
        await withCheckedContinuation { continuation in
            presentSaveToDownloadsAlert(
                with: downloadMetadata,
                saveToDownloadsHandler: {
                    continuation.resume(returning: .success)
                }, cancelHandler: {
                    continuation.resume(returning: .cancelled)
                }
            )
        }
    }

    private func registerForDownloadsNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(downloadDidStart),
                                               name: .downloadStarted,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector:
                                                #selector(downloadDidFinish),
                                               name: .downloadFinished,
                                               object: nil)
    }

    @objc private func downloadDidStart(_ notification: Notification) {
        guard let download = notification.userInfo?[DownloadManager.UserInfoKeys.download] as? Download,
              !download.temporary,
              !FilePreviewHelper.handlesDownloadNatively(mimeType: download.mimeType,
                                                         url: download.url,
                                                         filename: download.filename,
                                                         featureFlagger: featureFlagger)
        else { return }

        let attributedMessage = DownloadActionMessageViewHelper.makeDownloadStartedMessage(for: download)

        DispatchQueue.main.async {
            ActionMessageView.present(message: attributedMessage, numberOfLines: 2, actionTitle: UserText.actionGenericShow,
                                      presentationLocation: .withBottomBar(andAddressBarBottom: self.appSettings.currentAddressBarPosition.isBottom),
                                      onAction: {
                Pixel.fire(pixel: .downloadsListOpened,
                           withAdditionalParameters: [PixelParameters.originatedFromMenu: "0"])
                self.delegate?.tabDidRequestDownloads(tab: self)
            })
        }
    }

    @objc private func downloadDidFinish(_ notification: Notification) {
        if let error = notification.userInfo?[DownloadManager.UserInfoKeys.error] as? Error {
            let nserror = error as NSError
            let downloadWasCancelled = nserror.domain == "NSURLErrorDomain" && nserror.code == -999

            if !downloadWasCancelled {
                let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
                ActionMessageView.present(message: UserText.messageDownloadFailed,
                                          presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom))
            }

            return
        }

        guard let download = notification.userInfo?[DownloadManager.UserInfoKeys.download] as? Download else { return }

        DispatchQueue.main.async {
            let handledNatively = FilePreviewHelper.handlesDownloadNatively(mimeType: download.mimeType,
                                                                            url: download.location,
                                                                            filename: download.filename,
                                                                            featureFlagger: self.featureFlagger)
            if !download.temporary && !handledNatively {
                let attributedMessage = DownloadActionMessageViewHelper.makeDownloadFinishedMessage(for: download)
                let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
                ActionMessageView.present(message: attributedMessage, numberOfLines: 2, actionTitle: UserText.actionGenericShow,
                                          presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom),
                                          onAction: {
                    Pixel.fire(pixel: .downloadsListOpened,
                               withAdditionalParameters: [PixelParameters.originatedFromMenu: "0"])
                    self.delegate?.tabDidRequestDownloads(tab: self)
                })
            } else {
                self.previewDownloadedFileIfNecessary(download)
            }
        }
    }

    private func previewDownloadedFileIfNecessary(_ download: Download) {
        let canAutoPreview = FilePreviewHelper.canAutoPreview(mimeType: download.mimeType,
                                                              url: download.location,
                                                              filename: download.filename,
                                                              featureFlagger: featureFlagger)
        guard let delegate = self.delegate,
              delegate.tabCheckIfItsBeingCurrentlyPresented(self),
              canAutoPreview,
              let fileHandler = FilePreviewHelper.fileHandlerForDownload(download, viewController: self, featureFlagger: featureFlagger)
        else { return }

        if mostRecentAutoPreviewDownloadID == download.id {
            retainCalendarPreviewIfNeeded(fileHandler)
            retainContactPreviewIfNeeded(fileHandler)
            fileHandler.preview()
        } else {
            let pixelParameters = [PixelParameters.mimeType: download.mimeType.rawValue,
                                   PixelParameters.downloadListCount: "\(AppDependencyProvider.shared.downloadManager.downloadList.count)"]
            Pixel.fire(pixel: .downloadTriedToPresentPreviewWithoutTab, withAdditionalParameters: pixelParameters)
        }
    }

    private func retainCalendarPreviewIfNeeded(_ fileHandler: FilePreview) {
        guard let calendarHandler = fileHandler as? CalendarEventPreviewHelper else { return }
        pendingCalendarPreview = calendarHandler
        calendarHandler.onDismiss = { [weak self] in
            self?.pendingCalendarPreview = nil
        }
        calendarHandler.onSaved = { [weak self] in
            self?.showFileHandlerAddedToast(message: UserText.icsEventAddedToCalendar)
        }
        calendarHandler.onFailure = { [weak self] failure in
            self?.showCalendarAddFailureToast(for: failure)
        }
    }

    private func retainContactPreviewIfNeeded(_ fileHandler: FilePreview) {
        guard let contactHandler = fileHandler as? ContactPreviewHelper else { return }
        pendingContactPreview = contactHandler
        contactHandler.onDismiss = { [weak self] in
            self?.pendingContactPreview = nil
        }
        contactHandler.onSaved = { [weak self] in
            self?.showFileHandlerAddedToast(message: UserText.vcardContactAdded)
        }
        contactHandler.onParseFailure = { [weak self] in
            self?.showFileHandlerFailureToast(message: UserText.vcardAddContactParseFailure)
        }
    }

    private func showCalendarAddFailureToast(for failure: CalendarEventPreviewHelper.Failure) {
        let message: String
        switch failure {
        case .multipleEvents:
            message = UserText.icsAddToCalendarMultipleEvents
        case .unrecognizedTimeZone:
            message = UserText.icsAddToCalendarUnrecognizedTimeZone
        case .parseFailure:
            message = UserText.icsAddToCalendarParseFailure
        }
        showFileHandlerFailureToast(message: message)
    }

    /// Success toast for an imported file (calendar event added, contact added, etc.).
    private func showFileHandlerAddedToast(message: String) {
        ActionMessageView.present(
            message: message,
            presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom)
        )
    }

    private func showFileHandlerFailureToast(message: String) {
        ActionMessageView.present(
            message: message,
            actionTitle: UserText.actionGenericShow,
            presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
            duration: 10,
            onAction: { [weak self] in
                self?.openDownloadsFromToast()
            }
        )
    }

    private func openDownloadsFromToast() {
        Pixel.fire(pixel: .downloadsListOpened,
                   withAdditionalParameters: [PixelParameters.originatedFromMenu: "0"])
        let openDownloads = { [weak self] in
            guard let self else { return }
            self.delegate?.tabDidRequestDownloads(tab: self)
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: openDownloads)
        } else {
            openDownloads()
        }
    }
}

// MARK: - WKUIDelegate
extension TabViewController: WKUIDelegate {

    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        return delegate?.tab(self,
                             didRequestNewWebViewWithConfiguration: configuration,
                             for: navigationAction,
                             inheritingAttribution: adClickAttributionLogic.state)
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard origin.host.isDuckAIHost,
              type == .microphone || type == .cameraAndMicrophone else {
            decisionHandler(.prompt)
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        decisionHandler(status == .authorized ? .grant : .deny)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if openedByPage {
            delegate?.tabDidRequestClose(self)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleWebContentProcessDidTerminate(webView, reasonName: nil)
    }

    // WebKit invokes this in place of `webViewWebContentProcessDidTerminate(_:)` when a termination
    // reason is available, so it must reproduce that method's reporting and recovery in full.
    @objc(_webView:webContentProcessDidTerminateWithReason:)
    public func webView(_ webView: WKWebView, webContentProcessDidTerminateWith reason: Int) {
        handleWebContentProcessDidTerminate(webView, reasonName: WKProcessTerminationReason(rawValue: reason)?.pixelName ?? "unknown")
    }

    private func handleWebContentProcessDidTerminate(_ webView: WKWebView, reasonName: String?) {
        let isDuckAITab = webView.url?.isDuckAIURL == true
        if isDuckAITab {
            DailyPixel.fireDailyAndCount(.aiChatTabDidTerminate, error: nil, withAdditionalParameters: [:])
        }
        DailyPixel.fireDailyAndCount(pixel: .webKitDidTerminate, pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)

        if let reasonName {
            DailyPixel.fireDailyAndCount(pixel: .webContentProcessTerminated(reason: reasonName))
            if isDuckAITab {
                DailyPixel.fireDailyAndCount(pixel: .aiChatWebContentProcessTerminated(reason: reasonName))
            }
        }

        delegate?.tabContentProcessDidTerminate(tab: self)
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        
        guard canDisplayJavaScriptAlert else {
            completionHandler()
            return
        }
        
        let alert = WebJSAlert(domain: frame.safeRequest?.url?.host
                               // in case the web view is navigating to another host
                               ?? webView.backForwardList.currentItem?.url.host
                               ?? self.url?.absoluteString
                               ?? "",
                               message: message,
                               alertType: .alert(handler: completionHandler))
        self.present(alert)
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        
        guard canDisplayJavaScriptAlert else {
            completionHandler(false)
            return
        }
        
        let alert = WebJSAlert(domain: frame.safeRequest?.url?.host
                               // in case the web view is navigating to another host
                               ?? webView.backForwardList.currentItem?.url.host
                               ?? self.url?.absoluteString
                               ?? "",
                               message: message,
                               alertType: .confirm(handler: completionHandler))
        self.present(alert)
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        
        guard canDisplayJavaScriptAlert else {
            completionHandler(nil)
            return
        }
        
        let alert = WebJSAlert(domain: frame.request.url?.host
                               // in case the web view is navigating to another host
                               ?? webView.backForwardList.currentItem?.url.host
                               ?? self.url?.absoluteString
                               ?? "",
                               message: prompt,
                               alertType: .text(handler: completionHandler,
                                                defaultText: defaultText))
        self.present(alert)
    }
    
}

// MARK: - UIGestureRecognizerDelegate
extension TabViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if isShowBarsTap(gestureRecognizer) {
            return true
        }
        return false
    }

    private func isShowBarsTap(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let y = gestureRecognizer.location(in: self.view).y
        return gestureRecognizer == showBarsTapGestureRecogniser && chromeDelegate?.isToolbarHidden == true && isBottom(yPosition: y)
    }

    private func isBottom(yPosition y: CGFloat) -> Bool {
        let webViewFrameInTabView = webView.convert(webView.bounds, to: view)
        let bottomOfWebViewInTabView = webViewFrameInTabView.maxY - webView.scrollView.contentInset.bottom

        return y > bottomOfWebViewInTabView
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == showBarsTapGestureRecogniser else {
            return false
        }

        // Don't delay tap gestures that are inside the onboarding dialog
        if let daxContextualOnboardingController,
           let otherView = otherRecognizer.view,
           otherView.isDescendant(of: daxContextualOnboardingController.view) {
            return false
        }

        if gestureRecognizer == showBarsTapGestureRecogniser,
            otherRecognizer is UITapGestureRecognizer {
            return true
        }

        return false
    }

    func requestFindInPage() {
        guard findInPage == nil else { return }
        findInPage = FindInPage(webView: webView)
        delegate?.tabDidRequestFindInPage(tab: self)
    }

    func refresh() {
        let url: URL?
        if isError || webView.url == nil {
            url = self.url
        } else {
            url = webView.url
        }
        
        requeryLogic.onRefresh()
        if isError || webView.url == nil, let url = url {
            load(url: url)
        } else {
            reload()
        }

        refreshCountSinceLoad += 1
        if let url {
            AppDependencyProvider.shared.pageRefreshMonitor.register(for: url)
        }
    }

    func zoomIn() {
        applyTextZoomLevel(textZoomCoordinator.textZoomLevel(forHost: webView.url?.host).incremented())
    }

    func zoomOut() {
        applyTextZoomLevel(textZoomCoordinator.textZoomLevel(forHost: webView.url?.host).decremented())
    }

    func resetTextZoom() {
        applyTextZoomLevel(appSettings.defaultTextZoomLevel)
    }

    private func applyTextZoomLevel(_ level: TextZoomLevel) {
        textZoomCoordinator.set(textZoomLevel: level, forHost: webView.url?.host)
        textZoomCoordinator.onTextZoomChange(applyToWebView: webView)
    }

}

// MARK: - UserContentControllerDelegate
extension TabViewController: DaxEasterEggDelegate {
    
    func daxEasterEggHandler(_ handler: DaxEasterEggHandling, didFindLogoURL logoURL: String?, for pageURL: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            Logger.daxEasterEgg.debug("Handler found logo - Page: \(pageURL), Logo: \(logoURL ?? "nil")")
            self.delegate?.tab(self, didExtractDaxEasterEggLogoURL: logoURL)
        }
    }
}

extension TabViewController: UserContentControllerDelegate {

    var userScripts: UserScripts? {
        userContentController.contentBlockingAssets?.userScripts as? UserScripts
    }
    private var findInPageScript: FindInPageUserScript? {
        userScripts?.findInPageScript
    }
    private var autofillUserScript: AutofillUserScript? {
        userScripts?.autofillUserScript
    }

    func userContentController(_ userContentController: UserContentController,
                               didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
                               userScripts: UserScriptsProvider,
                               updateEvent: ContentBlockerRulesManager.UpdateEvent) {
        guard let userScripts = userScripts as? UserScripts else { fatalError("Unexpected UserScripts") }

        userScripts.trackerProtectionSubfeature.delegate = self
        userScripts.autofillUserScript.emailDelegate = emailManager
        userScripts.autofillUserScript.vaultDelegate = vaultManager
        userScripts.autofillUserScript.passwordImportDelegate = credentialsImportManager
        userScripts.faviconScript.delegate = faviconUpdater
        userScripts.printingSubfeature.delegate = self
        userScripts.loginFormDetectionScript?.delegate = self
        userScripts.autoconsentUserScript.delegate = self
        userScripts.autoconsentUserScript.management = autoconsentManagement
        userScripts.contentScopeUserScript.delegate = self
        userScripts.serpSettingsUserScript.delegate = self
        userScripts.serpSettingsUserScript.setStore(keyValueStore)
        userScripts.serpSettingsUserScript.webView = webView
        
        userScripts.aiChatUserScript.setFireModeProvider { [weak self] in self?.tabModel.fireTab ?? false }
        userScripts.aiChatUserScript.setFocusChatInputHandler { [weak self] in
            guard let self else { return }
            (self.parent as? MainViewController)?.focusUnifiedToggleInputForActiveChat(from: self.webView)
        }
        userScripts.duckAiNativeStorageUserScript?.fireModeStorageProvider = { [weak self] in
            guard let self else { return .notFireMode }
            return .resolve(isFireMode: self.tabModel.fireTab,
                            handler: self.duckAiFireModeStorageHandler)
        }
        aiChatContentHandler.setup(with: userScripts.aiChatUserScript, webView: webView, displayMode: .fullTab)
        aiChatContextualSheetCoordinator.pageContextHandler.resubscribe()

        // Setup DaxEasterEgg handler only for DuckDuckGo search pages
        if daxEasterEggHandler == nil, let url = webView.url, url.isDuckDuckGoSearch {
            daxEasterEggHandler = DaxEasterEggHandler(webView: webView, logoCache: logoCache)
            daxEasterEggHandler?.delegate = self
        }

        // Special Error Page (SSL, Malicious Site protection)
        specialErrorPageNavigationHandler.setUserScript(userScripts.specialErrorPageUserScript)

        // Setup DuckPlayer Scripts
        userScripts.duckPlayer = duckPlayerNavigationHandler.duckPlayer

        // Set webView for legacy scripts only if not using native UI
        if duckPlayerNavigationHandler.duckPlayer.settings.nativeUI == false {
            userScripts.youtubeOverlayScript?.webView = webView
            userScripts.youtubePlayerUserScript?.webView = webView
        }
        
        breakageReportingSubfeature = BreakageReportingSubfeature(targetWebview: webView)
        userScripts.contentScopeUserScriptIsolated.registerSubfeature(delegate: breakageReportingSubfeature!)

        siteLoadingPerformanceSubfeature = SiteLoadingPerformanceSubfeature()
        userScripts.contentScopeUserScriptIsolated.registerSubfeature(delegate: siteLoadingPerformanceSubfeature!)

        adClickAttributionLogic.onRulesChanged(latestRules: ContentBlocking.shared.contentBlockingManager.currentRules)
        
        cachedMapper = nil
        cachedMapperVendor = nil
        cachedMapperAttributionTrackerData = nil

        let tdsKey = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        let notificationsTriggeringReload = [
            UserDefaultsFireproofing.Notifications.loginDetectionStateChanged,
            AppUserDefaults.Notifications.doNotSellStatusChange
        ]
        if updateEvent.changes[tdsKey]?.contains(.unprotectedSites) == true
            || notificationsTriggeringReload.contains(where: {
                updateEvent.changes[$0.rawValue]?.contains(.notification) == true
            }) {

            reload()
        }
    }

    @objc
    func onOpenInSafariFromErrorPage() {
        guard let safariRedirectLoopErrorURL else { return }
        openExternally(url: makeXSafariHTTPSURL(from: safariRedirectLoopErrorURL))
    }

    @objc
    func onReportBrokenSiteFromErrorPage() {
        DailyPixel.fireDailyAndCount(pixel: .webViewExternalSchemeNavigationSafariRedirectLoopErrorPageReportSiteBreakage, error: nil, withAdditionalParameters: [:])
        delegate?.tabDidRequestReportBrokenSite(tab: self)
    }

}

// MARK: - TrackerProtectionSubfeatureDelegate
extension TabViewController: TrackerProtectionSubfeatureDelegate {

    func trackerProtectionShouldProcessTrackers(_ subfeature: TrackerProtectionSubfeature) -> Bool {
        return privacyInfo?.isFor(self.url) ?? false
    }

    private func makeMapper(attributionTrackerData: TrackerData?, vendor: String?) -> TrackerProtectionEventMapper? {
        if let cachedMapper,
           cachedMapperVendor == vendor,
           cachedMapperAttributionTrackerData == attributionTrackerData {
            return cachedMapper
        }

        let rules = ContentBlocking.shared.contentBlockingManager.currentRules
        let tdsName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        guard let mainTrackerData = rules.first(where: { $0.name == tdsName })?.trackerData else { return nil }

        var supplementary: [TrackerData] = []
        if let attributionTrackerData {
            supplementary.append(attributionTrackerData)
        }

        let tld = AppDependencyProvider.shared.storageCache.tld
        let privacyConfig = ContentBlocking.shared.privacyConfigurationManager.privacyConfig
        let tempList = privacyConfig.tempUnprotectedDomains + privacyConfig.exceptionsList(forFeature: .contentBlocking)
        let mapper = TrackerProtectionEventMapper(tld: tld,
                                                  mainTrackerData: mainTrackerData,
                                                  supplementaryTrackerData: supplementary,
                                                  unprotectedSites: privacyConfig.userUnprotectedDomains,
                                                  tempList: tempList,
                                                  contentBlockingEnabled: privacyConfig.isEnabled(featureKey: .contentBlocking),
                                                  trackerAllowlist: privacyConfig.trackerAllowlist.entries)
        cachedMapper = mapper
        cachedMapperVendor = vendor
        cachedMapperAttributionTrackerData = attributionTrackerData
        return mapper
    }

    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didObserveResource observation: TrackerProtectionSubfeature.ResourceObservation) {
        guard let mapper = makeMapper(attributionTrackerData: subfeature.currentAttributionTrackerData,
                                      vendor: subfeature.currentAdClickAttributionVendor) else { return }

        if let detected = mapper.classifyResource(observation,
                                                   adClickAttributionVendor: subfeature.currentAdClickAttributionVendor) {
            userScriptDetectedTracker(detected)
        } else if let thirdParty = mapper.makeThirdPartyRequest(from: observation) {
            privacyInfo?.trackerInfo.add(detectedThirdPartyRequest: thirdParty)
        }
    }

    func trackerProtection(_ subfeature: TrackerProtectionSubfeature,
                           didInjectSurrogate surrogate: TrackerProtectionSubfeature.SurrogateInjection) {
        guard let url = url,
              let mapper = makeMapper(attributionTrackerData: subfeature.currentAttributionTrackerData,
                                      vendor: subfeature.currentAdClickAttributionVendor),
              let detected = mapper.classifySurrogate(surrogate,
                                                      adClickAttributionVendor: subfeature.currentAdClickAttributionVendor),
              let host = mapper.surrogateHost(from: surrogate) else { return }

        // C-S-S always pairs `surrogateInjected` with a preceding `resourceObserved` for the same
        // URL, so `userScriptDetectedTracker` already ran via `didObserveResource`. Calling it
        // again here would double-count `privacyStats` and re-fire dax/attribution side-effects.
        privacyInfo?.trackerInfo.addInstalledSurrogateHost(host, for: detected, onPageWithURL: url)
    }

    fileprivate func userScriptDetectedTracker(_ tracker: DetectedRequest) {
        guard let url = url else { return }

        adClickAttributionLogic.onRequestDetected(request: tracker)

        if tracker.isBlocked && fireWoFollowUp {
            fireWoFollowUp = false
            Pixel.fire(pixel: .daxDialogsWithoutTrackersFollowUp)
        }

        privacyInfo?.trackerInfo.addDetectedTracker(tracker, onPageWithURL: url)

        guard tracker.isBlocked,
              let entityName = tracker.entityName else {
            return
        }

        Task {
            await privacyStats.recordBlockedTracker(entityName)
        }
    }
}

// MARK: - PrintingSubfeatureDelegate
extension TabViewController: PrintingSubfeatureDelegate {

    func printingSubfeatureDidRequestPrint(for frameHandle: Any?, in webView: WKWebView?) {
        // Use explicit if-let to avoid type inference issues with IUO (WKWebView!)
        let targetWebView: WKWebView
        if let providedWebView = webView {
            targetWebView = providedWebView
        } else if let ownWebView = self.webView {
            targetWebView = ownWebView
        } else {
            return
        }

        let controller = UIPrintInteractionController.shared
        controller.printFormatter = targetWebView.viewPrintFormatter()
        controller.present(animated: true, completionHandler: nil)
    }

}

// MARK: - ContentScopeUserScriptDelegate
extension TabViewController: ContentScopeUserScriptDelegate {
    func contentScopeUserScript(_ script: BrowserServicesKit.ContentScopeUserScript, didReceiveDebugFlag debugFlag: String) {
        privacyInfo?.addDebugFlag(debugFlag)
    }
}

// MARK: - AutoconsentUserScriptDelegate
extension TabViewController: AutoconsentUserScriptDelegate {
    
    func autoconsentUserScript(consentStatus: CookieConsentInfo) {
        privacyInfo?.cookieConsentManaged = consentStatus
    }
}


@available(iOS 18.4, *)
extension PrivacyInfo {
    func updateCookieConsentManagedForWebExtensionDashboardState(url refreshURL: URL, consentStatus: ConsentStatusInfo) {
        guard url.host == refreshURL.host,
              normalizedPath(url.path) == normalizedPath(refreshURL.path) else {
            return
        }

        cookieConsentManaged = consentStatus.toCookieConsentInfo()
    }

    private func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}

// MARK: - ConsentStatusInfo to CookieConsentInfo Conversion

@available(iOS 18.4, *)
extension ConsentStatusInfo {
    func toCookieConsentInfo() -> CookieConsentInfo {
        CookieConsentInfo(
            consentManaged: consentManaged,
            cosmetic: cosmetic,
            optoutFailed: optoutFailed,
            selftestFailed: selftestFailed,
            consentReloadLoop: consentReloadLoop,
            consentRule: consentRule,
            consentHeuristicEnabled: consentHeuristicEnabled,
            cpmDashboardState: .applied,
            cpmStage: cpmStage.flatMap(CookieConsentCPMStage.init(rawValue:)),
            cpmErrors: cpmErrors,
            cpmQueueSize: cpmQueueSize,
            cpmConfigVersion: cpmConfigVersion
        )
    }
}

// MARK: - AdClickAttributionLogicDelegate
extension TabViewController: AdClickAttributionLogicDelegate {

    func attributionLogic(_ logic: AdClickAttributionLogic,
                          didRequestRuleApplication rules: ContentBlockerRulesManager.Rules?,
                          forVendor vendor: String?) {
        let attributedTempListName = AdClickAttributionRulesProvider.Constants.attributedTempRuleListName

        guard privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking)
        else {
            userContentController.removeLocalContentRuleList(withIdentifier: attributedTempListName)
            userScripts?.trackerProtectionSubfeature.currentAdClickAttributionVendor = nil
            userScripts?.trackerProtectionSubfeature.currentAttributionTrackerData = nil
            return
        }

        userScripts?.trackerProtectionSubfeature.currentAdClickAttributionVendor = vendor
        userScripts?.trackerProtectionSubfeature.currentAttributionTrackerData = rules?.trackerData

        let globalListName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        let globalAttributionListName = AdClickAttributionRulesSplitter.blockingAttributionRuleListName(forListNamed: globalListName)

        if let rules, vendor != nil {
            userContentController.installLocalContentRuleList(rules.rulesList, identifier: attributedTempListName)
            try? userContentController.disableGlobalContentRuleList(withIdentifier: globalAttributionListName)
        } else if vendor == nil {
            // No active attribution — tear down any previously installed local list and
            // re-enable the global attribution list, even when `rules` is nil (e.g. on the
            // initial pre-compilation call from `AdClickAttributionLogic.applyRules`).
            userContentController.removeLocalContentRuleList(withIdentifier: attributedTempListName)
            try? userContentController.enableGlobalContentRuleList(withIdentifier: globalAttributionListName)
        }
    }

}

// MARK: - Themable
extension TabViewController {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.backgroundColor
        error?.backgroundColor = theme.backgroundColor
        errorHeader.textColor = theme.barTintColor
        errorMessage.textColor = theme.barTintColor

        if let webView {
            webView.scrollView.refreshControl?.backgroundColor = theme.mainViewBackgroundColor
            webView.scrollView.refreshControl?.tintColor = .secondaryLabel
        }
    }
    
}

// MARK: - NSError+failedUrl
extension NSError {

    var failedUrl: URL? {
        return userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }
    
}

extension TabViewController: SecureVaultManagerDelegate {

    private func presentSavePasswordModal(with vault: SecureVaultManager, credentials: SecureVaultModels.WebsiteCredentials, backfilled: Bool) {
        guard AutofillSettingStatus.isAutofillEnabledInSettings,
              featureFlagger.isFeatureOn(.autofillCredentialsSaving),
              let autofillUserScript = autofillUserScript else { return }

        let manager = SaveAutofillLoginManager(credentials: credentials, vaultManager: vault, autofillScript: autofillUserScript)
        manager.prepareData { [weak self] in
            guard let self = self else { return }
            
            let saveLoginController = SaveLoginViewController(credentialManager: manager,
                                                              appSettings: self.appSettings,
                                                              domainLastShownOn: self.domainSaveLoginPromptLastShownOn,
                                                              backfilled: backfilled)
            self.domainSaveLoginPromptLastShownOn = self.url?.host
            saveLoginController.delegate = self

            if let presentationController = saveLoginController.presentationController as? UISheetPresentationController {
                if #available(iOS 16.0, *) {
                    presentationController.detents = [.custom(resolver: { _ in
                        saveLoginController.viewModel?.minHeight
                    })]
                } else {
                    presentationController.detents = [.medium()]
                }
                presentationController.prefersScrollingExpandsWhenScrolledToEdge = false
            }

            self.present(saveLoginController, animated: true, completion: nil)
        }
    }
    
    private func presentSaveCreditCardModal(with vault: SecureVaultManager, creditCard: SecureVaultModels.CreditCard) {
        guard CreditCardValidation.isValidCardNumber(creditCard.cardNumber) else {
            Logger.autofill.debug("Invalid credit card number, not presenting save prompt")
            return
        }
        
        let saveCreditCardController = SaveCreditCardViewController(creditCard: creditCard, accountDomain: self.url?.host ?? "", domainLastShownOn: self.domainSaveCreditCardPromptLastShownOn)
        self.domainSaveCreditCardPromptLastShownOn = self.url?.host
        saveCreditCardController.delegate = self
        if let presentationController = saveCreditCardController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    saveCreditCardController.viewModel.minHeight
                })]
            } else {
                presentationController.detents = [.medium()]
            }
            presentationController.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        
        self.present(saveCreditCardController, animated: true, completion: nil)
    }
    
    func secureVaultError(_ error: SecureStorageError) {
        SecureVaultReporter().secureVaultError(error)
    }

    func secureVaultKeyStoreEvent(_ event: SecureStorageKeyStoreEvent) {
        SecureVaultReporter().secureVaultKeyStoreEvent(event)
    }

    private func isCreditCardAutofillEnabled() -> Bool {
        return AutofillSettingStatus.isCreditCardAutofillEnabledInSettings &&
        featureFlagger.isFeatureOn(.autofillCreditCards) &&
        !isLinkPreview
    }
    
    func secureVaultManagerIsEnabledStatus(_ manager: SecureVaultManager, forType type: AutofillType?) -> Bool {
        let isCredentialsEnabled = AutofillSettingStatus.isAutofillEnabledInSettings &&
                        featureFlagger.isFeatureOn(.autofillCredentialInjecting) &&
                        !isLinkPreview
        let isCreditCardsEnabled = isCreditCardAutofillEnabled()

        let isDataProtected = !UIApplication.shared.isProtectedDataAvailable
        if (isCredentialsEnabled || isCreditCardsEnabled) && isDataProtected {
            DailyPixel.fire(pixel: .secureVaultIsEnabledCheckedWhenEnabledAndDataProtected,
                       withAdditionalParameters: [PixelParameters.isDataProtected: "true"])
        }
        return isCredentialsEnabled || isCreditCardsEnabled
    }

    func secureVaultManagerShouldSaveData(_ manager: SecureVaultManager) -> Bool {
        return secureVaultManagerIsEnabledStatus(manager, forType: nil)
    }

    func secureVaultManager(_ vault: SecureVaultManager,
                            promptUserToStoreAutofillData data: AutofillData,
                            withTrigger trigger: AutofillUserScript.GetTriggerType?) {
        
        if let credentials = data.credentials,
            AutofillSettingStatus.isAutofillEnabledInSettings,
            featureFlagger.isFeatureOn(.autofillCredentialsSaving) {
            if data.automaticallySavedCredentials, let trigger = trigger {
                if trigger == AutofillUserScript.GetTriggerType.passwordGeneration {
                    return
                } else if trigger == AutofillUserScript.GetTriggerType.formSubmission {
                    guard let accountID = credentials.account.id,
                          let accountIdInt = Int64(accountID) else { return }
                    confirmSavedCredentialsFor(credentialID: accountIdInt, message: UserText.autofillLoginSavedToastMessage)
                    return
                }
            }

            saveLoginPromptIsPresenting = true

            // Add a delay to allow propagation of pointer events to the page
            // see https://app.asana.com/0/1202427674957632/1202532842924584/f
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.presentSavePasswordModal(with: vault, credentials: credentials, backfilled: data.backfilled)
            }
        } else if let creditCard = data.creditCard, isCreditCardAutofillEnabled() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.presentSaveCreditCardModal(with: vault, creditCard: creditCard)
            }
            
        }
    }

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCredentialsForDomain domain: String,
                            withAccounts accounts: [SecureVaultModels.WebsiteAccount],
                            withTrigger trigger: AutofillUserScript.GetTriggerType,
                            onAccountSelected: @escaping (SecureVaultModels.WebsiteAccount?) -> Void,
                            completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {
  
        if !AutofillSettingStatus.isAutofillEnabledInSettings, featureFlagger.isFeatureOn(.autofillCredentialInjecting) {
            completionHandler(nil)
            return
        }

        // if user is interacting with the searchBar, don't show the autofill prompt since it will overlay the keyboard
        if let parent = parent as? MainViewController, parent.viewCoordinator.omniBar.isTextFieldEditing {
            completionHandler(nil)
            return
        }

        if accounts.count > 0 {
            let accountMatches = autofillWebsiteAccountMatcher.findDeduplicatedSortedMatches(accounts: accounts, for: domain)

            presentAutofillPromptViewController(accountMatches: accountMatches, domain: domain, trigger: trigger, useLargeDetent: false) { [weak self] account in
                onAccountSelected(account)

                guard let domain = account?.domain else { return }
                Task {
                    await self?.credentialIdentityStoreManager.updateCredentialStore(for: domain)
                }
            } completionHandler: { account in
                if account != nil {
                    NotificationCenter.default.post(name: .autofillFillEvent, object: nil)
                }
                completionHandler(account)
            }
        } else {
            completionHandler(nil)
        }
    }

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToAutofillCreditCardWith creditCards: [SecureVaultModels.CreditCard],
                            withTrigger trigger: AutofillUserScript.GetTriggerType,
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        guard isCreditCardAutofillEnabled() else {
            completionHandler(nil)
            return
        }

        // if user is interacting with the searchBar, don't show the autofill prompt since it will overlay the keyboard
        if let parent = parent as? MainViewController, parent.viewCoordinator.omniBar.isTextFieldEditing {
            completionHandler(nil)
            return
        }

        promptToFill(withCreditCards: creditCards) { card in
            completionHandler(card)
        }
    }

    func secureVaultManager(_: SecureVaultManager,
                            didFocusFieldFor mainType: AutofillUserScript.GetAutofillDataMainType,
                            withCreditCards creditCards: [SecureVaultModels.CreditCard],
                            completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        guard isCreditCardAutofillEnabled(), mainType == .creditCards else {
            completionHandler(nil)
            cleanupInputAccessoryView()
            return
        }

        promptToFill(withCreditCards: creditCards) { card in
            completionHandler(card)
        }
    }

    private func promptToFill(withCreditCards creditCards: [SecureVaultModels.CreditCard], completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        if domainFillCreditCardPromptLastShownOn != url?.host {
            AppDependencyProvider.shared.autofillLoginSession.endSession()
            self.domainFillCreditCardPromptLastShownOn = self.url?.host
            resetCreditCardPrompt()
        }

        guard creditCards.count > 0 else {
            completionHandler(nil)
            cleanupInputAccessoryView()
            return
        }

        if shouldShowCreditCardPrompt {
            fillCreditCardsPromptIsPresenting = true
            presentAutofillPromptViewController(creditCards: creditCards) { [weak self] creditCard in
                completionHandler(creditCard)
                self?.fillCreditCardsPromptIsPresenting = false

                if creditCard != nil {
                    NotificationCenter.default.post(name: .autofillFillEvent, object: nil)
                }
            }
            shouldShowCreditCardPrompt = false
            autofillCreditCardAccessoryView?.updateCreditCards(creditCards)
        } else {
            addCreditCardInputAccessoryView(creditCards: creditCards) { card in
                completionHandler(card)
            }
        }
    }

    private func presentAutofillPromptViewController(creditCards: [SecureVaultModels.CreditCard],
                                                     completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        // Ensure keyboard doesn't block prompt
        dismissKeyboardIfPresent()

        let creditCardPromptViewController = CreditCardPromptViewController(creditCards: creditCards) { creditCard in
            completionHandler(creditCard)
        }

        if let presentationController = creditCardPromptViewController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    AutofillViews.loginPromptMinHeight
                })]
            } else {
                presentationController.detents =  [.medium()]
            }
        }

        self.present(creditCardPromptViewController, animated: true, completion: nil)
    }

    private func addCreditCardInputAccessoryView(creditCards: [SecureVaultModels.CreditCard], completionHandler: @escaping (SecureVaultModels.CreditCard?) -> Void) {
        guard let webView = webView as? WebView, let autofillCreditCardAccessoryView = autofillCreditCardAccessoryView else {
            completionHandler(nil)
            return
        }
        autofillCreditCardAccessoryView.updateCreditCards(creditCards)
        webView.setAccessoryContentView(autofillCreditCardAccessoryView)

        autofillCreditCardAccessoryView.onCardSelected = { [weak self] card in
            completionHandler(card)
            if card == nil {
                self?.dismissKeyboardIfPresent()
            } else {
                NotificationCenter.default.post(name: .autofillFillEvent, object: nil)
            }

            self?.cleanupInputAccessoryView()
        }
    }

    private func cleanupInputAccessoryView() {
        guard isCreditCardAutofillEnabled(), let webView = webView as? WebView else {
            return
        }

        webView.removeAccessoryContentViewIfNecessary()
    }

    private func resetCreditCardPrompt() {
        shouldShowCreditCardPrompt = true
    }

    func secureVaultManager(_: SecureVaultManager,
                            promptUserWithGeneratedPassword password: String,
                            completionHandler: @escaping (Bool) -> Void) {

        // Ensure keyboard doesn't block prompt
        dismissKeyboardIfPresent()

        var responseSent: Bool = false

        let sendResponse: (Bool) -> Void = { useGeneratedPassword in
            guard !responseSent else { return }
            responseSent = true
            completionHandler(useGeneratedPassword)
        }

        let passwordGenerationPromptViewController = PasswordGenerationPromptViewController(generatedPassword: password) { useGeneratedPassword in
            sendResponse(useGeneratedPassword)
        }

        if let presentationController = passwordGenerationPromptViewController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    AutofillViews.passwordGenerationMinHeight
                })]
            } else {
                presentationController.detents = [.medium()]
            }
        }

        self.present(passwordGenerationPromptViewController, animated: true)
    }

    /// Using Bool for detent size parameter to be backward compatible with iOS 14
    func presentAutofillPromptViewController(accountMatches: AccountMatches,
                                             domain: String,
                                             trigger: AutofillUserScript.GetTriggerType,
                                             useLargeDetent: Bool,
                                             onAccountSelected: @escaping (SecureVaultModels.WebsiteAccount?) -> Void,
                                             completionHandler: @escaping (SecureVaultModels.WebsiteAccount?) -> Void) {

        // Ensure keyboard doesn't block prompt
        dismissKeyboardIfPresent()

        var responseSent: Bool = false

        let sendResponse: (SecureVaultModels.WebsiteAccount?) -> Void = { [weak self] account in
            guard !responseSent else { return }
            responseSent = true
            completionHandler(account)

            if account != nil {
                self?.extensionPromotionManager.shouldShowPromotion(for: .browser, totalCredentialsCount: nil, completion: { [weak self] shouldShow in
                    if shouldShow {
                        self?.shouldShowAutofillExtensionPrompt = true
                        self?.detectedLoginURL = self?.webView.url
                    } else {
                        self?.shouldShowAutofillExtensionPrompt = false
                        self?.detectedLoginURL = nil
                    }
                })
            } else {
                self?.shouldShowAutofillExtensionPrompt = false
                self?.detectedLoginURL = nil
            }
        }

        let autofillPromptViewController = AutofillLoginPromptViewController(accounts: accountMatches,
                                                                             domain: domain,
                                                                             trigger: trigger,
                                                                             onAccountSelected: { account in
            onAccountSelected(account)
        }, completion: { account, showExpanded in
            if showExpanded {
                self.presentAutofillPromptViewController(accountMatches: accountMatches,
                                                         domain: domain,
                                                         trigger: trigger,
                                                         useLargeDetent: showExpanded,
                                                         onAccountSelected: { account in
                    onAccountSelected(account)
                },
                                                         completionHandler: { account in
                    sendResponse(account)
                })
            } else {
                sendResponse(account)
            }
        })

        if let presentationController = autofillPromptViewController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    AutofillViews.loginPromptMinHeight
                })]
            } else {
                presentationController.detents = useLargeDetent ? [.large()] : [.medium()]
            }
        }

        self.present(autofillPromptViewController, animated: true, completion: nil)
    }

    func secureVaultManager(_: SecureVaultManager,
                            promptUserToImportCredentialsForDomain domain: String,
                            completionHandler: @escaping (Bool) -> Void) {
        guard let eTLDplus1 = storageCache.tld.eTLDplus1(url?.host), credentialsImportManager.domainPasswordImportLastShownOn != eTLDplus1 else {
            completionHandler(false)
            return
        }

        // Ensure keyboard doesn't block prompt
        dismissKeyboardIfPresent()

        credentialsImportManager.domainPasswordImportLastShownOn = eTLDplus1

        let promptViewController = ImportPasswordsPromptViewController(keyValueStore: keyValueStore) { [weak self] startImport in
            guard startImport, let self = self else {
                completionHandler(false)
                return
            }

            self.delegate?.tab(self, didRequestDataImport: .inBrowserPromo, onFinished: { [weak self] in
                Pixel.fire(pixel: .importCredentialsFlowEnded)
                completionHandler(true)

                if let domainPasswordImportLastShownOn = self?.credentialsImportManager.domainPasswordImportLastShownOn,
                    let autofillUserScript = self?.autofillUserScript {
                    self?.vaultManager.autofillUserScript(autofillUserScript, didRequestAccountsForDomain: domainPasswordImportLastShownOn) { accounts, _ in
                        if !accounts.isEmpty {
                            Pixel.fire(pixel: .importCredentialsFlowHadCredentials)
                        }
                    }
                }
            }, onCancelled: {
                Pixel.fire(pixel: .importCredentialsFlowCancelled)
                completionHandler(false)
            })
        }

        if let presentationController = promptViewController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    AutofillViews.loginPromptMinHeight
                })]
            } else {
                presentationController.detents =  [.medium()]
            }
        }

        self.present(promptViewController, animated: true, completion: nil)
    }

    func presentAutofillExtensionPrompt() {
        guard let eTLDplus1 = storageCache.tld.eTLDplus1(url?.host), extensionPromotionManager.domainExtensionPromptLastShownOn != eTLDplus1 else {
            return
        }

        // Ensure keyboard doesn't block prompt
        dismissKeyboardIfPresent()

        extensionPromotionManager.domainExtensionPromptLastShownOn = eTLDplus1

        let promptViewController = AutofillExtensionPromptViewController(extensionPromotionManager: extensionPromotionManager) { [weak self] enableExtension in
            if enableExtension {
                guard let mainVC = self?.view.window?.rootViewController as? MainViewController else { return }
                mainVC.segueToSettingsAutofillWith(account: nil, card: nil, showSettingsScreen: .extensionManagement, source: .extensionEnablePrompt)
            }
        }

        if let presentationController = promptViewController.presentationController as? UISheetPresentationController {
            if #available(iOS 16.0, *) {
                presentationController.detents = [.custom(resolver: { _ in
                    AutofillViews.loginPromptMinHeight
                })]
            } else {
                presentationController.detents =  [.medium()]
            }
        }

        self.present(promptViewController, animated: true, completion: nil)

    }

    // Used on macOS to request authentication for individual autofill items
    func secureVaultManager(_: BrowserServicesKit.SecureVaultManager,
                            isAuthenticatedFor type: BrowserServicesKit.AutofillType,
                            completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func secureVaultManager(_: SecureVaultManager, didAutofill type: AutofillType, withObjectId objectId: String) {
        // No-op, don't need to do anything here
    }

    func secureVaultManager(_: SecureVaultManager, didRequestAuthenticationWithCompletionHandler: @escaping (Bool) -> Void) {
        // We don't have auth yet
    }

    func secureVaultManager(_: BrowserServicesKit.SecureVaultManager, didRequestCreditCardsManagerForDomain domain: String) {
    }

    func secureVaultManager(_: BrowserServicesKit.SecureVaultManager, didRequestIdentitiesManagerForDomain domain: String) {
    }

    func secureVaultManager(_: BrowserServicesKit.SecureVaultManager, didRequestPasswordManagerForDomain domain: String) {
    }

    func secureVaultManager(_: SecureVaultManager, didRequestRuntimeConfigurationForDomain domain: String, completionHandler: @escaping (String?) -> Void) {
        // didRequestRuntimeConfigurationForDomain fires for every iframe loaded on a website
        // so caching the runtime configuration for the domain to prevent unnecessary re-building of the configuration
        if let runtimeConfigurationForDomain = cachedRuntimeConfigurationForDomain[domain] as? String {
            completionHandler(runtimeConfigurationForDomain)
            return
        }

        do {
            let runtimeConfiguration =
            try DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfigurationManager,
                                                      properties: buildContentScopePropertiesForDomain(domain))
            .build()
            .buildRuntimeConfigResponse()

            cachedRuntimeConfigurationForDomain = [domain: runtimeConfiguration]
            completionHandler(runtimeConfiguration)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to build DefaultAutofillSourceProvider: \(error.localizedDescription)")
        }
    }

    private func buildContentScopePropertiesForDomain(_ domain: String) -> ContentScopeProperties {
        var supportedFeatures = ContentScopeFeatureToggles.supportedFeaturesOniOS

        if AutofillSettingStatus.isAutofillEnabledInSettings,
           featureFlagger.isFeatureOn(.autofillCredentialsSaving),
           autofillNeverPromptWebsitesManager.hasNeverPromptWebsitesFor(domain: domain) {
            supportedFeatures.passwordGeneration = false
        }

        return ContentScopeProperties(gpcEnabled: appSettings.sendDoNotSell,
                                      sessionKey: autofillUserScript?.sessionKey ?? "",
                                      messageSecret: autofillUserScript?.messageSecret ?? "",
                                      featureToggles: supportedFeatures)
    }

    func secureVaultManager(_: SecureVaultManager, didReceivePixel pixel: AutofillUserScript.JSPixel) {
        guard !pixel.isEmailPixel else {
            // The iOS app uses a native email autofill UI, and sends its pixels separately. Ignore pixels sent from the JS layer.
            return
        }

        Pixel.fire(pixel: .autofillJSPixelFired(pixel))
    }
    
}

extension TabViewController: SaveLoginViewControllerDelegate {

    private func saveCredentials(_ credentials: SecureVaultModels.WebsiteCredentials, withSuccessMessage message: String) {
        saveLoginPromptLastDismissed = Date()
        saveLoginPromptIsPresenting = false

        do {
            let credentialID = try SaveAutofillLoginManager.saveCredentials(credentials,
                                                                            with: AutofillSecureVaultFactory)
            confirmSavedCredentialsFor(credentialID: credentialID, message: message)
            syncService.scheduler.notifyDataChanged()

            NotificationCenter.default.post(name: .autofillSaveEvent, object: nil)
        } catch {
            Logger.general.error("failed to store credentials: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func confirmSavedCredentialsFor(credentialID: Int64, message: String) {
        do {
            let vault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
            
            if let newCredential = try vault.websiteCredentialsFor(accountId: credentialID) {
                DispatchQueue.main.async {
                    let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
                    ActionMessageView.present(message: message,
                                              actionTitle: UserText.autofillLoginSaveToastActionButton,
                                              presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom),
                                              onAction: {

                        self.showLoginDetails(with: newCredential.account, source: .viewSavedLoginPrompt)
                    })
                    self.favicons.loadFavicon(forDomain: newCredential.account.domain, intoCache: .fireproof, fromCache: .tabs)
                }

                guard let domain = newCredential.account.domain else { return }
                Task {
                    await credentialIdentityStoreManager.updateCredentialStore(for: domain)
                }
            }
        } catch {
            Logger.general.error("failed to fetch credentials: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func saveLoginViewController(_ viewController: SaveLoginViewController, didSaveCredentials credentials: SecureVaultModels.WebsiteCredentials) {
        saveCredentials(credentials, withSuccessMessage: UserText.autofillLoginSavedToastMessage)
    }
    
    func saveLoginViewController(_ viewController: SaveLoginViewController, didUpdateCredentials credentials: SecureVaultModels.WebsiteCredentials) {
        saveCredentials(credentials, withSuccessMessage: UserText.autofillLoginUpdatedToastMessage)
    }
    
    func saveLoginViewControllerDidCancel(_ viewController: SaveLoginViewController) {
        saveLoginPromptLastDismissed = Date()
        saveLoginPromptIsPresenting = false
    }

    func saveLoginViewController(_ viewController: SaveLoginViewController, didRequestNeverPromptForWebsite domain: String) {
        saveLoginPromptLastDismissed = Date()
        saveLoginPromptIsPresenting = false

        do {
            _ = try autofillNeverPromptWebsitesManager.saveNeverPromptWebsite(domain)
        } catch {
            Logger.general.error("failed to save never prompt for website: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func saveLoginViewControllerConfirmKeepUsing(_ viewController: SaveLoginViewController) {
        Pixel.fire(pixel: .autofillLoginsFillLoginInlineDisableSnackbarShown)
        DispatchQueue.main.async {
            let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
            ActionMessageView.present(message: UserText.autofillDisablePromptMessage,
                                      actionTitle: UserText.autofillDisablePromptAction,
                                      presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom),
                                      duration: 4.0,
                                      onAction: { [weak self] in
                Pixel.fire(pixel: .autofillLoginsFillLoginInlineDisableSnackbarOpenSettings)
                guard let mainVC = self?.view.window?.rootViewController as? MainViewController else { return }
                mainVC.segueToSettingsAutofillWith(account: nil, card: nil, source: .saveLoginDisablePrompt)
            })
            Pixel.fire(pixel: .autofillCardsSaveDisableSnackbarShown)
        }
    }
}

extension TabViewController: SaveCreditCardViewControllerDelegate {
    func saveCreditCardViewController(_ viewController: SaveCreditCardViewController, didSaveCreditCard card: SecureVaultModels.CreditCard) {
        let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
        ActionMessageView.present(message: UserText.autofillCreditCardSavedToastMessage,
                                  actionTitle: UserText.autofillLoginSaveToastActionButton,
                                  presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom),
                                  onAction: { [weak self] in
            guard let self = self else { return }
            self.delegate?.tab(self, didRequestSettingsToCreditCards: card, source: .viewSavedCreditCardPrompt)
        })
        syncService.scheduler.notifyDataChanged()
    }
    
    func saveCreditCardViewControllerConfirmKeepUsing(_ viewController: SaveCreditCardViewController) {
        DispatchQueue.main.async {
            let addressBarBottom = self.appSettings.currentAddressBarPosition.isBottom
            ActionMessageView.present(message: UserText.autofillCreditCardsDisablePromptMessage,
                                      actionTitle: UserText.autofillDisablePromptAction,
                                      presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom),
                                      duration: 4.0,
                                      onAction: { [weak self] in
                
                guard let mainVC = self?.view.window?.rootViewController as? MainViewController else { return }
                mainVC.segueToSettingsAutofillWith(account: nil, card: nil, source: .saveCreditCardDisablePrompt)
                Pixel.fire(pixel: .autofillCardsSaveDisableSnackbarOpenSettings)
            })
        }
    }
}

extension TabViewController: OnboardingNavigationDelegate {

    func searchFromOnboarding(for query: String) {
        delegate?.tab(self, didRequestLoadQuery: query)
    }

    func navigateFromOnboarding(to url: URL) {
        delegate?.tab(self, didRequestLoadURL: url)
    }

}

extension TabViewController: ContextualOnboardingEventDelegate {

    func didAcknowledgeContextualOnboardingSearch() {
        contextualOnboardingLogic.setSearchMessageSeen()
    }

    func didAcknowledgeContextualOnboardingTrackersDialog() {
        // Store when Fire contextual dialog is shown to decide if final dialog needs to be shown.
        contextualOnboardingLogic.setFireEducationMessageSeen()
        delegate?.tabDidRequestFireButtonPulse(tab: self)
    }

    func didShowContextualOnboardingTrackersDialog() {
        guard contextualOnboardingLogic.shouldShowPrivacyButtonPulse else { return }
        
        delegate?.tabDidRequestPrivacyDashboardButtonPulse(tab: self, animated: true)
    }

    func didTapDismissContextualOnboardingAction() {
        // Reset last visited onboarding site and last dax dialog shown.
        contextualOnboardingLogic.setDaxDialogDismiss()

        dismissContextualOnboardingIfNeeded()

        // Chat-first path: after the user taps "Got it" on the trackers-blocked dialog the
        // phase transitions to .trackerToEOJ. Open a new tab so the NTP can surface the
        // "You've got this!" end-of-journey dialog via presentChatPathOnboardingCompletionIfNeeded.
        // setDaxDialogDismiss() does not affect chatPathPhase, so the check is still valid here.
        if contextualOnboardingLogic.chatPathPhase == .trackerToEOJ {
            delegate?.tabDidRequestNewTab(self)
        }
    }

    func didNavigateAwayFromContextualOnboardingDialog() {
        // Collapse the dialog immediately so the user isn't left looking at the visit-site bubble
        // while the chosen page is loading. Crucially this does NOT call `setDaxDialogDismiss()` —
        // we want the natural next contextual spec (trackers / no-trackers / etc.) to surface
        // once the page finishes loading, which depends on `lastShownDaxDialogType` /
        // `lastVisitedOnboardingWebsiteURL` not being cleared.
        contextualOnboardingPresenter.dismissContextualOnboardingIfNeeded(from: self)

        // Chat-first path: open a new tab so the NTP can surface the "You've got this!" end-of-journey dialog.
        if contextualOnboardingLogic.chatPathPhase == .trackerToEOJ {
            delegate?.tabDidRequestNewTab(self)
        }
    }

}

extension WKWebView {

    func load(_ url: URL, in frame: WKFrameInfo?) {
        evaluateJavaScript("window.location.href='" + url.absoluteString + "'", in: frame, in: .page)
    }

}

// MARK: - SpecialErrorPageNavigationDelegate

extension TabViewController: SpecialErrorPageNavigationDelegate {

    func closeSpecialErrorPageTab(shouldCreateNewEmptyTab: Bool) {
        let behavior: TabClosingBehavior = shouldCreateNewEmptyTab ? .createEmptyTabAtSamePosition : .onlyClose
        delegate?.tabDidRequestClose(tabModel, behavior: behavior, clearTabHistory: true)
    }
}

// MARK: - DuckPlayerTabNavigationHandling

// This Protocol allows DuckPlayerHandler access tabs
extension TabViewController: DuckPlayerTabNavigationHandling {
    
    func openTab(for url: URL) {
        delegate?.tab(self,
                      didRequestNewTabForUrl: url,
                      openedByPage: true,
                      inheritingAttribution: adClickAttributionLogic.state)
        
    }
    
    func closeTab() {
        if openingTab != nil {
            delegate?.tabDidRequestClose(self)
            return
        }
    }
    
}

private extension TabViewController {

    func restoreInteractionStateToWebView(_ interactionStateData: Data?) -> Bool {
        var didRestoreWebViewState = false
        if let interactionStateData {
            let startTime = CFAbsoluteTimeGetCurrent()
            webView.interactionState = interactionStateData
            if webView.url != nil {
                self.url = tabModel.link?.url
                didRestoreWebViewState = true
                preventUniversalLinksOnce = true
                tabInteractionStateSource?.saveState(webView.interactionState, for: tabModel)
            } else {
                Pixel.fire(pixel: .tabInteractionStateFailedToRestore)
            }

            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            Pixel.fire(pixel: .tabInteractionStateRestorationTime(Pixel.Event.BucketAggregation(number: timeElapsed)))
        }

        return didRestoreWebViewState
    }
}

// Landscape/Portrait mode customizations
extension TabViewController {
    
    /// Stores WebView settings and
    /// Updates its properties when displaying video in landscape mode
    // This is used by DuckPlayer when rotating to landscape
    func setupWebViewForLandscapeVideo() {
        guard let webView = webView else { return }
        
        // Store original settings
        savedViewSettings = ViewSettings(
            viewBackground: view.backgroundColor,
            webViewBackground: webView.backgroundColor,
            webViewOpaque: webView.isOpaque,
            scrollViewBackground: webView.scrollView.backgroundColor
        )
        
        // Apply landscape settings
        view.backgroundColor = .black
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.backgroundColor = .black
    }
    
    /// Resets the webview to its original settings
    /// This is used by DuckPlayer when rotating back to portrait
    func setupWebViewForPortraitVideo() {
        guard let webView = webView else { return }
        
        // Restore original settings if they were stored
        let settings = savedViewSettings ?? ViewSettings.default
        view.backgroundColor = settings.viewBackground
        webView.backgroundColor = settings.webViewBackground
        webView.isOpaque = settings.webViewOpaque
        webView.scrollView.backgroundColor = settings.scrollViewBackground
        
        // Clear stored settings
        savedViewSettings = nil
    }
}

extension TabViewController: Navigatable {
    public var canGoBack: Bool {
        let webViewCanGoBack = webView.canGoBack
        let navigatedToError = webView.url != nil && isError
        return webViewCanGoBack || navigatedToError || openingTab != nil
    }

    public var canGoForward: Bool {
        let webViewCanGoForward = webView.canGoForward
        return webViewCanGoForward && !isError
    }

}

extension TabViewController: DuckPlayerHosting {
    var contentBottomConstraint: NSLayoutConstraint? {
        return webViewBottomAnchorConstraint
    }
    
    var persistentBottomBarHeight: CGFloat {
        return chromeDelegate?.barsMaxHeight ?? 0.0
    }

    func showChrome() {
        showBars()
    }

    func hideChrome() {
        hideBars()
    }

    func isTabCurrentlyPresented() -> Bool {
        return delegate?.tabCheckIfItsBeingCurrentlyPresented(self) ?? false
    }

}

extension TabViewController {
        
    // This is used to handle the webView constraint changes when DuckPlayer is presented
    private func setupDuckPlayerConstraintHandling(publisher: AnyPublisher<DuckPlayerConstraintUpdate, Never>) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self = self else { return }
                
                switch update {
                case .showPill(let height):
                    if self.appSettings.currentAddressBarPosition == .bottom {
                        let targetHeight = self.chromeDelegate?.barsMaxHeight ?? 0
                        self.webViewBottomAnchorConstraint?.constant = -targetHeight - height
                    } else {
                        self.webViewBottomAnchorConstraint?.constant = -height
                    }

                case .reset:
                    let targetHeight = self.chromeDelegate?.barsMaxHeight ?? 0
                    self.webViewBottomAnchorConstraint?.constant = self.appSettings.currentAddressBarPosition == .bottom ? -targetHeight : 0
                }
                
                self.view.layoutIfNeeded()
            }
            .store(in: &cancellables)
    }
}

extension TabViewController: SERPSettingsUserScriptDelegate {

    func serpSettingsUserScriptDidRequestToCloseTab(_ userScript: SERPSettingsUserScript) {
        // macOS Only
    }

    func serpSettingsUserScriptDidRequestToOpenAIFeaturesSettings(_ userScript: SERPSettingsUserScript) {
        PixelKit.fire(SERPSettingsPixel.openDuckAIButtonClick, frequency: .dailyAndStandard)
        guard let mainVC = parent as? MainViewController else { return }
        mainVC.segueToSettingsAIChat(openedFromSERPSettingsButton: true)
    }
}

// MARK: - SafariRedirectHandlerDelegate

extension TabViewController: SafariRedirectHandlerDelegate {

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestLoadURL url: URL) {
        DailyPixel.fireDailyAndCount(pixel: .webViewExternalSchemeNavigationSafariRedirectLoadURLRequested, error: nil, withAdditionalParameters: [:])
        shouldUseSafariOnlyUserAgentForNextMainFrameNavigation = true
        load(url: url, didUpgradeURL: false)
    }

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestShowSafariRedirectLoopErrorForURL url: URL) {
        DailyPixel.fireDailyAndCount(pixel: .webViewExternalSchemeNavigationSafariRedirectLoopErrorPageShown, error: nil, withAdditionalParameters: [:])
        shouldUseSafariOnlyUserAgentForNextMainFrameNavigation = false
        showSafariRedirectLoopError(for: url)
    }
}

private extension WKProcessTerminationReason {

    var pixelName: String {
        switch self {
        case .exceededMemoryLimit: return "exceeded_memory_limit"
        case .exceededCPULimit: return "exceeded_cpu_limit"
        case .requestedByClient: return "requested_by_client"
        case .crash: return "crash"
        case .exceededSharedProcessCrashLimit: return "exceeded_shared_process_crash_limit"
        }
    }
}
