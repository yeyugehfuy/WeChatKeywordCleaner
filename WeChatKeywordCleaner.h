// WeChatKeywordCleaner.h
// 共享声明：悬浮按钮入口 + 数据层桥接（搜/删依赖微信 8.0.68 真实 API）
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 在微信界面上加一个悬浮按钮「清」，点击弹出关键字清理界面
void ShowKeywordCleanerFloatingButton(void);

// 数据层桥接：搜索与删除都依赖微信 8.0.68 的真实类/方法，下面仅为占位签名
@interface WeChatBridge : NSObject
// 按关键字搜索聊天记录；回调数组元素为 @{@"msgId":, @"talker":, @"content":}
+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *results))completion;
// 批量删除
+ (void)deleteMessages:(NSArray *)messages completion:(void (^)(BOOL success))completion;
@end
