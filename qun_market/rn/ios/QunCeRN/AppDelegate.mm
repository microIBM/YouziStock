#import "AppDelegate.h"

#import <React/RCTBundleURLProvider.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.moduleName = @"QunCeRN";
  // You can add your custom initial props in the dictionary below.
  // They will be passed down to the ViewController used by React Native.
  self.initialProps = @{};

  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

@end

#import <React/RCTBridgeModule.h>
@interface QunNetwork : NSObject <RCTBridgeModule>
@end
@implementation QunNetwork
RCT_EXPORT_MODULE();
+ (BOOL)requiresMainQueueSetup { return NO; }
RCT_REMAP_METHOD(probe, probeWithResolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
  NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  config.timeoutIntervalForRequest = 10;
  config.timeoutIntervalForResource = 15;
  config.waitsForConnectivity = NO;
  config.URLCache = nil;
  config.HTTPCookieStorage = nil;
  config.URLCredentialStorage = nil;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
  [[session dataTaskWithURL:[NSURL URLWithString:@"https://captive.apple.com/hotspot-detect.html"] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error) {
      NSString *message = [NSString stringWithFormat:@"原生联网失败：%@ code=%ld %@", error.domain, (long)error.code, error.localizedDescription];
      reject(@"NETWORK_PROBE", message, error);
    } else {
      resolve([NSString stringWithFormat:@"原生 HTTPS 探活 HTTP %ld；只验证探活地址，不代表模型接口已连通。", (long)((NSHTTPURLResponse *)response).statusCode]);
    }
    [session finishTasksAndInvalidate];
  }] resume];
}
@end
