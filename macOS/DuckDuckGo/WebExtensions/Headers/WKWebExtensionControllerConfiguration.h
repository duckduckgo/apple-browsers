#import <Foundation/Foundation.h>

@class WKWebViewConfiguration;
@class WKWebsiteDataStore;
@class WKWebExtensionController;

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionControllerConfiguration : NSObject <NSSecureCoding, NSCopying>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)defaultConfiguration;
+ (instancetype)nonPersistentConfiguration;
+ (instancetype)configurationWithIdentifier:(NSUUID *)identifier;

@property (nonatomic, readonly, getter=isPersistent) BOOL persistent;
@property (nonatomic, nullable, readonly, copy) NSUUID *identifier;
@property (nonatomic, null_resettable, copy) WKWebViewConfiguration *webViewConfiguration;
@property (nonatomic, null_resettable, retain) WKWebsiteDataStore *defaultWebsiteDataStore;

@end
