// KeywordCleanerUI.m —— 关键字清理界面 + 悬浮按钮
// 搜索结果先按消息原文精确筛选；删除必须逐条手动勾选。

#import "WeChatKeywordCleaner.h"

@interface KeywordCleanerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITextField *keywordField;
@property (nonatomic, strong) UIButton *searchBtn;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, strong) UIButton *scopeBtn;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *allResults;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *results;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedKeys;
@property (nonatomic, copy) NSString *selectedTalker;

@end

@implementation KeywordCleanerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"关键字清理";
    self.allResults = [NSMutableArray array];
    self.results = [NSMutableArray array];
    self.selectedKeys = [NSMutableSet set];

    CGFloat w = self.view.bounds.size.width;

    self.keywordField = [[UITextField alloc] initWithFrame:CGRectMake(16, 90, w - 32, 40)];
    self.keywordField.borderStyle = UITextBorderStyleRoundedRect;
    self.keywordField.placeholder = @"输入要精确匹配的文字";
    self.keywordField.delegate = self;
    [self.view addSubview:self.keywordField];

    self.searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.searchBtn.frame = CGRectMake(16, 140, (w - 48) / 2, 40);
    [self.searchBtn setTitle:@"搜索" forState:UIControlStateNormal];
    [self.searchBtn addTarget:self
                       action:@selector(doSearch)
             forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.searchBtn];

    self.deleteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.deleteBtn.frame = CGRectMake(32 + (w - 48) / 2,
                                      140,
                                      (w - 48) / 2,
                                      40);
    [self.deleteBtn setTitle:@"删除已选（0）" forState:UIControlStateNormal];
    [self.deleteBtn addTarget:self
                       action:@selector(doDelete)
             forControlEvents:UIControlEventTouchUpInside];
    self.deleteBtn.enabled = NO;
    [self.view addSubview:self.deleteBtn];

    self.scopeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scopeBtn.frame = CGRectMake(16, 185, w - 32, 34);
    [self.scopeBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [self.scopeBtn setTitle:@"聊天范围：全部聊天（搜索后可筛选）" forState:UIControlStateNormal];
    [self.scopeBtn addTarget:self
                      action:@selector(chooseScope)
            forControlEvents:UIControlEventTouchUpInside];
    self.scopeBtn.enabled = NO;
    [self.view addSubview:self.scopeBtn];

    self.summaryLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 220, w - 32, 42)];
    self.summaryLabel.font = [UIFont systemFontOfSize:12];
    self.summaryLabel.textColor = [UIColor secondaryLabelColor];
    self.summaryLabel.numberOfLines = 2;
    self.summaryLabel.text = @"搜索结果按消息原文精确匹配。点选消息后才会进入删除清单；选中后会删除整条消息。";
    [self.view addSubview:self.summaryLabel];

    self.tableView = [[UITableView alloc]
                      initWithFrame:CGRectMake(0,
                                               264,
                                               w,
                                               MAX(0, self.view.bounds.size.height - 264))
                      style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    [self.view addSubview:self.tableView];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(dismissSelf)];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)keyForRecord:(NSDictionary *)record {
    NSString *talker = record[@"__talker"] ?: record[@"talker"];
    NSString *messageID = record[@"msgId"];
    if (![talker isKindOfClass:[NSString class]] || !talker.length ||
        ![messageID isKindOfClass:[NSString class]] || !messageID.length) return nil;
    return [NSString stringWithFormat:@"%@:%@", talker, messageID];
}

- (NSUInteger)selectedCount {
    NSUInteger count = 0;
    for (NSDictionary *record in self.results) {
        NSString *key = [self keyForRecord:record];
        if (key && [self.selectedKeys containsObject:key]) count++;
    }
    return count;
}

- (NSArray<NSDictionary *> *)selectedRecords {
    NSMutableArray *selected = [NSMutableArray array];
    for (NSDictionary *record in self.results) {
        NSString *key = [self keyForRecord:record];
        if (key && [self.selectedKeys containsObject:key]) [selected addObject:record];
    }
    return selected;
}

- (void)updateDeleteButton {
    NSUInteger count = [self selectedCount];
    [self.deleteBtn setTitle:[NSString stringWithFormat:@"删除已选（%lu）", (unsigned long)count]
                     forState:UIControlStateNormal];
    self.deleteBtn.enabled = count > 0;
}

