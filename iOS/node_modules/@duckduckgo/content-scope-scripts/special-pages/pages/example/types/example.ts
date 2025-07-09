/**
 * These types are auto-generated from schema files.
 * scripts/build-types.mjs is responsible for type generation.
 * **DO NOT** edit this file directly as your changes will be lost.
 *
 * @module Example Messages
 */

/**
 * Requests, Notifications and Subscriptions from the Example feature
 */
export interface ExampleMessages {
  notifications: ReportInitExceptionNotification | ReportPageExceptionNotification;
  requests: InitialSetupRequest;
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
 * Generated from @see "../messages/initialSetup.request.json"
 */
export interface InitialSetupRequest {
  method: "initialSetup";
  result: InitialSetupResponse;
}
export interface InitialSetupResponse {
  locale: string;
  env: "development" | "production";
}

declare module "../src/index.js" {
  export interface ExamplePage {
    notify: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<ExampleMessages>['notify'],
    request: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<ExampleMessages>['request']
  }
}