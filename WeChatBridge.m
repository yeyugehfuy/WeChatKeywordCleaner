// WeChatBridge.m
// Runtime bridge for the WeChat 8.0.68 message search and deletion APIs.
#import "WeChatKeywordCleaner.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdint.h>

static NSString *KWSearchDiagnostic = @"尚未搜索";

static void KWSetSearchDiagnostic(NSString *diagnostic) {
    @synchronized ([WeChatBridge class]) {
        KWSearchDiagnostic = [diagnostic copy] ?: @"";
    }
}

static NSString *KWGetSearchDiagnostic(void) {
    @synchronized ([WeChatBridge class]) {
        return [KWSearchDiagnostic copy] ?: @"";
    }
}

static id KWSendObject0(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static id KWSendObject1(id target, NSString *selectorName, id arg1) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(target, selector, arg1);
}

static id KWSendObject2(id target, NSString *selectorName, id arg1, id arg2) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id, id))objc_msgSend)(target, selector, arg1, arg2);
}

static id KWSendObject3(id target, SEL selector, id arg1, id arg2, id arg3) {
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)(target, selector, arg1, arg2, arg3);
}

static id KWSendObject4(id target, SEL selector, id arg1, id arg2, uint32_t arg3, id arg4) {
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, id, id, uint32_t, id))objc_msgSend)(target, selector,
                                                                   arg1, arg2, arg3, arg4);
}

static uint32_t KWSendUInt0(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) return 0;
    return ((uint32_t (*)(id, SEL))objc_msgSend)(target, selector);
}

static id KWSendMessageForLocalID(id target, SEL selector, id talker, uint32_t localID) {
    return ((id (*)(id, SEL, id, uint32_t))objc_msgSend)(target, selector, talker, localID);
}

static void KWSendDeleteBatch(id target, SEL selector, id talker, NSArray *wraps) {
    ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(target, selector, talker, wraps, NO);
}

static void KWAddContext(NSMutableArray *contexts, NSHashTable *visited, id context) {
    if (!context || [visited containsObject:context]) return;
    [visited addObject:context];
    [contexts addObject:context];
}

static BOOL KWSendBool1(id target, NSString *selectorName, id arg1) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(target, selector, arg1);
}

static id KWGetService(NSString *className) {
    Class serviceClass = objc_getClass(className.UTF8String);
    if (!serviceClass) {
        NSLog(@"[WeChatKeywordCleaner] Service class %@ is not loaded", className);
        return nil;
    }

    NSMutableArray *contexts = [NSMutableArray array];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
                            NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    Class contextClass = objc_getClass("MMContext");
    if (contextClass) {
        // Prefer the logged-in user's context, then inspect every known context.
        KWAddContext(contexts, visited, KWSendObject0((id)contextClass, @"activeUserContext"));
        KWAddContext(contexts, visited, KWSendObject0((id)contextClass, @"currentContext"));
        KWAddContext(contexts, visited, KWSendObject0((id)contextClass, @"lastContext"));
        KWAddContext(contexts, visited, KWSendObject0((id)contextClass, @"rootContext"));
    }

    Class contextManagerClass = objc_getClass("MMContextManager");
    id contextManager = KWSendObject0((id)contextManagerClass, @"defaultManager");
    KWAddContext(contexts, visited, KWSendObject0(contextManager, @"activeUserContext"));
    id allContexts = KWSendObject0(contextManager, @"allContexts");
    if ([allContexts isKindOfClass:[NSArray class]]) {
        for (id context in (NSArray *)allContexts) {
            KWAddContext(contexts, visited, context);
        }
    }

    NSUInteger registeredContextCount = 0;
    NSUInteger registeredCenterCount = 0;
    for (id context in contexts) {
        if (KWSendBool1(context, @"isServiceExist:", (id)serviceClass)) {
            registeredContextCount++;
        }
        id service = KWSendObject1(context, @"getService:", (id)serviceClass);
        if (service) return service;

        id serviceCenter = KWSendObject0(context, @"serviceCenter");
        if (KWSendBool1(serviceCenter, @"isServiceExist:", (id)serviceClass)) {
            registeredCenterCount++;
        }
        service = KWSendObject1(serviceCenter, @"getService:", (id)serviceClass);
        if (service) return service;
    }

    if ([className isEqualToString:@"FTSMessageMgr"] ||
        [className isEqualToString:@"FTSIntelligentMessageMgr"]) {
        NSString *diagnostic = [NSString stringWithFormat:
                                @"%@：检查 %lu 个 MMContext，已注册 %lu 个，serviceCenter 已注册 %lu 个，均未返回实例。",
                                className,
                                (unsigned long)contexts.count,
                                (unsigned long)registeredContextCount,
                                (unsigned long)registeredCenterCount];
        KWSetSearchDiagnostic(diagnostic);
    }
    NSLog(@"[WeChatKeywordCleaner] Could not resolve %@ across %lu contexts",
          className, (unsigned long)contexts.count);
    return nil;
}

