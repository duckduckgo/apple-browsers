/**
 * These types are auto-generated from schema files.
 * scripts/build-types.mjs is responsible for type generation.
 * **DO NOT** edit this file directly as your changes will be lost.
 *
 * @module NewTab Messages
 */

export type OpenTarget = "same-tab" | "new-tab" | "new-window";
export type BackgroundVariant =
  | DefaultBackground
  | SolidColorBackground
  | HexValueBackground
  | GradientBackground
  | UserImageBackground;
export type PredefinedColor =
  | "color01"
  | "color02"
  | "color03"
  | "color04"
  | "color05"
  | "color06"
  | "color07"
  | "color08"
  | "color09"
  | "color10"
  | "color11"
  | "color12"
  | "color13"
  | "color14"
  | "color15"
  | "color16"
  | "color17"
  | "color18"
  | "color19";
export type PredefinedGradient =
  | "gradient01"
  | "gradient02"
  | "gradient02.01"
  | "gradient03"
  | "gradient04"
  | "gradient05"
  | "gradient06"
  | "gradient07";
/**
 * Note: this is different to the Browser Theme
 */
export type BackgroundColorScheme = "light" | "dark";
export type BrowserTheme = "light" | "dark" | "system";
/**
 * Represents the expansion state of a widget
 */
export type Expansion = "expanded" | "collapsed";
/**
 * Generic Animation configuration
 */
export type Animation = None | ViewTransitions | Auto;
export type Suggestion =
  | BookmarkSuggestion
  | OpenTabSuggestion
  | PhraseSuggestion
  | WebsiteSuggestion
  | HistoryEntrySuggestion
  | InternalPageSuggestion;
export type OmnibarMode = "search" | "ai";
export type EnableDuckAi = boolean;
export type FeedType = "privacy-stats" | "activity";
/**
 * The visibility state of the widget, as configured by the user
 */
export type WidgetVisibility = "visible" | "hidden";
/**
 * Configuration settings for widgets
 */
export type WidgetConfigs = WidgetConfigItem[];
export type Favicon = null | {
  src: string;
  maxAvailableSize?: number;
};
/**
 * An ordered list of supported Widgets. Use this to communicate what's supported
 */
export type Widgets = WidgetListItem[];
export type NextStepsCardTypes =
  | "bringStuff"
  | "defaultApp"
  | "blockCookies"
  | "emailProtection"
  | "duckplayer"
  | "addAppToDockMac"
  | "pinAppToTaskbarWindows";
export type NextStepsCards = {
  id: NextStepsCardTypes;
}[];
export type RMFMessage = SmallMessage | MediumMessage | BigSingleActionMessage | BigTwoActionMessage;
export type RMFIcon = "Announce" | "DDGAnnounce" | "CriticalUpdate" | "AppUpdate" | "PrivacyPro";

/**
 * Requests, Notifications and Subscriptions from the NewTab feature
 */
