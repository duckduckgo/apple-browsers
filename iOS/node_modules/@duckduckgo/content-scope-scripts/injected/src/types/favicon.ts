/**
 * These types are auto-generated from schema files.
 * scripts/build-types.mjs is responsible for type generation.
 * **DO NOT** edit this file directly as your changes will be lost.
 *
 * @module Favicon Messages
 */

/**
 * Requests, Notifications and Subscriptions from the Favicon feature
 */
export interface FaviconMessages {
  notifications: FaviconFoundNotification;
}
/**
 * Generated from @see "../messages/favicon/faviconFound.notify.json"
 */
export interface FaviconFoundNotification {
  method: "faviconFound";
  params: FaviconFound;
}
export interface FaviconFound {
  favicons: FaviconAttrs[];
  documentUrl: string;
}
export interface FaviconAttrs {
  href: string;
  rel: string;
}

declare module "../features/favicon.js" {
  export interface Favicon {
    notify: import("@duckduckgo/messaging/lib/shared-types").MessagingBase<FaviconMessages>['notify']
  }
}