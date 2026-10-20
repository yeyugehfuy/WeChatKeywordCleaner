// WeChatKeywordCleaner.h
// Shared declarations: floating button entry point and search/delete bridge.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Add the "清" floating button inside WeChat.
void ShowKeywordCleanerFloatingButton(void);

#ifdef __cplusplus
}
#endif

@interface WeChatBridge : NSObject
// Results are dictionaries containing msgId, talker, and content.
+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *results))completion;
// Batch deletion. This remains unavailable until the exact WeChat 8.0.68 API is verified.
+ (void)deleteMessages:(NSArray *)messages completion:(void (^)(BOOL success))completion;
@end
