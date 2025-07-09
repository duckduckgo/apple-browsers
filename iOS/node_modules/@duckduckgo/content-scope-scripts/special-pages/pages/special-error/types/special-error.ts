/**
 * These types are auto-generated from schema files.
 * scripts/build-types.mjs is responsible for type generation.
 * **DO NOT** edit this file directly as your changes will be lost.
 *
 * @module SpecialError Messages
 */

/**
 * Requests, Notifications and Subscriptions from the SpecialError feature
 */
export interface SpecialErrorMessages {
  notifications:
    | AdvancedInfoNotification
    | LeaveSiteNotification
    | ReportInitExceptionNotification
    | ReportPageExceptionNotification
    | VisitSiteNotification;
  requests: InitialSetupRequest;
}
/**
 * Generated from @see "../messages/advancedInfo.notify.json"
 */
export interface AdvancedInfoNotification {
  method: "advancedInfo";
}
/**
 * Generated from @see "../messages/leaveSite.notify.json"
 */
export interface LeaveSiteNotification {
  method: "leaveSite";
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
 * Generated from @see "../messages/visitSite.notify.json"
 */
export interface VisitSiteNotification {
  method: "visitSite";
}
/**
 * Generated from @see "../messages/initialSetup.request.json"
 */
export interface InitialSetupRequest {
  method: "initialSetup";
  result: InitialSetupResponse;
}
export interface InitialSetupResponse {
  locale: string;
  env: "development" | "production";
  platform: {
    name: "macos" | "windows" | "android" | "ios";
  };
  errorData: MaliciousSite | SSLExpiredCertificate | SSLInvalidCertificate | SSLSelfSignedCertificate | SSLWrongHost;
  /**
   * Optional locale-specific strings
   */
  localeStrings?: string;
}
export interface MaliciousSite {
  kind: "phishing" | "malware" | "scam";
  url: string;
}
export interface SSLExpiredCertificate {
  kind: "ssl";
  errorType: "expired";
  domain: string;
}
export interface SSLInvalidCertificate {
  kind: "ssl";
  errorType: "invalid";
  domain: string;
}
export interface SSLSelfSignedCertificate {
  kind: "ssl";
  errorType: "selfSigned";
  domain: string;
}
export interface SSLWrongHost {
  kind: "ssl";
  errorType: "wrongHost";
  domain: string;
  eTldPlus1: string;
}

declare module "../src/index.js" {
  export interface SpecialErrorPage {
    notify: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<SpecialErrorMessages>['notify'],
    request: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<SpecialErrorMessages>['request']
  }
}