static id KWGetMessageSearchManager(void) {
    NSArray<NSDictionary<NSString *, NSString *> *> *backends = @[
        @{@"service": @"FTSMessageMgr", @"manager": @"FTSMsgSearchMgr"},
        @{@"service": @"FTSIntelligentMessageMgr", @"manager": @"FTSIntelligentMsgSearchMgr"}
    ];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    for (NSDictionary<NSString *, NSString *> *backend in backends) {
        NSString *serviceName = backend[@"service"];
        NSString *managerName = backend[@"manager"];
        id service = KWGetService(serviceName);
        if (!service) {
            NSString *diagnostic = KWGetSearchDiagnostic();
            if (diagnostic.length) [failures addObject:diagnostic];
            continue;
        }

        id searchManager = KWSendObject0(service, @"searchMgr");
        if (searchManager) {
            KWSetSearchDiagnostic([NSString stringWithFormat:@"已取得 %@ 的原生搜索管理器。", serviceName]);
            return searchManager;
        }

        id database = KWSendObject0(service, @"ftsMessageDB");
        Class searchManagerClass = objc_getClass(managerName.UTF8String);
        if (!database || !searchManagerClass) {
            [failures addObject:[NSString stringWithFormat:
                                 @"%@ 已取得，但数据库或搜索管理器类为空。", serviceName]];
            continue;
        }

        id allocated = KWSendObject0((id)searchManagerClass, @"alloc");
        searchManager = KWSendObject1(allocated, @"initWithDB:", database);
        if (searchManager) {
            KWSendObject1(service, @"setSearchMgr:", searchManager);
            KWSetSearchDiagnostic([NSString stringWithFormat:@"已初始化 %@ 原生搜索管理器。", serviceName]);
            return searchManager;
        }
        [failures addObject:[NSString stringWithFormat:@"%@ 搜索管理器初始化失败。", serviceName]];
    }

    if (failures.count) {
        KWSetSearchDiagnostic([failures componentsJoinedByString:@"；"]);
    } else {
        KWSetSearchDiagnostic(@"微信未提供可用的消息全文搜索服务。");
    }
    return nil;
}

static NSString *KWDisplayNameForTalker(id contactManager, NSString *talker) {
    id contact = KWSendObject1(contactManager, @"getContactForSearchByName:", talker);
    NSString *remark = KWSendObject0(contact, @"m_nsRemark");
    NSString *nickname = KWSendObject0(contact, @"m_nsNickName");
    if ([remark isKindOfClass:[NSString class]] && remark.length) return remark;
    if ([nickname isKindOfClass:[NSString class]] && nickname.length) return nickname;
    return talker;
}

static void KWAppendFTSItems(id object, NSMutableArray *items, NSHashTable *visited) {
    if (!object || object == [NSNull null] || [visited containsObject:object]) return;
    [visited addObject:object];

    if ([object isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)object) KWAppendFTSItems(child, items, visited);
        return;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (id child in [(NSDictionary *)object allValues]) KWAppendFTSItems(child, items, visited);
        return;
    }

    if ([object respondsToSelector:NSSelectorFromString(@"userName")] &&
        [object respondsToSelector:NSSelectorFromString(@"localId")]) {
        [items addObject:object];
        return;
    }

    NSArray *childSelectors = @[
        @"arrMsgItems", @"arrMsgItem", @"arrSessionResult",
        @"arrSessionResultItem", @"clusterResults"
    ];
    for (NSString *name in childSelectors) {
        id child = KWSendObject0(object, name);
        if (child && child != object) KWAppendFTSItems(child, items, visited);
    }
}

