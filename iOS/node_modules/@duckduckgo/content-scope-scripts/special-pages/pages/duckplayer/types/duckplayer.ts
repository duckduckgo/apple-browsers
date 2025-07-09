/**
 * These types are auto-generated from schema files.
 * scripts/build-types.mjs is responsible for type generation.
 * **DO NOT** edit this file directly as your changes will be lost.
 *
 * @module Duckplayer Messages
 */

export type YouTubeError = "age-restricted" | "sign-in-required" | "no-embed" | "unknown";
export type PrivatePlayerMode =
  | {
      enabled: unknown;
    }
  | {
      disabled: unknown;
    }
  | {
      alwaysAsk: unknown;
    };

/**
 * Requests, Notifications and Subscriptions from the Duckplayer feature
 */
export interface DuckplayerMessages {
  notifications:
    | OpenInfoNotification
    | OpenSettingsNotification
    | ReportInitExceptionNotification
    | ReportPageExceptionNotification
    | ReportYouTubeErrorNotification
    | TelemetryEventNotification;
  requests: GetUserValuesRequest | InitialSetupRequest | SetUserValuesRequest;
  subscriptions: OnUserValuesChangedSubscription;
}
/**
 * Generated from @see "../messages/openInfo.notify.json"
 */
export interface OpenInfoNotification {
  method: "openInfo";
}
/**
 * Generated from @see "../messages/openSettings.notify.json"
 */
export interface OpenSettingsNotification {
  method: "openSettings";
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
 * Generated from @see "../messages/reportYouTubeError.notify.json"
 */
export interface ReportYouTubeErrorNotification {
  method: "reportYouTubeError";
  params: ReportYouTubeErrorNotify;
}
export interface ReportYouTubeErrorNotify {
  error: YouTubeError;
}
/**
 * Generated from @see "../messages/telemetryEvent.notify.json"
 */
export interface TelemetryEventNotification {
  method: "telemetryEvent";
  params: TelemetryEvent;
}
export interface TelemetryEvent {
  attributes: Impression;
}
export interface Impression {
  name: "impression";
  value: "landscape-layout";
}
/**
 * Generated from @see "../messages/getUserValues.request.json"
 */
export interface GetUserValuesRequest {
  method: "getUserValues";
  result: UserValues;
}
export interface UserValues {
  overlayInteracted: boolean;
  privatePlayerMode: PrivatePlayerMode;
}
/**
 * Generated from @see "../messages/initialSetup.request.json"
 */
export interface InitialSetupRequest {
  method: "initialSetup";
  result: InitialSetupResponse;
}
export interface InitialSetupResponse {
  userValues: UserValues;
  settings: DuckPlayerPageSettings;
  locale: string;
  env: "development" | "production";
  platform: {
    name: "macos" | "windows" | "android" | "ios";
  };
  /**
   * Optional locale-specific strings
   */
  localeStrings?: string;
}
export interface DuckPlayerPageSettings {
  pip: {
    state: "enabled" | "disabled";
  };
  autoplay?: {
    state: "enabled" | "disabled";
  };
  focusMode?: {
    state: "enabled" | "disabled";
  };
  customError?: CustomErrorSettings & {
    /**
     * A selector that, when not empty, indicates a sign-in required error
     */
    signInRequiredSelector?: string;
  };
}
/**
 * Configures a custom error message for YouTube errors
 */
export interface CustomErrorSettings {
  state: "enabled" | "disabled";
  /**
   * Custom error settings
   */
  settings?: {
    /**
     * A selector that, when not empty, indicates a sign-in required error
     */
    signInRequiredSelector?: string;
    /**
     * A selector that, when not empty, indicates a general YouTube error
     */
    youtubeErrorSelector?: string;
  };
}
/**
 * Generated from @see "../messages/setUserValues.request.json"
 */
export interface SetUserValuesRequest {
  method: "setUserValues";
  params: UserValues;
  result: UserValues;
}
/**
 * Generated from @see "../messages/onUserValuesChanged.subscribe.json"
 */
export interface OnUserValuesChangedSubscription {
  subscriptionEvent: "onUserValuesChanged";
  params: UserValues;
}

declare module "../src/index.js" {
  export interface DuckplayerPage {
    notify: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<DuckplayerMessages>['notify'],
    request: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<DuckplayerMessages>['request'],
    subscribe: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<DuckplayerMessages>['subscribe']
  }
}