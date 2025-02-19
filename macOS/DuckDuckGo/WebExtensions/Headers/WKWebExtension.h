#import <Foundation/Foundation.h>

#import "WKWebExtensionMatchPattern.h"
#import "WKWebExtensionPermission.h"

@class NSImage;

API_AVAILABLE(macos(15.3))
WK_EXTERN NSErrorDomain const WKWebExtensionErrorDomain NS_SWIFT_NAME(WKWebExtension.errorDomain) NS_SWIFT_NONISOLATED;

API_AVAILABLE(macos(15.3))
NS_SWIFT_NAME(WKWebExtension.Error)
typedef NS_ERROR_ENUM(WKWebExtensionErrorDomain, WKWebExtensionError) {
    WKWebExtensionErrorUnknown = 1,
    WKWebExtensionErrorResourceNotFound,
    WKWebExtensionErrorInvalidResourceCodeSignature,
    WKWebExtensionErrorInvalidManifest,
    WKWebExtensionErrorUnsupportedManifestVersion,
    WKWebExtensionErrorInvalidManifestEntry,
    WKWebExtensionErrorInvalidDeclarativeNetRequestEntry,
    WKWebExtensionErrorInvalidBackgroundPersistence,
};

API_AVAILABLE(macos(15.3))
NS_SWIFT_UI_ACTOR
@interface WKWebExtension : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)extensionWithAppExtensionBundle:(NSBundle *)appExtensionBundle
                      completionHandler:(void (^)(WKWebExtension * _Nullable extension, NSError * _Nullable error))completionHandler API_AVAILABLE(macos(15.3));

+ (void)extensionWithResourceBaseURL:(NSURL *)resourceBaseURL
                   completionHandler:(void (^)(WKWebExtension * _Nullable extension, NSError * _Nullable error))completionHandler API_AVAILABLE(macos(15.3));

@property (nonatomic, readonly, copy) NSArray<NSError *> *errors;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *manifest;
@property (nonatomic, readonly) double manifestVersion;

- (BOOL)supportsManifestVersion:(double)manifestVersion;

@property (nonatomic, nullable, readonly, copy) NSLocale *defaultLocale;
@property (nonatomic, nullable, readonly, copy) NSString *displayName;
@property (nonatomic, nullable, readonly, copy) NSString *displayShortName;
@property (nonatomic, nullable, readonly, copy) NSString *displayVersion;
@property (nonatomic, nullable, readonly, copy) NSString *displayDescription;
@property (nonatomic, nullable, readonly, copy) NSString *displayActionLabel;
@property (nonatomic, nullable, readonly, copy) NSString *version;

- (nullable NSImage *)iconForSize:(CGSize)size;
- (nullable NSImage *)actionIconForSize:(CGSize)size;

@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *requestedPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *optionalPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *requestedPermissionMatchPatterns;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *optionalPermissionMatchPatterns;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *allRequestedMatchPatterns;
@property (nonatomic, readonly) BOOL hasBackgroundContent;
@property (nonatomic, readonly) BOOL hasPersistentBackgroundContent;
@property (nonatomic, readonly) BOOL hasInjectedContent;
@property (nonatomic, readonly) BOOL hasOptionsPage;
@property (nonatomic, readonly) BOOL hasOverrideNewTabPage;
@property (nonatomic, readonly) BOOL hasCommands;
@property (nonatomic, readonly) BOOL hasContentModificationRules;

@end