export interface NewTabMessages {
  notifications:
    | ActivityAddFavoriteNotification
    | ActivityOpenNotification
    | ActivityRemoveFavoriteNotification
    | ActivityRemoveItemNotification
    | ContextMenuNotification
    | CustomizerContextMenuNotification
    | CustomizerDeleteImageNotification
    | CustomizerSetBackgroundNotification
    | CustomizerSetThemeNotification
    | CustomizerUploadNotification
    | FavoritesAddNotification
    | FavoritesMoveNotification
    | FavoritesOpenNotification
    | FavoritesOpenContextMenuNotification
    | FavoritesSetConfigNotification
    | FreemiumPIRBannerActionNotification
    | FreemiumPIRBannerDismissNotification
    | NextStepsActionNotification
    | NextStepsDismissNotification
    | NextStepsSetConfigNotification
    | OmnibarOpenSuggestionNotification
    | OmnibarSetConfigNotification
    | OmnibarSubmitChatNotification
    | OmnibarSubmitSearchNotification
    | OpenNotification
    | ProtectionsSetConfigNotification
    | ReportInitExceptionNotification
    | ReportPageExceptionNotification
    | RmfDismissNotification
    | RmfPrimaryActionNotification
    | RmfSecondaryActionNotification
    | StatsShowLessNotification
    | StatsShowMoreNotification
    | TelemetryEventNotification
    | UpdateNotificationDismissNotification
    | WidgetsSetConfigNotification;
  requests:
    | ActivityConfirmBurnRequest
    | ActivityGetDataRequest
    | ActivityGetDataForUrlsRequest
    | ActivityGetUrlsRequest
    | FavoritesGetConfigRequest
    | FavoritesGetDataRequest
    | FreemiumPIRBannerGetDataRequest
    | InitialSetupRequest
    | NextStepsGetConfigRequest
    | NextStepsGetDataRequest
    | OmnibarGetConfigRequest
    | OmnibarGetSuggestionsRequest
    | ProtectionsGetConfigRequest
    | ProtectionsGetDataRequest
    | RmfGetDataRequest
    | StatsGetDataRequest;
  subscriptions:
    | ActivityOnBurnCompleteSubscription
    | ActivityOnDataPatchSubscription
    | ActivityOnDataUpdateSubscription
    | CustomizerAutoOpenSubscription
    | CustomizerOnBackgroundUpdateSubscription
    | CustomizerOnColorUpdateSubscription
    | CustomizerOnImagesUpdateSubscription
    | CustomizerOnThemeUpdateSubscription
    | FavoritesOnConfigUpdateSubscription
    | FavoritesOnDataUpdateSubscription
    | FavoritesOnRefreshSubscription
    | FreemiumPIRBannerOnDataUpdateSubscription
    | NextStepsOnConfigUpdateSubscription
    | NextStepsOnDataUpdateSubscription
    | OmnibarOnConfigUpdateSubscription
    | ProtectionsOnConfigUpdateSubscription
    | ProtectionsOnDataUpdateSubscription
    | RmfOnDataUpdateSubscription
    | StatsOnDataUpdateSubscription
    | UpdateNotificationOnDataUpdateSubscription
    | WidgetsOnConfigUpdatedSubscription;
}
/**
 * Generated from @see "../messages/activity_addFavorite.notify.json"
 */
export interface ActivityAddFavoriteNotification {
  method: "activity_addFavorite";
  params: ActivityAddFavoriteNotify;
}
export interface ActivityAddFavoriteNotify {
  /**
   * The History Entry url to be added to favorites
   */
  url: string;
}
/**
 * Generated from @see "../messages/activity_open.notify.json"
 */
export interface ActivityOpenNotification {
  method: "activity_open";
  params: ActivityOpenAction;
}
export interface ActivityOpenAction {
  /**
   * The url to open
   */
  url: string;
  target: OpenTarget;
}
/**
 * Generated from @see "../messages/activity_removeFavorite.notify.json"
 */
export interface ActivityRemoveFavoriteNotification {
  method: "activity_removeFavorite";
  params: ActivityRemoveFavoriteNotify;
}
export interface ActivityRemoveFavoriteNotify {
  /**
   * The History Entry url to be removed from favorites
   */
  url: string;
}
/**
 * Generated from @see "../messages/activity_removeItem.notify.json"
 */
export interface ActivityRemoveItemNotification {
  method: "activity_removeItem";
  params: ActivityRemoveItemNotify;
}
export interface ActivityRemoveItemNotify {
  /**
   * The History Entry url to be removed
   */
  url: string;
}
/**
 * Generated from @see "../messages/contextMenu.notify.json"
 */
export interface ContextMenuNotification {
  method: "contextMenu";
  params: ContextMenuNotify;
}
export interface ContextMenuNotify {
  visibilityMenuItems: VisibilityMenuItem[];
}
export interface VisibilityMenuItem {
  id: string;
  /**
   * Translated name of the section
   */
  title: string;
}
/**
 * Generated from @see "../messages/customizer_contextMenu.notify.json"
 */
export interface CustomizerContextMenuNotification {
  method: "customizer_contextMenu";
  params: UserImageContextMenu;
}
export interface UserImageContextMenu {
  id: string;
  target: "userImage";
}
/**
 * Generated from @see "../messages/customizer_deleteImage.notify.json"
 */
