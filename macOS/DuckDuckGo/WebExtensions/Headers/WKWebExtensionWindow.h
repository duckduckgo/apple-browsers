#import <Foundation/Foundation.h>

@class WKWebExtensionContext;
@protocol WKWebExtensionTab;

typedef NS_ENUM(NSInteger, WKWebExtensionWindowType) {
    WKWebExtensionWindowTypeNormal,
    WKWebExtensionWindowTypePopup,
} NS_SWIFT_NAME(WKWebExtension.WindowType) API_AVAILABLE(macos(15.3));

typedef NS_ENUM(NSInteger, WKWebExtensionWindowState) {
    WKWebExtensionWindowStateNormal,
    WKWebExtensionWindowStateMinimized,
    WKWebExtensionWindowStateMaximized,
    WKWebExtensionWindowStateFullscreen,
} NS_SWIFT_NAME(WKWebExtension.WindowState) API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3)) WK_SWIFT_UI_ACTOR
@protocol WKWebExtensionWindow <NSObject>
//@optional

- (NSArray<id <WKWebExtensionTab>> *)tabsForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(tabs(for:));
- (nullable id <WKWebExtensionTab>)activeTabForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(activeTab(for:));
- (WKWebExtensionWindowType)windowTypeForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(windowType(for:));
- (WKWebExtensionWindowState)windowStateForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(windowState(for:));
- (void)setWindowState:(WKWebExtensionWindowState)state forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setWindowState(_:for:completionHandler:));
- (BOOL)isPrivateForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isPrivate(for:));

#if TARGET_OS_OSX
- (CGRect)screenFrameForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(screenFrame(for:));
#endif

- (CGRect)frameForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(frame(for:));
- (void)setFrame:(CGRect)frame forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setFrame(_:for:completionHandler:));
- (void)focusForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(focus(for:completionHandler:));
- (void)closeForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(close(for:completionHandler:));

@end
