#import "WKWebExtensionContext.h"

@class WKWebExtensionSidebar;

@interface WKWebExtensionContext ()

@property (nonatomic, nullable, readonly) WKWebView *_backgroundWebView;
@property (nonatomic, nullable, readonly) NSURL *_backgroundContentURL;

- (nullable WKWebExtensionSidebar *)sidebarForTab:(nullable id <WKWebExtensionTab>)tab NS_SWIFT_NAME(sidebar(for:));

@end