export interface CustomizerDeleteImageNotification {
  method: "customizer_deleteImage";
  params: CustomizerDeleteImageNotify;
}
export interface CustomizerDeleteImageNotify {
  id: string;
}
/**
 * Generated from @see "../messages/customizer_setBackground.notify.json"
 */
export interface CustomizerSetBackgroundNotification {
  method: "customizer_setBackground";
  params: CustomizerSetBackgroundNotify;
}
export interface CustomizerSetBackgroundNotify {
  background: BackgroundVariant;
}
export interface DefaultBackground {
  kind: "default";
}
export interface SolidColorBackground {
  kind: "color";
  value: PredefinedColor;
}
export interface HexValueBackground {
  kind: "hex";
  value: string;
}
export interface GradientBackground {
  kind: "gradient";
  value: PredefinedGradient;
}
export interface UserImageBackground {
  kind: "userImage";
  value: UserImage;
}
export interface UserImage {
  id: string;
  src: string;
  thumb: string;
  colorScheme: BackgroundColorScheme;
}
/**
 * Generated from @see "../messages/customizer_setTheme.notify.json"
 */
export interface CustomizerSetThemeNotification {
  method: "customizer_setTheme";
  params: CustomizerSetThemeNotify;
}
export interface CustomizerSetThemeNotify {
  theme: BrowserTheme;
}
/**
 * Generated from @see "../messages/customizer_upload.notify.json"
 */
export interface CustomizerUploadNotification {
  method: "customizer_upload";
}
/**
 * Generated from @see "../messages/favorites_add.notify.json"
 */
export interface FavoritesAddNotification {
  method: "favorites_add";
}
/**
 * Generated from @see "../messages/favorites_move.notify.json"
 */
export interface FavoritesMoveNotification {
  method: "favorites_move";
  params: FavoritesMoveAction;
}
export interface FavoritesMoveAction {
  /**
   * Entity ID
   */
  id: string;
  /**
   * zero-indexed target
   */
  targetIndex: number;
  /**
   * zero-indexed source
   */
  fromIndex: number;
}
/**
 * Generated from @see "../messages/favorites_open.notify.json"
 */
export interface FavoritesOpenNotification {
  method: "favorites_open";
  params: FavoritesOpenAction;
}
export interface FavoritesOpenAction {
  /**
   * Entity ID
   */
  id: string;
  /**
   * The url to open
   */
  url: string;
  target: OpenTarget;
}
/**
 * Generated from @see "../messages/favorites_openContextMenu.notify.json"
 */
export interface FavoritesOpenContextMenuNotification {
  method: "favorites_openContextMenu";
  params: FavoritesOpenContextMenuAction;
}
export interface FavoritesOpenContextMenuAction {
  /**
   * Entity ID
   */
  id: string;
}
/**
 * Generated from @see "../messages/favorites_setConfig.notify.json"
 */
export interface FavoritesSetConfigNotification {
  method: "favorites_setConfig";
  params: FavoritesConfig;
}
export interface FavoritesConfig {
  expansion: Expansion;
  animation?: Animation;
}
export interface None {
  kind: "none";
}
/**
 * Use CSS view transitions where available
 */
export interface ViewTransitions {
  kind: "view-transitions";
}
/**
 * Use the auto-animate library to provide default animation styles
 */
export interface Auto {
  kind: "auto-animate";
}
/**
 * Generated from @see "../messages/freemiumPIRBanner_action.notify.json"
 */
export interface FreemiumPIRBannerActionNotification {
  method: "freemiumPIRBanner_action";
  params: FreemiumPIRBannerAction;
}
export interface FreemiumPIRBannerAction {
  id: string;
}
/**
 * Generated from @see "../messages/freemiumPIRBanner_dismiss.notify.json"
 */
export interface FreemiumPIRBannerDismissNotification {
  method: "freemiumPIRBanner_dismiss";
  params: FreemiumPIRBannerDismissAction;
}
export interface FreemiumPIRBannerDismissAction {
  id: string;
}
/**
 * Generated from @see "../messages/nextSteps_action.notify.json"
 */
