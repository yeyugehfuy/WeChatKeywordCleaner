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
    Class contextClass = objc_getClass("MMContext");
    Class serviceClass = objc_getClass(className.UTF8String);
    SEL currentContextSelector = NSSelectorFromString(@"currentContext");
    if (!contextClass || !serviceClass || !class_getClassMethod(contextClass, currentContextSelector)) {
        return nil;
    }

    id context = ((id (*)(id, SEL))objc_msgSend)((id)contextClass, currentContextSelector);
    id serviceCenter = KWSendObject0(context, @"serviceCenter");
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

static NSArray *KWBuildSearchResults(id handler) {
    id resultRoot = KWSendObject0(handler, @"getAllResult");
    if (!resultRoot) resultRoot = KWSendObject0(handler, @"arrSessionResultItem");

    NSMutableArray *items = [NSMutableArray array];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
                            NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    KWAppendFTSItems(resultRoot, items, visited);

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:items.count];
    NSMutableSet *seen = [NSMutableSet set];
    for (id item in items) {
        NSString *talker = KWSendObject0(item, @"userName");
        id wrap = KWSendObject0(item, @"msgWrap");
        uint32_t localID = KWSendUInt0(item, @"localId");
        if (!localID && wrap) localID = KWSendUInt0(wrap, @"m_uiMesLocalID");
        if (!talker.length || localID == 0) continue;

        NSString *uniqueKey = [NSString stringWithFormat:@"%@:%u", talker, localID];
        if ([seen containsObject:uniqueKey]) continue;
        [seen addObject:uniqueKey];

        NSString *content = KWSendObject0(wrap, @"m_nsContent");
        if (!content.length) content = KWSendObject0(item, @"ftsContent");
        if (![content isKindOfClass:[NSString class]]) content = [content description] ?: @"";

        [results addObject:@{
            @"msgId": [NSString stringWithFormat:@"%u", localID],
            @"talker": talker,
            @"content": content,
            @"__talker": talker,
            @"__localID": @(localID),
            @"__msgWrap": wrap ?: [NSNull null]
        }];
    }
    return results;
}

@interface KWMessageSearchRequest : NSObject
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

        NSArray *results = KWBuildSearchResults(self.resultHandler) ?: @[];
        NSLog(@"[WeChatKeywordCleaner] Search completed with %lu message results",
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
        NSLog(@"[WeChatKeywordCleaner] Unable to get WeChat FTS search service");
        if (completion) completion(@[]);
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
        @try {
            // Resolve and validate every wrap before deleting anything, so a malformed row cannot cause a partial batch.
            for (id record in messages) {
                if (![record isKindOfClass:[NSDictionary class]]) {
                    if (completion) completion(NO);
                    return;
                }
                NSString *talker = record[@"__talker"] ?: record[@"talker"];
                NSNumber *localIDNumber = record[@"__localID"];
                uint32_t localID = localIDNumber ? localIDNumber.unsignedIntValue :
                                   [record[@"msgId"] respondsToSelector:@selector(unsignedIntValue)] ?
                                   [record[@"msgId"] unsignedIntValue] : 0;
                if (![talker isKindOfClass:[NSString class]] || !talker.length || !localID) {
                    if (completion) completion(NO);
                    return;
                }

                NSString *uniqueKey = [NSString stringWithFormat:@"%@:%u", talker, localID];
                if ([seen containsObject:uniqueKey]) continue;
                [seen addObject:uniqueKey];

                id wrap = record[@"__msgWrap"];
                if (wrap == [NSNull null]) wrap = nil;
                if (!wrap) wrap = KWSendMessageForLocalID(messageManager, getMessageSelector, talker, localID);
                if (!wrap) {
                    NSLog(@"[WeChatKeywordCleaner] Could not resolve message %@", uniqueKey);
                    if (completion) completion(NO);
                    return;
                }

                Class wrapClass = objc_getClass("CMessageWrap");
                if (wrapClass && ![wrap isKindOfClass:wrapClass]) {
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
                    if ([remaining isKindOfClass:[NSArray class]] && [(NSArray *)remaining count] > 0) {
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

