#import "WKWebExtension.h"

@interface WKWebExtension ()

- (nullable instancetype)initWithAppExtensionBundle:(NSBundle *)appExtensionBundle error:(NSError **)error;
- (nullable instancetype)initWithResourceBaseURL:(NSURL *)resourceBaseURL error:(NSError **)error;

- (nullable instancetype)_initWithAppExtensionBundle:(NSBundle *)appExtensionBundle error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)_initWithResourceBaseURL:(NSURL *)resourceBaseURL error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)_initWithManifestDictionary:(NSDictionary<NSString *, id> *)manifest;
- (nullable instancetype)_initWithManifestDictionary:(NSDictionary<NSString *, id> *)manifest resources:(nullable NSDictionary<NSString *, id> *)resources NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)_initWithResources:(NSDictionary<NSString *, id> *)resources NS_DESIGNATED_INITIALIZER;

@property (readonly, nonatomic) BOOL _hasServiceWorkerBackgroundContent;
@property (readonly, nonatomic) BOOL _hasModularBackgroundContent;
@property (readonly, nonatomic) BOOL _hasSidebar;

@end