export interface NextStepsActionNotification {
  method: "nextSteps_action";
  params: NextStepsActionNotify;
}
export interface NextStepsActionNotify {
  id: string;
}
/**
 * Generated from @see "../messages/nextSteps_dismiss.notify.json"
 */
export interface NextStepsDismissNotification {
  method: "nextSteps_dismiss";
  params: NextStepsDismissNotify;
}
export interface NextStepsDismissNotify {
  id: string;
}
/**
 * Generated from @see "../messages/nextSteps_setConfig.notify.json"
 */
export interface NextStepsSetConfigNotification {
  method: "nextSteps_setConfig";
  params: NextStepsConfig;
}
export interface NextStepsConfig {
  expansion: Expansion;
  animation?: Animation;
}
/**
 * Generated from @see "../messages/omnibar_openSuggestion.notify.json"
 */
export interface OmnibarOpenSuggestionNotification {
  method: "omnibar_openSuggestion";
  params: OpenSuggestionAction;
}
export interface OpenSuggestionAction {
  suggestion: Suggestion;
  target: OpenTarget;
}
export interface BookmarkSuggestion {
  kind: "bookmark";
  title: string;
  url: string;
  isFavorite: boolean;
  score: number;
}
export interface OpenTabSuggestion {
  kind: "openTab";
  title: string;
  tabId: string;
  score: number;
}
export interface PhraseSuggestion {
  kind: "phrase";
  phrase: string;
}
export interface WebsiteSuggestion {
  kind: "website";
  url: string;
}
export interface HistoryEntrySuggestion {
  kind: "historyEntry";
  title: string;
  url: string;
  score: number;
}
export interface InternalPageSuggestion {
  kind: "internalPage";
  title: string;
  url: string;
  score: number;
}
/**
 * Generated from @see "../messages/omnibar_setConfig.notify.json"
 */
export interface OmnibarSetConfigNotification {
  method: "omnibar_setConfig";
  params: OmnibarConfig;
}
export interface OmnibarConfig {
  mode: OmnibarMode;
  enableAi?: EnableDuckAi;
}
/**
 * Generated from @see "../messages/omnibar_submitChat.notify.json"
 */
export interface OmnibarSubmitChatNotification {
  method: "omnibar_submitChat";
  params: SubmitChatAction;
}
export interface SubmitChatAction {
  /**
   * The chat message to submit to Duck.ai
   */
  chat: string;
  target: OpenTarget;
}
/**
 * Generated from @see "../messages/omnibar_submitSearch.notify.json"
 */
export interface OmnibarSubmitSearchNotification {
  method: "omnibar_submitSearch";
  params: SubmitSearchAction;
}
export interface SubmitSearchAction {
  /**
   * The search term to submit
   */
  term: string;
  target: OpenTarget;
}
/**
 * Generated from @see "../messages/open.notify.json"
 */
export interface OpenNotification {
  method: "open";
  params: OpenAction;
}
export interface OpenAction {
  target: "settings";
}
/**
 * Generated from @see "../messages/protections_setConfig.notify.json"
 */
export interface ProtectionsSetConfigNotification {
  method: "protections_setConfig";
  params: ProtectionsConfig;
}
export interface ProtectionsConfig {
  expansion: Expansion;
  feed: FeedType;
  /**
   * Boolean flag to explicitly enable or disable the burn animations
   */
  showBurnAnimation?: boolean;
}
/**
 * Generated from @see "../messages/reportInitException.notify.json"
 */
export interface ReportInitExceptionNotification {
  method: "reportInitException";
  params: ReportInitExceptionNotify;
}
export interface ReportInitExceptionNotify {
  message: string;
}
/**
 * Generated from @see "../messages/reportPageException.notify.json"
 */
export interface ReportPageExceptionNotification {
  method: "reportPageException";
  params: ReportPageExceptionNotify;
}
export interface ReportPageExceptionNotify {
  message: string;
}
/**
 * Generated from @see "../messages/rmf_dismiss.notify.json"
 */