- (void)updateSummary {
    NSMutableSet *talkers = [NSMutableSet set];
    for (NSDictionary *record in self.results) {
        NSString *talker = record[@"__talker"] ?: record[@"talker"];
        if (talker.length) [talkers addObject:talker];
    }

    NSString *keyword = [self.keywordField.text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    self.summaryLabel.text = [NSString stringWithFormat:
                              @"原文精确包含“%@”：%lu 条消息，来自 %lu 个聊天。只删除你逐条勾选的消息；勾选后整条删除。",
                              keyword,
                              (unsigned long)self.results.count,
                              (unsigned long)talkers.count];
}

- (void)updateScopeButton {
    if (!self.selectedTalker.length) {
        [self.scopeBtn setTitle:@"聊天范围：全部聊天（搜索后可筛选）" forState:UIControlStateNormal];
        return;
    }

    NSString *displayName = self.selectedTalker;
    for (NSDictionary *record in self.allResults) {
        if ([record[@"__talker"] isEqualToString:self.selectedTalker]) {
            displayName = record[@"displayName"] ?: self.selectedTalker;
            break;
        }
    }
    [self.scopeBtn setTitle:[NSString stringWithFormat:@"聊天范围：%@", displayName]
                   forState:UIControlStateNormal];
}

- (void)applyScopeFilter {
    [self.results removeAllObjects];
    for (NSDictionary *record in self.allResults) {
        NSString *talker = record[@"__talker"] ?: record[@"talker"];
        if (!self.selectedTalker.length || [talker isEqualToString:self.selectedTalker]) {
            [self.results addObject:record];
        }
    }
    [self updateScopeButton];
    [self updateSummary];
    [self updateDeleteButton];
    [self.tableView reloadData];
}

- (void)doSearch {
    [self.keywordField resignFirstResponder];

    NSString *keyword = [self.keywordField.text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!keyword.length) return;

    [self.allResults removeAllObjects];
    [self.results removeAllObjects];
    [self.selectedKeys removeAllObjects];
    self.selectedTalker = nil;
    [self.tableView reloadData];
    self.searchBtn.enabled = NO;
    self.scopeBtn.enabled = NO;
    [self updateDeleteButton];

    [WeChatBridge searchKeyword:keyword
                      completion:^(NSArray *res) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.searchBtn.enabled = YES;
            self.allResults = [res mutableCopy] ?: [NSMutableArray array];
            self.scopeBtn.enabled = self.allResults.count > 0;
            [self applyScopeFilter];
        });
    }];
}

- (NSDictionary<NSString *, NSString *> *)availableTalkers {
    NSMutableDictionary *talkers = [NSMutableDictionary dictionary];
    for (NSDictionary *record in self.allResults) {
        NSString *talker = record[@"__talker"] ?: record[@"talker"];
        if (!talker.length) continue;
        NSString *displayName = record[@"displayName"] ?: talker;
        talkers[talker] = displayName;
    }
    return talkers;
}

