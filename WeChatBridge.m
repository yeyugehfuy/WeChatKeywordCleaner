// WeChatBridge.m
// Runtime bridge for the WeChat 8.0.68 message search and deletion APIs.
#import "WeChatKeywordCleaner.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdint.h>

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

static id KWGetService(NSString *className) {
    Class serviceClass = objc_getClass(className.UTF8String);
    if (!serviceClass) return nil;

    id serviceCenter = nil;
    Class contextClass = objc_getClass("MMContext");
    SEL currentContextSelector = NSSelectorFromString(@"currentContext");
    if (contextClass && class_getClassMethod(contextClass, currentContextSelector)) {
        id context = ((id (*)(id, SEL))objc_msgSend)((id)contextClass, currentContextSelector);
        serviceCenter = KWSendObject0(context, @"serviceCenter");
    }

    // Some WeChat builds expose the service center as a singleton instead.
    if (!serviceCenter) {
        Class serviceCenterClass = objc_getClass("MMServiceCenter");
        serviceCenter = KWSendObject0((id)serviceCenterClass, @"defaultCenter");
    }
    if (!serviceCenter) {
        NSLog(@"[WeChatKeywordCleaner] Could not resolve MMServiceCenter for %@", className);
        return nil;
    }
    return KWSendObject1(serviceCenter, @"getService:", (id)serviceClass);
}

static id KWGetMessageSearchManager(void) {
    id messageSearchService = KWGetService(@"FTSMessageMgr");
    id searchManager = KWSendObject0(messageSearchService, @"searchMgr");
    if (searchManager) return searchManager;

    // Some WeChat startup paths create the FTS search manager lazily.
    id database = KWSendObject0(messageSearchService, @"ftsMessageDB");
    Class searchManagerClass = objc_getClass("FTSMsgSearchMgr");
    if (!messageSearchService || !database || !searchManagerClass) return nil;

    id allocated = KWSendObject0((id)searchManagerClass, @"alloc");
    searchManager = KWSendObject1(allocated, @"initWithDB:", database);
    if (searchManager) {
        KWSendObject1(messageSearchService, @"setSearchMgr:", searchManager);
    }
    return searchManager;
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
    id messageSearchService = KWGetService(@"FTSMessageMgr");
    id database = KWSendObject0(messageSearchService, @"ftsMessageDB");
    SEL querySelector = NSSelectorFromString(@"queryText:limitUsrname:cancelBlock:");
    if (!database || ![database respondsToSelector:querySelector]) {
        NSLog(@"[WeChatKeywordCleaner] Direct FTS database query API unavailable");
        return nil;
    }
    @try {
        return KWSendObject3(database, querySelector, keyword, nil, nil);
    } @catch (NSException *exception) {
        NSLog(@"[WeChatKeywordCleaner] Direct FTS query raised %@", exception.name);
        return nil;
    }
}

static NSArray *KWBuildSearchResults(id handler, NSString *keyword) {
    // WeChat 8.0.68 may return a wrapper around the actual search result handler.
    id innerHandler = KWSendObject0(handler, @"handler");
    if (innerHandler) handler = innerHandler;

    id resultRoot = KWSendObject0(handler, @"getAllResult");
    if (!resultRoot) resultRoot = KWSendObject0(handler, @"arrSessionResultItem");

    NSMutableArray *items = [NSMutableArray array];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
                            NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    KWAppendFTSItems(resultRoot, items, visited);
    if (!items.count) {
        // Fall back to the exact synchronous FTSMessageDB API present in 8.0.68.
        id directRoot = KWDirectFTSQuery(keyword);
        if (directRoot) KWAppendFTSItems(directRoot, items, visited);
        NSLog(@"[WeChatKeywordCleaner] Direct FTS fallback found %lu candidate items",
              (unsigned long)items.count);
    }

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

        // Require the full message wrapper. FTS snippets alone are not enough
        // evidence for showing a message as eligible for destructive action.
        id wrap = KWSendObject0(item, @"msgWrap");
        if (!wrap && messageManager && [messageManager respondsToSelector:getMessageSelector]) {
            wrap = KWSendMessageForLocalID(messageManager, getMessageSelector, talker, localID);
        }
        Class wrapClass = objc_getClass("CMessageWrap");
        if (!wrap || (wrapClass && ![wrap isKindOfClass:wrapClass]) ||
            KWSendUInt0(wrap, @"m_uiMesLocalID") != localID) continue;
        NSString *content = KWSendObject0(wrap, @"m_nsContent");
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
            @"__msgWrap": wrap
        }];
    }
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
    if (!searchManager || ![searchManager respondsToSelector:startSelector]) {
        NSLog(@"[WeChatKeywordCleaner] FTSMsgSearchMgr API unavailable");
        [self finishWithTimeout];
        return;
    }

    @try {
        self.resultHandler = KWSendObject3(searchManager, startSelector, keyword, nil, self);
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
        NSLog(@"[WeChatKeywordCleaner] Search did not complete; returning no results");
        void (^completion)(NSArray *) = self.completion;
        self.completion = nil;
        if (completion) completion(@[]);
        KWReleaseSearchRequest(self);
    });
}

@end

@implementation WeChatBridge

+ (void)searchKeyword:(NSString *)keyword completion:(void (^)(NSArray *))completion {
    NSString *trimmedKeyword = [keyword stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmedKeyword.length) {
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

