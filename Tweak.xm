// Tweak.xm —— 仅负责在微信进程里弹出悬浮按钮
// 不 hook 任何微信内部类，因此即使 8.0.68 类名叫了名也能稳定加载、不会崩
#import "WeChatKeywordCleaner.h"

%ctor {
    %init;
    // 等微信界面起来后再加悬浮按钮
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        ShowKeywordCleanerFloatingButton();
    });
}
