#import <Foundation/Foundation.h>

#import "WKWebExtensionMatchPattern.h"
#import "WKWebExtensionPermission.h"

@class WKWebView;
@class WKWebExtensionContext;
@class NSImage;
@class NSMenuItem;
@class NSPopover;
@protocol WKWebExtensionTab;

API_AVAILABLE(macos(15.3))
WK_EXTERN NSNotificationName const WKWebExtensionActionPropertiesDidChangeNotification NS_SWIFT_NAME(WKWebExtensionAction.propertiesDidChangeNotification) NS_SWIFT_NONISOLATED;

API_AVAILABLE(macos(15.3))
WK_SWIFT_UI_ACTOR NS_SWIFT_NAME(WKWebExtension.Action)
@interface WKWebExtensionAction : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly, weak) WKWebExtensionContext *webExtensionContext;
@property (nonatomic, readonly, nullable, weak) id <WKWebExtensionTab> associatedTab;

- (nullable NSImage *)iconForSize:(CGSize)size;

@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, copy) NSString *badgeText;
@property (nonatomic) BOOL hasUnreadBadgeText;
@property (nonatomic, nullable, copy) NSString *inspectionName;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, copy) NSArray<NSMenuItem *> *menuItems;
@property (nonatomic, readonly) BOOL presentsPopup;
@property (nonatomic, readonly, nullable) NSPopover *popupPopover;
@property (nonatomic, readonly, nullable) WKWebView *popupWebView;

- (void)closePopup;

@end
