// KeywordCleanerUI.m —— 关键字清理界面 + 悬浮按钮
// 这部分不依赖微信内部 API，可正常编译运行；只有调用 WeChatBridge 的数据是占位的

#import "WeChatKeywordCleaner.h"

@interface KeywordCleanerViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITextField *keywordField;
@property (nonatomic, strong) UIButton *searchBtn;
@property (nonatomic, strong) UIButton *deleteBtn;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *results;

@end

@implementation KeywordCleanerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"关键字清理";
    self.results = [NSMutableArray array];

    CGFloat w = self.view.bounds.size.width;

    self.keywordField = [[UITextField alloc] initWithFrame:CGRectMake(16, 90, w - 32, 40)];
    self.keywordField.borderStyle = UITextBorderStyleRoundedRect;
    self.keywordField.placeholder = @"输入关键字，如 秒批、盲批";
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
    [self.deleteBtn setTitle:@"删除全部结果"
                    forState:UIControlStateNormal];
    [self.deleteBtn addTarget:self
                       action:@selector(doDelete)
             forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.deleteBtn];

    self.tableView = [[UITableView alloc]
                      initWithFrame:CGRectMake(0,
                                               190,
                                               w,
                                               self.view.bounds.size.height - 190)
                      style:UITableViewStylePlain];

    self.tableView.dataSource = self;
    self.tableView.delegate = self;

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

- (void)doSearch {
    [self.keywordField resignFirstResponder];

    NSString *kw = self.keywordField.text;
    if (!kw.length) return;

    [WeChatBridge searchKeyword:kw
                      completion:^(NSArray *res) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.results = [res mutableCopy];
            [self.tableView reloadData];
        });
    }];
}

- (void)doDelete {
    if (!self.results.count) return;

    [WeChatBridge deleteMessages:self.results
                      completion:^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                [self.results removeAllObjects];
                [self.tableView reloadData];
            }
        });
    }];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tv
 numberOfRowsInSection:(NSInteger)s {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {

    UITableViewCell *c =
        [tv dequeueReusableCellWithIdentifier:@"c"];

    if (!c) {
        c = [[UITableViewCell alloc]
             initWithStyle:UITableViewCellStyleSubtitle
             reuseIdentifier:@"c"];
    }

    NSDictionary *d = self.results[ip.row];

    c.textLabel.text = d[@"content"] ?: @"(空)";

    c.detailTextLabel.text =
        [NSString stringWithFormat:@"%@ | %@",
         d[@"talker"] ?: @"",
         d[@"msgId"] ?: @""];

    return c;
}

@end


#pragma mark - Window helper

// iOS 13+ 不再使用 UIApplication.keyWindow。
// 通过当前前台 UIWindowScene 找到微信正在使用的窗口。
static UIWindow *KWGetKeyWindow(void) {

    UIApplication *application = [UIApplication sharedApplication];

    for (UIScene *scene in application.connectedScenes) {

        if (scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        // 优先寻找真正的 key window
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }

        // 如果没有 key window，则退回当前场景的第一个窗口
        if (windowScene.windows.count > 0) {
            return windowScene.windows.firstObject;
        }
    }

    return nil;
}


#pragma mark - 悬浮按钮

// 悬浮按钮 + 弹出界面
void ShowKeywordCleanerFloatingButton(void) {

    UIWindow *win = KWGetKeyWindow();

    if (!win) return;

    static UIButton *btn;

    if (btn) return;

    btn = [UIButton buttonWithType:UIButtonTypeCustom];

    btn.frame = CGRectMake(
        win.bounds.size.width - 60,
        100,
        44,
        44
    );

    btn.backgroundColor = [UIColor systemBlueColor];

    [btn setTitle:@"清"
          forState:UIControlStateNormal];

    btn.layer.cornerRadius = 22;

    [btn addTarget:[KeywordCleanerViewController class]
            action:@selector(presentCleaner)
  forControlEvents:UIControlEventTouchUpInside];

    [win addSubview:btn];
}


#pragma mark - Present Cleaner

@implementation KeywordCleanerViewController (Present)

+ (void)presentCleaner {

    KeywordCleanerViewController *vc =
        [[KeywordCleanerViewController alloc] init];

    UINavigationController *nav =
        [[UINavigationController alloc]
         initWithRootViewController:vc];

    UIWindow *win = KWGetKeyWindow();

    if (!win) return;

    [win.rootViewController
     presentViewController:nav
     animated:YES
     completion:nil];
}

@end