static id KWDirectFTSQuery(NSString *keyword) {
    NSString *regularFailure = nil;
    id service = KWGetService(@"FTSMessageMgr");
    if (service) {
        id database = KWSendObject0(service, @"ftsMessageDB");
        SEL querySelector = NSSelectorFromString(@"queryText:limitUsrname:cancelBlock:");
        if (database && [database respondsToSelector:querySelector]) {
            @try {
                id result = KWSendObject3(database, querySelector, keyword, nil, nil);
                if (result) return result;
                regularFailure = @"FTSMessageMgr 查询返回空结果";
            } @catch (NSException *exception) {
                regularFailure = [NSString stringWithFormat:@"FTSMessageMgr 查询异常：%@", exception.name];
            }
        } else {
            regularFailure = @"FTSMessageMgr 没有可用的 ftsMessageDB/queryText 接口";
        }
    } else {
        regularFailure = KWGetSearchDiagnostic();
    }

    id intelligentService = KWGetService(@"FTSIntelligentMessageMgr");
    if (intelligentService) {
        id database = KWSendObject0(intelligentService, @"ftsMessageDB");
        SEL querySelector = NSSelectorFromString(@"queryText:limitUsrname:searchType:cancelBlock:");
        if (database && [database respondsToSelector:querySelector]) {
            @try {
                // Search type 0 is the default text-search path in this API.
                id result = KWSendObject4(database, querySelector, keyword, nil, 0, nil);
                if (result) return result;
                KWSetSearchDiagnostic(@"FTSIntelligentMessageMgr 的文本查询返回空结果。");
            } @catch (NSException *exception) {
                KWSetSearchDiagnostic([NSString stringWithFormat:
                                       @"FTSIntelligentMessageMgr 查询异常：%@", exception.name]);
            }
        } else {
            KWSetSearchDiagnostic(@"FTSIntelligentMessageMgr 已取得，但数据库或文本查询接口为空。");
        }
    } else {
        NSString *intelligentFailure = KWGetSearchDiagnostic();
        KWSetSearchDiagnostic([NSString stringWithFormat:@"%@；普通消息索引：%@；智能消息索引：%@",
                               @"直接搜索未执行",
                               regularFailure ?: @"不可用",
                               intelligentFailure.length ? intelligentFailure : @"服务未注册"]);
    }
    return nil;
}

static NSArray *KWResolveFTSItems(NSArray *items, NSString *keyword) {
    id contactManager = KWGetService(@"CContactMgr");
    id messageManager = KWGetService(@"CMessageMgr");
    SEL getMessageSelector = NSSelectorFromString(@"GetMsg:LocalID:");

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableSet *seen = [NSMutableSet set];
    for (id item in items) {
        NSString *talker = KWSendObject0(item, @"userName");
        uint32_t localID = KWSendUInt0(item, @"localId");
        if (!talker.length || localID == 0) continue;

        NSString *uniqueKey = [NSString stringWithFormat:@"%@:%u", talker, localID];
        if ([seen containsObject:uniqueKey]) continue;
        [seen addObject:uniqueKey];

        id wrap = KWSendObject0(item, @"msgWrap");
        Class wrapClass = objc_getClass("CMessageWrap");
        if (wrapClass && wrap && ![wrap isKindOfClass:wrapClass]) wrap = nil;
        if (wrap && KWSendUInt0(wrap, @"m_uiMesLocalID") != localID) wrap = nil;
        if (!wrap && messageManager && [messageManager respondsToSelector:getMessageSelector]) {
            wrap = KWSendMessageForLocalID(messageManager, getMessageSelector, talker, localID);
        }
        if (wrapClass && wrap && ![wrap isKindOfClass:wrapClass]) wrap = nil;
        if (wrap && KWSendUInt0(wrap, @"m_uiMesLocalID") != localID) wrap = nil;

        // Some FTS items contain the searchable text but omit msgWrap. Show those
        // indexed candidates; deleteMessages re-fetches the message and re-checks
        // the literal keyword before any deletion is sent.
        NSString *content = wrap ? KWSendObject0(wrap, @"m_nsContent") : nil;
        BOOL indexOnly = ![content isKindOfClass:[NSString class]] || !content.length;
        if (indexOnly) content = KWSendObject0(item, @"ftsContent");
        if (![content isKindOfClass:[NSString class]] || !content.length) continue;

        NSRange exactMatch = [content rangeOfString:keyword
                                            options:(NSCaseInsensitiveSearch | NSLiteralSearch)];
        if (exactMatch.location == NSNotFound) continue;

        NSString *displayName = KWDisplayNameForTalker(contactManager, talker);
        [results addObject:@{
            @"msgId": [NSString stringWithFormat:@"%u", localID],
            @"talker": talker,
            @"displayName": displayName ?: talker,
            @"content": content,
            @"__talker": talker,
            @"__localID": @(localID),
            @"__keyword": keyword,
            @"__indexOnly": @(indexOnly),
            @"__msgWrap": wrap ?: [NSNull null]
        }];
    }
    return results;
}