export interface RmfDismissNotification {
  method: "rmf_dismiss";
  params: RMFDismissAction;
}
export interface RMFDismissAction {
  id: string;
}
/**
 * Generated from @see "../messages/rmf_primaryAction.notify.json"
 */
export interface RmfPrimaryActionNotification {
  method: "rmf_primaryAction";
  params: RMFPrimaryAction;
}
export interface RMFPrimaryAction {
  id: string;
}
/**
 * Generated from @see "../messages/rmf_secondaryAction.notify.json"
 */
export interface RmfSecondaryActionNotification {
  method: "rmf_secondaryAction";
  params: RMFSecondaryAction;
}
export interface RMFSecondaryAction {
  id: string;
}
/**
 * Generated from @see "../messages/stats_showLess.notify.json"
 */
export interface StatsShowLessNotification {
  method: "stats_showLess";
}
/**
 * Generated from @see "../messages/stats_showMore.notify.json"
 */
export interface StatsShowMoreNotification {
  method: "stats_showMore";
}
/**
 * Generated from @see "../messages/telemetryEvent.notify.json"
 */
export interface TelemetryEventNotification {
  method: "telemetryEvent";
  params: NTPTelemetryEvent;
}
export interface NTPTelemetryEvent {
  attributes: StatsShowMore | ExampleTelemetryEvent;
}
export interface StatsShowMore {
  name: "stats_toggle";
  value: "show_more" | "show_less";
}
export interface ExampleTelemetryEvent {
  name: "ntp_example";
}
/**
 * Generated from @see "../messages/updateNotification_dismiss.notify.json"
 */
export interface UpdateNotificationDismissNotification {
  method: "updateNotification_dismiss";
}
/**
 * Generated from @see "../messages/widgets_setConfig.notify.json"
 */
export interface WidgetsSetConfigNotification {
  method: "widgets_setConfig";
  params: WidgetConfigs;
}
export interface WidgetConfigItem {
  /**
   * A unique identifier for the widget.
   */
  id: string;
  visibility: WidgetVisibility;
}
/**
 * Generated from @see "../messages/activity_confirmBurn.request.json"
 */
export interface ActivityConfirmBurnRequest {
  method: "activity_confirmBurn";
  params: ConfirmBurnParams;
  result: ConfirmBurnResponse;
}
export interface ConfirmBurnParams {
  /**
   * The History Entry url that will be burned
   */
  url: string;
}
export interface ConfirmBurnResponse {
  action: "burn" | "none";
}
/**
 * Generated from @see "../messages/activity_getData.request.json"
 */
export interface ActivityGetDataRequest {
  method: "activity_getData";
  result: ActivityData;
}
export interface ActivityData {
  activity: DomainActivity[];
}
export interface DomainActivity {
  /**
   * Current page title
   */
  title: string;
  /**
   * The full URL to be used for the favicon + title link. This is normally just the domain, but a fully qualified URL.
   */
  url: string;
  /**
   * Effective top-level domain plus one (eTLD+1) of the URL. Used to infer colors/fallbacks
   */
  etldPlusOne: string;
  favicon: Favicon;
  trackingStatus: TrackingStatus;
  /**
   * Indicates whether trackers were found
   */
  trackersFound: boolean;
  history: HistoryEntry[];
  favorite: boolean;
}
export interface TrackingStatus {
  trackerCompanies: {
    /**
     * Name of the tracking company (e.g., 'Google', 'Microsoft')
     */
    displayName: string;
  }[];
  totalCount: number;
}
export interface HistoryEntry {
  /**
   * Platform-dependent page identifier - could be HTML title, URL pathname, or other identifier. Examples: 'YouTube - Homepage', '/users/settings', 'Netflix', '/v2/api/analytics'
   */
  title: string;
  /**
   * Full page URL
   */
  url: string;
  /**
   * Human readable relative time
   */
  relativeTime: string;
}
/**
 * Generated from @see "../messages/activity_getDataForUrls.request.json"
 */
export interface ActivityGetDataForUrlsRequest {
  method: "activity_getDataForUrls";
  params: DataForUrlsParams;
  result: ActivityData;
}
export interface DataForUrlsParams {
  urls: string[];
}
/**
 * Generated from @see "../messages/activity_getUrls.request.json"
 */
