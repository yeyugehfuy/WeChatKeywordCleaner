// Tweak.xm —— 等微信窗口就绪后显示悬浮按钮
#import "WeChatKeywordCleaner.h"

static NSUInteger KWButtonAttemptGeneration = 0;

static void KWAttemptToShowButton(NSUInteger generation, NSUInteger attempt) {
    if (generation != KWButtonAttemptGeneration) return;

    ShowKeywordCleanerFloatingButton();

    // The injected library may load before WeChat creates its active UIWindow.
    // Retry for up to one minute; the UI helper guards against duplicate buttons.
    if (attempt >= 60) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        KWAttemptToShowButton(generation, attempt + 1);
    });
}

static void KWStartButtonAttempts(void) {
    KWButtonAttemptGeneration++;
    KWAttemptToShowButton(KWButtonAttemptGeneration, 0);
}

%ctor {
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         addObserverForName:UIApplicationDidBecomeActiveNotification
         object:nil
         queue:[NSOperationQueue mainQueue]
         usingBlock:^(__unused NSNotification *notification) {
            KWStartButtonAttempts();
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            KWStartButtonAttempts();
        });
    });
}

