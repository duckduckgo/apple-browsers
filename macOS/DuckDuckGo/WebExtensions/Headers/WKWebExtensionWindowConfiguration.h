#import <Foundation/Foundation.h>
#import "WKWebExtensionWindow.h"

@protocol WKWebExtensionTab;

API_AVAILABLE(macos(15.3)) WK_SWIFT_UI_ACTOR NS_SWIFT_NAME(WKWebExtension.WindowConfiguration)
@interface WKWebExtensionWindowConfiguration : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) WKWebExtensionWindowType windowType;
@property (nonatomic, readonly) WKWebExtensionWindowState windowState;
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly, copy) NSArray<NSURL *> *tabURLs;
@property (nonatomic, readonly, copy) NSArray<id <WKWebExtensionTab>> *tabs;
@property (nonatomic, readonly) BOOL shouldBeFocused;
@property (nonatomic, readonly) BOOL shouldBePrivate;

@end
