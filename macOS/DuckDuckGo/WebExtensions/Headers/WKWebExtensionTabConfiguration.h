#import <Foundation/Foundation.h>

@protocol WKWebExtensionTab;
@protocol WKWebExtensionWindow;

API_AVAILABLE(macos(15.3)) NS_SWIFT_UI_ACTOR NS_SWIFT_NAME(WKWebExtension.TabConfiguration)
@interface WKWebExtensionTabConfiguration : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, nullable, readonly, strong) id <WKWebExtensionWindow> window;
@property (nonatomic, readonly) NSUInteger index;
@property (nonatomic, nullable, readonly, strong) id <WKWebExtensionTab> parentTab;
@property (nonatomic, nullable, readonly, copy) NSURL *url;
@property (nonatomic, readonly) BOOL shouldBeActive;
@property (nonatomic, readonly) BOOL shouldAddToSelection;
@property (nonatomic, readonly) BOOL shouldBePinned;
@property (nonatomic, readonly) BOOL shouldBeMuted;
@property (nonatomic, readonly) BOOL shouldReaderModeBeActive;

@end
