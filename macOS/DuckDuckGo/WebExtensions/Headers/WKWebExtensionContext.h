#import <Foundation/Foundation.h>
#import "WKWebExtensionMatchPattern.h"
#import "WKWebExtensionPermission.h"
#import "WKWebExtensionTab.h"

@class WKWebViewConfiguration;
@class WKWebExtension;
@class WKWebExtensionAction;
@class WKWebExtensionCommand;
@class WKWebExtensionController;

@class NSEvent;
@class NSMenuItem;

API_AVAILABLE(macos(15.3))
extern NSErrorDomain const WKWebExtensionContextErrorDomain;

typedef NS_ERROR_ENUM(WKWebExtensionContextErrorDomain, WKWebExtensionContextError) {
    WKWebExtensionContextErrorUnknown = 1,
    WKWebExtensionContextErrorAlreadyLoaded,
    WKWebExtensionContextErrorNotLoaded,
    WKWebExtensionContextErrorBaseURLAlreadyInUse,
    WKWebExtensionContextErrorNoBackgroundContent,
    WKWebExtensionContextErrorBackgroundContentFailedToLoad,
} API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextErrorsDidUpdateNotification;

typedef NS_ENUM(NSInteger, WKWebExtensionContextPermissionStatus) {
    WKWebExtensionContextPermissionStatusDeniedExplicitly    = -3,
    WKWebExtensionContextPermissionStatusDeniedImplicitly    = -2,
    WKWebExtensionContextPermissionStatusRequestedImplicitly = -1,
    WKWebExtensionContextPermissionStatusUnknown             =  0,
    WKWebExtensionContextPermissionStatusRequestedExplicitly =  1,
    WKWebExtensionContextPermissionStatusGrantedImplicitly   =  2,
    WKWebExtensionContextPermissionStatusGrantedExplicitly   =  3,
} API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextPermissionsWereGrantedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextPermissionsWereDeniedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextGrantedPermissionsWereRemovedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextDeniedPermissionsWereRemovedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextPermissionMatchPatternsWereGrantedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextPermissionMatchPatternsWereDeniedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextGrantedPermissionMatchPatternsWereRemovedNotification;
API_AVAILABLE(macos(15.3))
extern NSNotificationName const WKWebExtensionContextDeniedPermissionMatchPatternsWereRemovedNotification;

typedef NSString * WKWebExtensionContextNotificationUserInfoKey NS_TYPED_EXTENSIBLE_ENUM;

extern WKWebExtensionContextNotificationUserInfoKey const WKWebExtensionContextNotificationUserInfoKeyPermissions;
extern WKWebExtensionContextNotificationUserInfoKey const WKWebExtensionContextNotificationUserInfoKeyMatchPatterns;

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionContext : NSObject

+ (instancetype)contextForExtension:(WKWebExtension *)extension;
- (instancetype)initForExtension:(WKWebExtension *)extension NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly, strong) WKWebExtension *webExtension;
@property (nonatomic, readonly, weak, nullable) WKWebExtensionController *webExtensionController;
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;
@property (nonatomic, readonly, copy) NSArray<NSError *> *errors;
@property (nonatomic, copy) NSURL *baseURL;
@property (nonatomic, copy) NSString *uniqueIdentifier;
@property (nonatomic, getter=isInspectable) BOOL inspectable;
@property (nonatomic, nullable, copy) NSString *inspectionName;
@property (nonatomic, null_resettable, copy) NSSet<NSString *> *unsupportedAPIs;
@property (nonatomic, readonly, copy, nullable) WKWebViewConfiguration *webViewConfiguration;
@property (nonatomic, readonly, copy, nullable) NSURL *optionsPageURL;
@property (nonatomic, readonly, copy, nullable) NSURL *overrideNewTabPageURL;
@property (nonatomic, copy) NSDictionary<WKWebExtensionPermission, NSDate *> *grantedPermissions;
@property (nonatomic, copy) NSDictionary<WKWebExtensionMatchPattern *, NSDate *> *grantedPermissionMatchPatterns;
@property (nonatomic, copy) NSDictionary<WKWebExtensionPermission, NSDate *> *deniedPermissions;
@property (nonatomic, copy) NSDictionary<WKWebExtensionMatchPattern *, NSDate *> *deniedPermissionMatchPatterns;
@property (nonatomic) BOOL hasRequestedOptionalAccessToAllHosts;
@property (nonatomic) BOOL hasAccessToPrivateData;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionPermission> *currentPermissions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionMatchPattern *> *currentPermissionMatchPatterns;