- (void)chooseScope {
    NSDictionary<NSString *, NSString *> *talkers = [self availableTalkers];
    if (!talkers.count) return;

    UIAlertController *picker =
        [UIAlertController alertControllerWithTitle:@"筛选聊天范围"
                                            message:@"筛选只影响当前列表；删除仍需逐条勾选。"
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [picker addAction:[UIAlertAction actionWithTitle:@"全部聊天"
                                               style:UIAlertActionStyleDefault
                                             handler:^(__unused UIAlertAction *action) {
        weakSelf.selectedTalker = nil;
        [weakSelf.selectedKeys removeAllObjects];
        [weakSelf applyScopeFilter];
    }]];

    NSArray<NSString *> *sortedTalkers = [talkers.allKeys sortedArrayUsingComparator:
                                          ^NSComparisonResult(NSString *left, NSString *right) {
        return [talkers[left] localizedCaseInsensitiveCompare:talkers[right]];
    }];
    for (NSString *talker in sortedTalkers) {
        NSString *displayName = talkers[talker] ?: talker;
        NSString *title = [displayName isEqualToString:talker]
                          ? displayName
                          : [NSString stringWithFormat:@"%@ · %@", displayName, talker];
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *action) {
            weakSelf.selectedTalker = talker;
            [weakSelf.selectedKeys removeAllObjects];
            [weakSelf applyScopeFilter];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"取消"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    UIPopoverPresentationController *popover = picker.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.scopeBtn;
        popover.sourceRect = self.scopeBtn.bounds;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)doDelete {
    NSArray<NSDictionary *> *selected = [self selectedRecords];
    if (!selected.count) return;

    NSMutableDictionary<NSString *, NSString *> *chats = [NSMutableDictionary dictionary];
    for (NSDictionary *record in selected) {
        NSString *talker = record[@"__talker"] ?: record[@"talker"];
        if (talker.length) chats[talker] = record[@"displayName"] ?: talker;
    }
    if (chats.count != 1) {
        UIAlertController *scopeRequired =
            [UIAlertController alertControllerWithTitle:@"请一次处理一个聊天"
                                                message:@"当前勾选项跨越了多个聊天。请先用“聊天范围”筛选到一个聊天，再逐条勾选要删除的消息。"
                                         preferredStyle:UIAlertControllerStyleAlert];
        [scopeRequired addAction:[UIAlertAction actionWithTitle:@"知道了"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil]];
        [self presentViewController:scopeRequired animated:YES completion:nil];
        return;
    }
    NSArray<NSString *> *sortedTalkers = [chats.allKeys sortedArrayUsingComparator:
                                          ^NSComparisonResult(NSString *left, NSString *right) {
        return [chats[left] localizedCaseInsensitiveCompare:chats[right]];
    }];
    NSMutableArray<NSString *> *chatLines = [NSMutableArray array];
    NSUInteger shown = MIN((NSUInteger)1, sortedTalkers.count);
    for (NSUInteger index = 0; index < shown; index++) {
        NSString *talker = sortedTalkers[index];
        NSString *displayName = chats[talker] ?: talker;
        [chatLines addObject:[displayName isEqualToString:talker]
         ? displayName
         : [NSString stringWithFormat:@"%@（%@）", displayName, talker]];
    }
    NSString *message = [NSString stringWithFormat:
                         @"将整条删除你勾选的 %lu 条消息，聊天对象：\n%@\n\n删除后无法在此插件中撤销。",
                         (unsigned long)selected.count,
                         [chatLines componentsJoinedByString:@"\n"]];
    UIAlertController *confirm =
        [UIAlertController alertControllerWithTitle:@"确认删除已勾选消息？"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"确认删除"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(__unused UIAlertAction *action) {
        self.searchBtn.enabled = NO;
        self.scopeBtn.enabled = NO;
        self.deleteBtn.enabled = NO;
        [WeChatBridge deleteMessages:selected
                          completion:^(BOOL ok) {
            if (ok) {
                NSMutableSet *deletedKeys = [NSMutableSet set];
                for (NSDictionary *record in selected) {
                    NSString *key = [self keyForRecord:record];
                    if (key) [deletedKeys addObject:key];
                }
                NSMutableArray *remaining = [NSMutableArray array];
                for (NSDictionary *record in self.allResults) {
                    NSString *key = [self keyForRecord:record];
                    if (key && ![deletedKeys containsObject:key]) [remaining addObject:record];
                }
                self.allResults = remaining;
                [self.selectedKeys removeAllObjects];
                self.searchBtn.enabled = YES;
                self.scopeBtn.enabled = self.allResults.count > 0;
                [self applyScopeFilter];
            } else {
                self.searchBtn.enabled = YES;
                self.scopeBtn.enabled = self.allResults.count > 0;
                UIAlertController *failed =
                    [UIAlertController alertControllerWithTitle:@"删除未能确认完成"
                                                        message:@"请重新搜索并核对结果。没有通过原文关键词校验的消息不会被提交删除。"
                                                 preferredStyle:UIAlertControllerStyleAlert];
                [failed addAction:[UIAlertAction actionWithTitle:@"知道了"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil]];
                [self presentViewController:failed animated:YES completion:nil];
                [self updateDeleteButton];
            }
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"message"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                     reuseIdentifier:@"message"];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 2;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *record = self.results[indexPath.row];
    cell.textLabel.text = record[@"content"] ?: @"(无可显示文本)";
    NSString *displayName = record[@"displayName"] ?: record[@"talker"] ?: @"";
    NSString *talker = record[@"talker"] ?: @"";
    cell.detailTextLabel.text = [displayName isEqualToString:talker]
                                ? displayName
                                : [NSString stringWithFormat:@"%@ · %@", displayName, talker];
    NSString *key = [self keyForRecord:record];
    cell.accessoryType = (key && [self.selectedKeys containsObject:key])
                         ? UITableViewCellAccessoryCheckmark
                         : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *record = self.results[indexPath.row];
    NSString *key = [self keyForRecord:record];
    if (!key) return;
    if ([self.selectedKeys containsObject:key]) {
        [self.selectedKeys removeObject:key];
    } else {
        [self.selectedKeys addObject:key];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateDeleteButton];
}

@end

#pragma mark - Window helper

// iOS 13+ 不再使用 UIApplication.keyWindow。
// 通过当前前台 UIWindowScene 找到微信正在使用的窗口。
static UIWindow *KWGetKeyWindow(void) {
    UIApplication *application = [UIApplication sharedApplication];
    for (UIScene *scene in application.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) return window;
        }
        if (windowScene.windows.count > 0) return windowScene.windows.firstObject;
    }
    return nil;
}

#pragma mark - Floating button

void ShowKeywordCleanerFloatingButton(void) {
    UIWindow *window = KWGetKeyWindow();
    if (!window) return;

    static UIButton *button;
    if (button) return;

    button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(window.bounds.size.width - 60, 100, 44, 44);
    button.backgroundColor = [UIColor systemBlueColor];
    [button setTitle:@"清" forState:UIControlStateNormal];
    button.layer.cornerRadius = 22;
    [button addTarget:[KeywordCleanerViewController class]
               action:@selector(presentCleaner)
     forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
}

#pragma mark - Present Cleaner

@implementation KeywordCleanerViewController (Present)

+ (void)presentCleaner {
    KeywordCleanerViewController *viewController = [[KeywordCleanerViewController alloc] init];
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:viewController];
    UIWindow *window = KWGetKeyWindow();
    if (!window) return;
    [window.rootViewController presentViewController:navigationController
                                            animated:YES
                                          completion:nil];
}

@end