export interface ActivityGetUrlsRequest {
  method: "activity_getUrls";
  result: UrlInfo;
}
export interface UrlInfo {
  urls: string[];
  totalTrackersBlocked: number;
}
/**
 * Generated from @see "../messages/favorites_getConfig.request.json"
 */
export interface FavoritesGetConfigRequest {
  method: "favorites_getConfig";
  result: FavoritesConfig;
}
/**
 * Generated from @see "../messages/favorites_getData.request.json"
 */
export interface FavoritesGetDataRequest {
  method: "favorites_getData";
  result: FavoritesData;
}
export interface FavoritesData {
  favorites: Favorite[];
}
export interface Favorite {
  /**
   * The full url that will be navigated to (including path, query params and hash)
   */
  url: string;
  /**
   * The eTLD+1 of the URL, representing the effective top-level domain and one second-level domain
   */
  etldPlusOne: null | string;
  id: string;
  title: string;
  favicon: Favicon;
}
/**
 * Generated from @see "../messages/freemiumPIRBanner_getData.request.json"
 */
export interface FreemiumPIRBannerGetDataRequest {
  method: "freemiumPIRBanner_getData";
  result: FreemiumPIRBannerData;
}
export interface FreemiumPIRBannerData {
  content: null | FreemiumPIRBannerMessage;
}
export interface FreemiumPIRBannerMessage {
  messageType: "big_single_action";
  id: "onboarding" | "scan_results";
  titleText: string | null;
  descriptionText: string;
  actionText: string;
}
/**
 * Generated from @see "../messages/initialSetup.request.json"
 */
export interface InitialSetupRequest {
  method: "initialSetup";
  result: InitialSetupResponse;
}
export interface InitialSetupResponse {
  widgets: Widgets;
  settings?: NewTabPageSettings;
  widgetConfigs: WidgetConfigs;
  locale: string;
  env: "development" | "production";
  platform: {
    name: "macos" | "windows" | "android" | "ios" | "integration";
  };
  customizer?: CustomizerData;
  updateNotification: null | UpdateNotificationData;
}
export interface WidgetListItem {
  /**
   * A unique identifier for the widget.
   */
  id: string;
}
export interface NewTabPageSettings {
  customizerDrawer?: {
    state: "enabled";
    /**
     * Should the customizer drawer be opened on page load?
     */
    autoOpen?: boolean;
  };
  adBlocking?: {
    state: "enabled" | "disabled";
  };
}
export interface CustomizerData {
  background: BackgroundVariant;
  theme: BrowserTheme;
  userImages: UserImage[];
  userColor: null | HexValueBackground;
  defaultStyles?: null | DefaultStyles;
}
export interface DefaultStyles {
  /**
   * Optional default dark background color. Any HEX value is permitted
   */
  darkBackgroundColor?: string;
  /**
   * Optional default light background color. Any HEX value is permitted
   */
  lightBackgroundColor?: string;
}
export interface UpdateNotificationData {
  content: null | UpdateNotification;
}
export interface UpdateNotification {
  version: string;
  notes: string[];
}
/**
 * Generated from @see "../messages/nextSteps_getConfig.request.json"
 */
export interface NextStepsGetConfigRequest {
  method: "nextSteps_getConfig";
  result: NextStepsConfig;
}
/**
 * Generated from @see "../messages/nextSteps_getData.request.json"
 */
export interface NextStepsGetDataRequest {
  method: "nextSteps_getData";
  result: NextStepsData;
}
export interface NextStepsData {
  content: null | NextStepsCards;
}
/**
 * Generated from @see "../messages/omnibar_getConfig.request.json"
 */
export interface OmnibarGetConfigRequest {
  method: "omnibar_getConfig";
  result: OmnibarConfig;
}
/**
 * Generated from @see "../messages/omnibar_getSuggestions.request.json"
 */