static NSArray *KWBuildSearchResults(id handler, NSString *keyword) {
    // WeChat 8.0.68 may return a wrapper around the actual search result handler.
    id innerHandler = KWSendObject0(handler, @"handler");
    if (innerHandler) handler = innerHandler;

    NSMutableArray *items = [NSMutableArray array];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
                            NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];

    id allResults = KWSendObject0(handler, @"getAllResult");
    if (allResults) KWAppendFTSItems(allResults, items, visited);
    // getAllResult can be an empty container while arrSessionResultItem is populated.
    if (!items.count) {
        id sessionResults = KWSendObject0(handler, @"arrSessionResultItem");
        if (sessionResults) KWAppendFTSItems(sessionResults, items, visited);
    }

    NSUInteger primaryCandidates = items.count;
    NSArray *results = KWResolveFTSItems(items, keyword);
    NSUInteger directCandidates = 0;
    NSString *directFailure = nil;

    // Retry whenever candidates fail full-text verification, not only when parsing
    // the async result tree returns an empty candidate list.
    if (!results.count) {
        id directRoot = KWDirectFTSQuery(keyword);
        NSMutableArray *directItems = [NSMutableArray array];
        NSHashTable *directVisited = [NSHashTable hashTableWithOptions:
                                      NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
        if (directRoot) KWAppendFTSItems(directRoot, directItems, directVisited);
        directCandidates = directItems.count;
        if (directItems.count) results = KWResolveFTSItems(directItems, keyword);
        if (!directRoot) directFailure = KWGetSearchDiagnostic();
    }

    if (results.count) {
        KWSetSearchDiagnostic([NSString stringWithFormat:@"已找到 %lu 条原文精确匹配。", (unsigned long)results.count]);
    } else {
        NSString *detail = directFailure.length ? directFailure : @"没有得到可核验的匹配消息。";
        KWSetSearchDiagnostic([NSString stringWithFormat:
                               @"异步候选：%lu 条；备用索引候选：%lu 条；原文精确匹配：0 条。%@",
                               (unsigned long)primaryCandidates,
                               (unsigned long)directCandidates,
                               detail]);
    }

    NSLog(@"[WeChatKeywordCleaner] Search candidates primary=%lu direct=%lu exact=%lu",
          (unsigned long)primaryCandidates,
          (unsigned long)directCandidates,
          (unsigned long)results.count);
    return results;
}

@interface KWMessageSearchRequest : NSObject
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, copy) void (^completion)(NSArray *results);
@property (nonatomic, strong) id resultHandler;
@property (nonatomic, strong) id searchManager;
@property (nonatomic, assign) BOOL finished;
- (void)onDBSearchFinish;
- (void)startWithKeyword:(NSString *)keyword searchManager:(id)searchManager;
- (void)finishWithTimeout;
@end

static NSMutableSet *KWActiveSearchRequests;
static dispatch_once_t KWActiveSearchRequestsOnce;

static void KWKeepSearchRequest(KWMessageSearchRequest *request) {
    dispatch_once(&KWActiveSearchRequestsOnce, ^{
        KWActiveSearchRequests = [NSMutableSet set];
    });
    @synchronized (KWActiveSearchRequests) {
        [KWActiveSearchRequests addObject:request];
    }
}

