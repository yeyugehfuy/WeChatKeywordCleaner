// WeChatBridge.m
// The exact WeChat 8.0.68 message search/delete API has not been verified yet.
// Keep the bridge fail-closed until matching headers or runtime traces are available.
#import "WeChatKeywordCleaner.h"

@implementation WeChatBridge

+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *))completion {
    NSLog(@"[WeChatKeywordCleaner] Search unavailable: WeChat 8.0.68 API is not verified (keyword length: %lu)",
          (unsigned long)keyword.length);
    if (completion) completion(@[]);
}

+ (void)deleteMessages:(NSArray *)messages completion:(void (^)(BOOL))completion {
    NSLog(@"[WeChatKeywordCleaner] Delete unavailable: WeChat 8.0.68 API is not verified (%lu results)",
          (unsigned long)messages.count);
    // Do not report success or clear the results when no deletion occurred.
    if (completion) completion(NO);
}

@end