export interface OmnibarGetSuggestionsRequest {
  method: "omnibar_getSuggestions";
  params: GetSuggestionsRequest;
  result: SuggestionsData;
}
export interface GetSuggestionsRequest {
  /**
   * The search term to get suggestions for
   */
  term: string;
}
export interface SuggestionsData {
  suggestions: {
    topHits: Suggestion[];
    duckduckgoSuggestions: Suggestion[];
    localSuggestions: Suggestion[];
  };
}
/**
 * Generated from @see "../messages/protections_getConfig.request.json"
 */
export interface ProtectionsGetConfigRequest {
  method: "protections_getConfig";
  result: ProtectionsConfig;
}
/**
 * Generated from @see "../messages/protections_getData.request.json"
 */
export interface ProtectionsGetDataRequest {
  method: "protections_getData";
  result: ProtectionsData;
}
export interface ProtectionsData {
  /**
   * Total number of trackers or ads blocked since install
   */
  totalCount: number;
}
/**
 * Generated from @see "../messages/rmf_getData.request.json"
 */
export interface RmfGetDataRequest {
  method: "rmf_getData";
  result: RMFData;
}
/**
 * The 'content' field is optional. Use that fact to show/hide messages
 */
export interface RMFData {
  content?: RMFMessage;
}
export interface SmallMessage {
  messageType: "small";
  id: string;
  titleText: string;
  descriptionText: string;
}
export interface MediumMessage {
  messageType: "medium";
  id: string;
  titleText: string;
  descriptionText: string;
  icon: RMFIcon;
}
export interface BigSingleActionMessage {
  messageType: "big_single_action";
  id: string;
  titleText: string;
  descriptionText: string;
  icon: RMFIcon;
  primaryActionText: string;
}
export interface BigTwoActionMessage {
  messageType: "big_two_action";
  id: string;
  titleText: string;
  descriptionText: string;
  icon: RMFIcon;
  primaryActionText: string;
  secondaryActionText: string;
}
/**
 * Generated from @see "../messages/stats_getData.request.json"
 */
export interface StatsGetDataRequest {
  method: "stats_getData";
  result: PrivacyStatsData;
}
export interface PrivacyStatsData {
  trackerCompanies: TrackerCompany[];
}
export interface TrackerCompany {
  displayName: string;
  count: number;
}
/**
 * Generated from @see "../messages/activity_onBurnComplete.subscribe.json"
 */
export interface ActivityOnBurnCompleteSubscription {
  subscriptionEvent: "activity_onBurnComplete";
}
/**
 * Generated from @see "../messages/activity_onDataPatch.subscribe.json"
 */
export interface ActivityOnDataPatchSubscription {
  subscriptionEvent: "activity_onDataPatch";
  params: UrlInfo & PatchData;
}
export interface PatchData {
  patch?: DomainActivity;
}
/**
 * Generated from @see "../messages/activity_onDataUpdate.subscribe.json"
 */
export interface ActivityOnDataUpdateSubscription {
  subscriptionEvent: "activity_onDataUpdate";
  params: ActivityData;
}
/**
 * Generated from @see "../messages/customizer_autoOpen.subscribe.json"
 */
export interface CustomizerAutoOpenSubscription {
  subscriptionEvent: "customizer_autoOpen";
}
/**
 * Generated from @see "../messages/customizer_onBackgroundUpdate.subscribe.json"
 */
export interface CustomizerOnBackgroundUpdateSubscription {
  subscriptionEvent: "customizer_onBackgroundUpdate";
  params: BackgroundData;
}
export interface BackgroundData {
  background: BackgroundVariant;
}
/**
 * Generated from @see "../messages/customizer_onColorUpdate.subscribe.json"
 */
export interface CustomizerOnColorUpdateSubscription {
  subscriptionEvent: "customizer_onColorUpdate";
  params: UserColorData;
}
export interface UserColorData {
  userColor: null | HexValueBackground;
}
/**
 * Generated from @see "../messages/customizer_onImagesUpdate.subscribe.json"
 */
export interface CustomizerOnImagesUpdateSubscription {
  subscriptionEvent: "customizer_onImagesUpdate";
  params: UserImageData;
}
export interface UserImageData {
  userImages: UserImage[];
}
/**
 * Generated from @see "../messages/customizer_onThemeUpdate.subscribe.json"
 */
