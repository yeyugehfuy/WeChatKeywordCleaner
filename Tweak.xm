// Add a native entry to WeChat's Settings navigation bar; no floating overlay.
#import "WeChatKeywordCleaner.h"
#import <objc/runtime.h>

%hook NewSettingViewController

- (void)viewDidLoad {
    %orig;

    UINavigationItem *navigationItem = self.navigationItem;
    if (!navigationItem) return;

    NSMutableArray<UIBarButtonItem *> *items =
        [navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    for (UIBarButtonItem *item in items) {
        if ([item.accessibilityIdentifier isEqualToString:@"WeChatKeywordCleaner.SettingsEntry"]) {
            return;
        }
    }

    Class cleanerClass = objc_getClass("KeywordCleanerViewController");
    if (!cleanerClass) {
        NSLog(@"[WeChatKeywordCleaner] Cleaner UI class is not loaded");
        return;
    }

    UIBarButtonItem *entry =
        [[UIBarButtonItem alloc] initWithTitle:@"清理"
                                         style:UIBarButtonItemStylePlain
                                        target:cleanerClass
                                        action:NSSelectorFromString(@"presentCleaner")];
    entry.accessibilityIdentifier = @"WeChatKeywordCleaner.SettingsEntry";
    [items addObject:entry];
    navigationItem.rightBarButtonItems = items;
}

%end

%ctor {
    %init;
}
