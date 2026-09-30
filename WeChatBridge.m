// WeChatBridge.m —— 数据层（关键：必须替换成微信 8.0.68 的真实 API）
//
// 下面两个方法是“占位实现”：能编译、运行不会真删。
// 要真正能用，你必须拿到微信 8.0.68 的头文件，把方法体换成真实调用。
//
// ┌─ 如何拿到 8.0.68 头文件 ───────────────────────────────┐
// │ 1) 脱壳：TrollStore 装 dump 工具（如 Crane / 砸壳类），│
// │    导出微信 .decrypted（或 .ipa）。                     │
// │ 2) class-dump 导出头文件。重点找：                      │
// │    - 消息管理类：旧版叫 CMessageMgr，新版可能改名        │
// │      （如 WCMessageNewMgr / MessageManager 等）         │
// │    - 消息模型类：CMessageWrap / WCMessageNew，字段如     │
// │      m_nsContent（内容）、m_nsFromUsr（发送方）、        │
// │      m_nMesLocalID（本地ID）、m_uiMessageType           │
// │ 3) 参考已在 8.0.68 能跑的「微信助手」里的消息相关调用，  │
// │    或真机用 Flex 实时看 CMessageMgr 的方法名。          │
// └────────────────────────────────────────────────────────┘
//
// 历史参考（仅示意，8.0.68 不一定适用，方法名以你 dump 到的头为准）：
//   搜索：
//     Class cls = %c(CMessageMgr);
//     CMessageMgr *mgr = [cls defaultMgr];      // 或 [[cls alloc] init]
//     NSArray *list = [mgr GetMsgListByKeyword:keyword];  // 方法名是编的，需核对
//   删除：
//     [mgr DelMsg:talker msgList:@[msg] onlyDelDb:YES];   // 方法名需核对
//
// 另外微信消息存储在本地加密 DB（WCDB/SQLCipher），若走 DB 直查，
// 还需微信的密钥与 DB 路径，同样要 8.0.68 头文件定位。

#import "WeChatKeywordCleaner.h"

@implementation WeChatBridge

+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *))completion {
    // TODO: 替换成真实搜索逻辑（按 keyword 查 CMessageMgr / 本地 DB）
    NSLog(@"[WeChatKeywordCleaner] 占位搜索：%@", keyword);
    if (completion) completion(@[]); // 返回空，等接入真实 API
}

+ (void)deleteMessages:(NSArray *)messages completion:(void (^)(BOOL))completion {
    // TODO: 替换成真实删除逻辑（删除 messages 里的 msgId）
    NSLog(@"[WeChatKeywordCleaner] 占位删除：%lu 条", (unsigned long)messages.count);
    if (completion) completion(YES);
}

@end