export interface CustomizerOnThemeUpdateSubscription {
  subscriptionEvent: "customizer_onThemeUpdate";
  params: ThemeData;
}
export interface ThemeData {
  theme: BrowserTheme;
  defaultStyles?: null | DefaultStyles;
}
/**
 * Generated from @see "../messages/favorites_onConfigUpdate.subscribe.json"
 */
export interface FavoritesOnConfigUpdateSubscription {
  subscriptionEvent: "favorites_onConfigUpdate";
  params: FavoritesConfig;
}
/**
 * Generated from @see "../messages/favorites_onDataUpdate.subscribe.json"
 */
export interface FavoritesOnDataUpdateSubscription {
  subscriptionEvent: "favorites_onDataUpdate";
  params: FavoritesData;
}
/**
 * Generated from @see "../messages/favorites_onRefresh.subscribe.json"
 */
export interface FavoritesOnRefreshSubscription {
  subscriptionEvent: "favorites_onRefresh";
  params: FavoritesRefresh;
}
export interface FavoritesRefresh {
  items: {
    kind: "favicons";
  }[];
}
/**
 * Generated from @see "../messages/freemiumPIRBanner_onDataUpdate.subscribe.json"
 */
export interface FreemiumPIRBannerOnDataUpdateSubscription {
  subscriptionEvent: "freemiumPIRBanner_onDataUpdate";
  params: FreemiumPIRBannerData;
}
/**
 * Generated from @see "../messages/nextSteps_onConfigUpdate.subscribe.json"
 */
export interface NextStepsOnConfigUpdateSubscription {
  subscriptionEvent: "nextSteps_onConfigUpdate";
  params: NextStepsConfig;
}
/**
 * Generated from @see "../messages/nextSteps_onDataUpdate.subscribe.json"
 */
export interface NextStepsOnDataUpdateSubscription {
  subscriptionEvent: "nextSteps_onDataUpdate";
  params: NextStepsData;
}
/**
 * Generated from @see "../messages/omnibar_onConfigUpdate.subscribe.json"
 */
export interface OmnibarOnConfigUpdateSubscription {
  subscriptionEvent: "omnibar_onConfigUpdate";
  params: OmnibarConfig;
}
/**
 * Generated from @see "../messages/protections_onConfigUpdate.subscribe.json"
 */
export interface ProtectionsOnConfigUpdateSubscription {
  subscriptionEvent: "protections_onConfigUpdate";
  params: ProtectionsConfig;
}
/**
 * Generated from @see "../messages/protections_onDataUpdate.subscribe.json"
 */
export interface ProtectionsOnDataUpdateSubscription {
  subscriptionEvent: "protections_onDataUpdate";
  params: ProtectionsData;
}
/**
 * Generated from @see "../messages/rmf_onDataUpdate.subscribe.json"
 */
export interface RmfOnDataUpdateSubscription {
  subscriptionEvent: "rmf_onDataUpdate";
  params: RMFData;
}
/**
 * Generated from @see "../messages/stats_onDataUpdate.subscribe.json"
 */
export interface StatsOnDataUpdateSubscription {
  subscriptionEvent: "stats_onDataUpdate";
  params: PrivacyStatsData;
}
/**
 * Generated from @see "../messages/updateNotification_onDataUpdate.subscribe.json"
 */
export interface UpdateNotificationOnDataUpdateSubscription {
  subscriptionEvent: "updateNotification_onDataUpdate";
  params: UpdateNotificationData;
}
/**
 * Generated from @see "../messages/widgets_onConfigUpdated.subscribe.json"
 */
export interface WidgetsOnConfigUpdatedSubscription {
  subscriptionEvent: "widgets_onConfigUpdated";
  params: WidgetConfigs;
}

declare module "../src/index.js" {
  export interface NewTabPage {
    notify: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<NewTabMessages>['notify'],
    request: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<NewTabMessages>['request'],
    subscribe: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<NewTabMessages>['subscribe']
  }
}