- (BOOL)hasPermission:(WKWebExtensionPermission)permission;
- (BOOL)hasPermission:(WKWebExtensionPermission)permission inTab:(nullable id <WKWebExtensionTab>)tab;
- (BOOL)hasAccessToURL:(NSURL *)url;
- (BOOL)hasAccessToURL:(NSURL *)url inTab:(nullable id <WKWebExtensionTab>)tab;
@property (nonatomic, readonly) BOOL hasAccessToAllURLs;
@property (nonatomic, readonly) BOOL hasAccessToAllHosts;
@property (nonatomic, readonly) BOOL hasInjectedContent;
- (BOOL)hasInjectedContentForURL:(NSURL *)url;
@property (nonatomic, readonly) BOOL hasContentModificationRules;
- (WKWebExtensionContextPermissionStatus)permissionStatusForPermission:(WKWebExtensionPermission)permission;
- (WKWebExtensionContextPermissionStatus)permissionStatusForPermission:(WKWebExtensionPermission)permission inTab:(nullable id <WKWebExtensionTab>)tab;
- (WKWebExtensionContextPermissionStatus)permissionStatusForURL:(NSURL *)url;
- (WKWebExtensionContextPermissionStatus)permissionStatusForURL:(NSURL *)url inTab:(nullable id <WKWebExtensionTab>)tab;
- (void)setPermissionStatus:(WKWebExtensionContextPermissionStatus)status forPermission:(WKWebExtensionPermission)permission expirationDate:(nullable NSDate *)expirationDate;
- (WKWebExtensionContextPermissionStatus)permissionStatusForURL:(NSURL *)url inTab:(nullable id <WKWebExtensionTab>)tab;
- (void)setPermissionStatus:(WKWebExtensionContextPermissionStatus)status forURL:(NSURL *)url expirationDate:(nullable NSDate *)expirationDate;
- (WKWebExtensionContextPermissionStatus)permissionStatusForMatchPattern:(WKWebExtensionMatchPattern *)pattern;
- (WKWebExtensionContextPermissionStatus)permissionStatusForMatchPattern:(WKWebExtensionMatchPattern *)pattern inTab:(nullable id <WKWebExtensionTab>)tab;
- (void)setPermissionStatus:(WKWebExtensionContextPermissionStatus)status forMatchPattern:(WKWebExtensionMatchPattern *)pattern expirationDate:(nullable NSDate *)expirationDate;
- (void)loadBackgroundContentWithCompletionHandler:(void (^)(NSError * _Nullable error))completionHandler;
- (nullable WKWebExtensionAction *)actionForTab:(nullable id <WKWebExtensionTab>)tab;
- (void)performActionForTab:(nullable id <WKWebExtensionTab>)tab;
@property (nonatomic, readonly, copy) NSArray<WKWebExtensionCommand *> *commands;
- (void)performCommand:(WKWebExtensionCommand *)command;
- (BOOL)performCommandForEvent:(NSEvent *)event;
- (nullable WKWebExtensionCommand *)commandForEvent:(NSEvent *)event;
- (void)userGesturePerformedInTab:(id <WKWebExtensionTab>)tab;
- (BOOL)hasActiveUserGestureInTab:(id <WKWebExtensionTab>)tab;
- (void)clearUserGestureInTab:(id <WKWebExtensionTab>)tab;
@property (nonatomic, readonly, copy) NSArray<id <WKWebExtensionWindow>> *openWindows;
@property (nonatomic, readonly, weak, nullable) id <WKWebExtensionWindow> focusedWindow;
@property (nonatomic, readonly, copy) NSSet<id <WKWebExtensionTab>> *openTabs;
- (void)didOpenWindow:(id <WKWebExtensionWindow>)newWindow;
- (void)didCloseWindow:(id <WKWebExtensionWindow>)closedWindow;
- (void)didFocusWindow:(nullable id <WKWebExtensionWindow>)focusedWindow;
- (void)didOpenTab:(id <WKWebExtensionTab>)newTab;
- (void)didCloseTab:(id <WKWebExtensionTab>)closedTab windowIsClosing:(BOOL)windowIsClosing;
- (void)didActivateTab:(id<WKWebExtensionTab>)activatedTab previousActiveTab:(nullable id<WKWebExtensionTab>)previousTab;
- (void)didSelectTabs:(NSSet<id <WKWebExtensionTab>> *)selectedTabs;
- (void)didDeselectTabs:(NSSet<id <WKWebExtensionTab>> *)deselectedTabs;
- (void)didMoveTab:(id <WKWebExtensionTab>)movedTab fromIndex:(NSUInteger)index inWindow:(nullable id <WKWebExtensionWindow>)oldWindow;
- (void)didReplaceTab:(id <WKWebExtensionTab>)oldTab withTab:(id <WKWebExtensionTab>)newTab;
- (void)didChangeTabProperties:(WKWebExtensionTabChangedProperties)properties forTab:(id <WKWebExtensionTab>)changedTab;

@end
