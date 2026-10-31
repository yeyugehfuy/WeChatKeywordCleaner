// WeChatKeywordCleaner.h
// Shared declarations for the in-app search and delete UI.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface WeChatBridge : NSObject
// Results are dictionaries containing msgId, talker, and content.
+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *results))completion;
+ (NSString *)lastSearchDiagnostic;
// Batch deletion through WeChat 8.0.68 CMessageMgr using per-session message wraps.
+ (void)deleteMessages:(NSArray *)messages completion:(void (^)(BOOL success))completion;
@end
