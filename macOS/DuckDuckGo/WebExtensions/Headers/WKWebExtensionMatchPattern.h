#import <Foundation/Foundation.h>

@class WKWebExtension;

API_AVAILABLE(macos(15.3))
WK_EXTERN NSErrorDomain const WKWebExtensionMatchPatternErrorDomain;

typedef NS_ERROR_ENUM(WKWebExtensionMatchPatternErrorDomain, WKWebExtensionMatchPatternError) {
    WKWebExtensionMatchPatternErrorUnknown = 1,
    WKWebExtensionMatchPatternErrorInvalidScheme,
    WKWebExtensionMatchPatternErrorInvalidHost,
    WKWebExtensionMatchPatternErrorInvalidPath,
} API_AVAILABLE(macos(15.3));

typedef NS_OPTIONS(NSUInteger, WKWebExtensionMatchPatternOptions) {
    WKWebExtensionMatchPatternOptionsNone                 = 0,
    WKWebExtensionMatchPatternOptionsIgnoreSchemes        = 1 << 0,
    WKWebExtensionMatchPatternOptionsIgnorePaths          = 1 << 1,
    WKWebExtensionMatchPatternOptionsMatchBidirectionally = 1 << 2,
} API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionMatchPattern : NSObject <NSSecureCoding, NSCopying>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)registerCustomURLScheme:(NSString *)urlScheme;

+ (instancetype)allURLsMatchPattern;
+ (instancetype)allHostsAndSchemesMatchPattern;
+ (nullable instancetype)matchPatternWithString:(NSString *)string;
+ (nullable instancetype)matchPatternWithScheme:(NSString *)scheme host:(NSString *)host path:(NSString *)path;

- (nullable instancetype)initWithString:(NSString *)string error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithScheme:(NSString *)scheme host:(NSString *)host path:(NSString *)path error:(NSError **)error NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly, copy) NSString *string;
@property (nonatomic, nullable, readonly, copy) NSString *scheme;
@property (nonatomic, nullable, readonly, copy) NSString *host;
@property (nonatomic, nullable, readonly, copy) NSString *path;
@property (nonatomic, readonly) BOOL matchesAllURLs;
@property (nonatomic, readonly) BOOL matchesAllHosts;

- (BOOL)matchesURL:(nullable NSURL *)url NS_SWIFT_UNAVAILABLE("Use options version with empty options set");
- (BOOL)matchesURL:(nullable NSURL *)url options:(WKWebExtensionMatchPatternOptions)options NS_SWIFT_NAME(matches(_:options:));
- (BOOL)matchesPattern:(nullable WKWebExtensionMatchPattern *)pattern NS_SWIFT_UNAVAILABLE("Use options version with empty options set");
- (BOOL)matchesPattern:(nullable WKWebExtensionMatchPattern *)pattern options:(WKWebExtensionMatchPatternOptions)options NS_SWIFT_NAME(matches(_:options:));

@end
