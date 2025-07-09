/**
 * These types are auto-generated from schema files.
 * scripts/build-types.mjs is responsible for type generation.
 * **DO NOT** edit this file directly as your changes will be lost.
 *
 * @module WebCompat Messages
 */

/**
 * Requests, Notifications and Subscriptions from the WebCompat feature
 */
export interface WebCompatMessages {
  requests: WebShareRequest;
}
/**
 * Generated from @see "../messages/web-compat/webShare.request.json"
 */
export interface WebShareRequest {
  method: "webShare";
  params: WebShareParams;
}
/**
 * todo: add description for `webShare` message
 */
export interface WebShareParams {
  /**
   * todo: add description for 'title' field
   */
  title?: string;
  /**
   * todo: add description for 'url' field
   */
  url?: string;
  /**
   * todo: add description for 'text' field
   */
  text?: string;
}

declare module "../features/web-compat.js" {
  export interface WebCompat {
    request: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<WebCompatMessages>['request']
  }
}