static void KWReleaseSearchRequest(KWMessageSearchRequest *request) {
    if (!KWActiveSearchRequests) return;
    @synchronized (KWActiveSearchRequests) {
        [KWActiveSearchRequests removeObject:request];
    }
}

@implementation KWMessageSearchRequest

- (void)startWithKeyword:(NSString *)keyword searchManager:(id)searchManager {
    self.keyword = keyword;
    self.searchManager = searchManager;
    SEL startSelector = NSSelectorFromString(@"startSearch:limitUsername:searchFinishTarget:");
    SEL intelligentSelector = NSSelectorFromString(@"startSearch:limitUsername:searchType:searchFinishTarget:");
    if (!searchManager) {
        NSLog(@"[WeChatKeywordCleaner] Native FTS search manager unavailable");
        [self finishWithTimeout];
        return;
    }

    @try {
        if ([searchManager respondsToSelector:startSelector]) {
            self.resultHandler = KWSendObject3(searchManager, startSelector, keyword, nil, self);
        } else if ([searchManager respondsToSelector:intelligentSelector]) {
            self.resultHandler = KWSendObject4(searchManager, intelligentSelector, keyword, nil, 0, self);
        } else {
            NSLog(@"[WeChatKeywordCleaner] Native FTS startSearch API unavailable");
            [self finishWithTimeout];
            return;
        }
    } @catch (NSException *exception) {
        NSLog(@"[WeChatKeywordCleaner] Search start raised %@", exception.name);
        [self finishWithTimeout];
        return;
    }

    if (!self.resultHandler) {
        NSLog(@"[WeChatKeywordCleaner] FTS search returned no result handler");
        [self finishWithTimeout];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self finishWithTimeout];
    });
}

- (void)onDBSearchFinish {
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self) {
            if (self.finished) return;
            self.finished = YES;
        }

        NSArray *results = KWBuildSearchResults(self.resultHandler, self.keyword) ?: @[];
        NSLog(@"[WeChatKeywordCleaner] Exact literal search completed with %lu message results",
              (unsigned long)results.count);
        void (^completion)(NSArray *) = self.completion;
        self.completion = nil;
        if (completion) completion(results);
        KWReleaseSearchRequest(self);
    });
}

- (void)finishWithTimeout {
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self) {
            if (self.finished) return;
            self.finished = YES;
        }
        NSArray *fallbackResults = KWBuildSearchResults(nil, self.keyword) ?: @[];
        NSLog(@"[WeChatKeywordCleaner] Search callback timed out; direct FTS fallback returned %lu messages",
              (unsigned long)fallbackResults.count);
        void (^completion)(NSArray *) = self.completion;
        self.completion = nil;
        if (completion) completion(fallbackResults);
        KWReleaseSearchRequest(self);
    });
}

@end

@implementation WeChatBridge

+ (NSString *)lastSearchDiagnostic {
    return KWGetSearchDiagnostic();
}

+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *))completion {
    NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmedKeyword.length) {
        KWSetSearchDiagnostic(@"请输入搜索关键词。");
        if (completion) completion(@[]);
        return;
    }

    id searchManager = KWGetMessageSearchManager();
    if (!searchManager) {
        NSLog(@"[WeChatKeywordCleaner] Async FTS manager unavailable; trying direct FTS query");
        NSArray *results = KWBuildSearchResults(nil, trimmedKeyword) ?: @[];
        if (completion) completion(results);
        return;
    }

    KWMessageSearchRequest *request = [KWMessageSearchRequest new];
    request.completion = completion;
    KWKeepSearchRequest(request);
    [request startWithKeyword:trimmedKeyword searchManager:searchManager];
}

