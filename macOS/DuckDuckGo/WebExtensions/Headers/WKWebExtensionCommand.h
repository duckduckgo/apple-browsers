#import <Foundation/Foundation.h>

#import "WKWebExtensionMatchPattern.h"
#import "WKWebExtensionPermission.h"

@class WKWebExtensionContext;
@class NSMenuItem;

API_AVAILABLE(macos(15.3))
NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(WKWebExtension.Command)
@interface WKWebExtensionCommand : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, weak) WKWebExtensionContext *webExtensionContext;
@property (nonatomic, readonly, copy) NSString *identifier NS_SWIFT_NAME(id);
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, nullable, copy) NSString *activationKey;
@property (nonatomic) NSEventModifierFlags modifierFlags;
@property (nonatomic, readonly, copy) NSMenuItem *menuItem;

@end