+ (void)deleteMessages:(NSArray *)messages completion:(void (^)(BOOL))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        id messageManager = KWGetService(@"CMessageMgr");
        SEL getMessageSelector = NSSelectorFromString(@"GetMsg:LocalID:");
        SEL deleteSelector = NSSelectorFromString(@"DelMsg:MsgList:DelAll:");
        if (!messageManager || ![messageManager respondsToSelector:getMessageSelector] ||
            ![messageManager respondsToSelector:deleteSelector] || !messages.count) {
            NSLog(@"[WeChatKeywordCleaner] Delete API unavailable or no messages selected");
            if (completion) completion(NO);
            return;
        }

        NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSString *batchTalker = nil;
        @try {
            // Re-fetch and re-check each selected message immediately before deletion.
            // Any row that cannot be proven to contain its exact keyword aborts the whole batch.
            for (id record in messages) {
                if (![record isKindOfClass:[NSDictionary class]]) {
                    if (completion) completion(NO);
                    return;
                }
                NSString *talker = record[@"__talker"] ?: record[@"talker"];
                NSString *keyword = record[@"__keyword"];
                NSNumber *localIDNumber = record[@"__localID"];
                uint32_t localID = localIDNumber ? localIDNumber.unsignedIntValue :
                                   [record[@"msgId"] respondsToSelector:@selector(unsignedIntValue)] ?
                                   [record[@"msgId"] unsignedIntValue] : 0;
                if (![talker isKindOfClass:[NSString class]] || !talker.length || !localID ||
                    ![keyword isKindOfClass:[NSString class]] || !keyword.length) {
                    if (completion) completion(NO);
                    return;
                }
                if (batchTalker && ![batchTalker isEqualToString:talker]) {
                    NSLog(@"[WeChatKeywordCleaner] Refusing a mixed-chat deletion batch");
                    if (completion) completion(NO);
                    return;
                }
                batchTalker = talker;

                NSString *uniqueKey = [NSString stringWithFormat:@"%@:%u", talker, localID];
                if ([seen containsObject:uniqueKey]) continue;
                [seen addObject:uniqueKey];

                id wrap = KWSendMessageForLocalID(messageManager, getMessageSelector, talker, localID);
                Class wrapClass = objc_getClass("CMessageWrap");
                if (!wrap || (wrapClass && ![wrap isKindOfClass:wrapClass]) ||
                    KWSendUInt0(wrap, @"m_uiMesLocalID") != localID) {
                    NSLog(@"[WeChatKeywordCleaner] Could not validate current message %@", uniqueKey);
                    if (completion) completion(NO);
                    return;
                }

                NSString *content = KWSendObject0(wrap, @"m_nsContent");
                if (![content isKindOfClass:[NSString class]] ||
                    [content rangeOfString:keyword
                                   options:(NSCaseInsensitiveSearch | NSLiteralSearch)].location == NSNotFound) {
                    NSLog(@"[WeChatKeywordCleaner] Message %@ no longer contains the selected literal keyword", uniqueKey);
                    if (completion) completion(NO);
                    return;
                }

                NSMutableDictionary *group = groups[talker];
                if (!group) {
                    group = [@{ @"wraps": [NSMutableArray array], @"localIDs": [NSMutableArray array] } mutableCopy];
                    groups[talker] = group;
                }
                [group[@"wraps"] addObject:wrap];
                [group[@"localIDs"] addObject:@(localID)];
            }

            if (!seen.count) {
                if (completion) completion(NO);
                return;
            }

            for (NSString *talker in groups) {
                KWSendDeleteBatch(messageManager, deleteSelector, talker, groups[talker][@"wraps"]);
            }
        } @catch (NSException *exception) {
            NSLog(@"[WeChatKeywordCleaner] Batch delete raised %@", exception.name);
            if (completion) completion(NO);
            return;
        }

        // DelMsg is void; verify the local database after WeChat processes the deletion notifications.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SEL getMessagesSelector = NSSelectorFromString(@"GetMsg:LocalIDArray:");
            BOOL verified = [messageManager respondsToSelector:getMessagesSelector];
            BOOL allRemoved = YES;
            if (verified) {
                for (NSString *talker in groups) {
                    id remaining = KWSendObject2(messageManager, @"GetMsg:LocalIDArray:",
                                                 talker, groups[talker][@"localIDs"]);
                    if (![remaining isKindOfClass:[NSArray class]] || [(NSArray *)remaining count] > 0) {
                        allRemoved = NO;
                        break;
                    }
                }
            }
            if (!verified) {
                NSLog(@"[WeChatKeywordCleaner] Delete calls were sent; this WeChat build has no batch read-back API");
            }
            if (completion) completion(verified ? allRemoved : YES);
        });
    });
}

@end

