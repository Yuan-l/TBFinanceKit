//
//  TBFinanceDetailViewController.m
//  TBFinanceKit
//
//  结构（ScrollView 内纵向堆叠）：
//  [价格头部：现价/涨跌/涨跌幅/行情时间]  ← 3s 定时轮询 ulist 刷新
//  [关键行情宫格：今开/最高/最低/昨收/成交量/成交额/振幅/换手/市值/PE]
//  [K 线区：日/周/月切换 + Core Graphics 蜡烛图（长按十字光标联动 OHLC）]
//  [公司/基金信息区]
//

#import "TBFinanceDetailViewController.h"
#import "TBFinanceService.h"
#import "TBKLineDrawView.h"
#import "TBFinanceColor.h"

static NSTimeInterval const kPollInterval = 3.0;

@interface TBFinanceDetailViewController ()
@property (nonatomic, strong) TBFinanceTarget *target;
@property (nonatomic, strong) UIScrollView *scrollView;
// 头部
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *changeLabel;
@property (nonatomic, strong) UILabel *timeLabel;
// 宫格
@property (nonatomic, strong) UIStackView *metricsStack;
// K 线
@property (nonatomic, strong) TBKLineDrawView *klineView;
@property (nonatomic, strong) UILabel *ohlcLabel;
@property (nonatomic, strong) NSArray<UIButton *> *periodButtons;
@property (nonatomic, assign) TBFinanceKLinePeriod currentPeriod;
// 信息
@property (nonatomic, strong) UILabel *infoLabel;
// 轮询
@property (nonatomic, strong) NSTimer *pollTimer;
@end

@implementation TBFinanceTarget
@end

@implementation TBFinanceDetailViewController

- (instancetype)initWithTarget:(TBFinanceTarget *)target {
    if (self = [super init]) {
        _target = target;
        self.title = target.name;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    [self buildUI];
    [self startPolling];
    [self loadKLine];
    [self loadExtraInfo];
}

- (void)dealloc {
    [_pollTimer invalidate];
}

#pragma mark - UI

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 16;

    // 头部价格
    self.priceLabel = [self makeLabel:44 bold:YES color:[UIColor blackColor]];
    self.priceLabel.frame = CGRectMake(16, y, w - 32, 52);
    self.priceLabel.text = @"--";
    [self.scrollView addSubview:self.priceLabel];
    y += 54;

    self.changeLabel = [self makeLabel:15 bold:NO color:[UIColor grayColor]];
    self.changeLabel.frame = CGRectMake(16, y, w - 32, 22);
    [self.scrollView addSubview:self.changeLabel];
    y += 26;

    self.timeLabel = [self makeLabel:11 bold:NO color:[UIColor lightGrayColor]];
    self.timeLabel.frame = CGRectMake(16, y, w - 32, 16);
    [self.scrollView addSubview:self.timeLabel];
    y += 28;

    // 宫格（4 列 × 3 行）
    self.metricsStack = [[UIStackView alloc] init];
    self.metricsStack.axis = UILayoutConstraintAxisVertical;
    self.metricsStack.spacing = 10;
    self.metricsStack.frame = CGRectMake(16, y, w - 32, 130);
    [self.scrollView addSubview:self.metricsStack];
    y += 146;

    // K 线周期切换
    NSArray *titles = @[@"日K", @"周K", @"月K"];
    UIStackView *ps = [[UIStackView alloc] initWithFrame:CGRectMake(16, y, 180, 30)];
    ps.axis = UILayoutConstraintAxisHorizontal;
    ps.distribution = UIStackViewDistributionFillEqually;
    ps.spacing = 8;
    NSMutableArray *btns = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        b.layer.cornerRadius = 6;
        b.layer.borderWidth = 1;
        b.tag = i;
        [b addTarget:self action:@selector(switchPeriod:) forControlEvents:UIControlEventTouchUpInside];
        [ps addArrangedSubview:b];
        [btns addObject:b];
    }
    self.periodButtons = btns;
    [self.scrollView addSubview:ps];
    y += 42;

    // OHLC 联动 label
    self.ohlcLabel = [self makeLabel:11 bold:NO color:[UIColor grayColor]];
    self.ohlcLabel.frame = CGRectMake(16, y, w - 32, 16);
    self.ohlcLabel.text = @"长按K线查看某日详情";
    [self.scrollView addSubview:self.ohlcLabel];
    y += 20;

    // K 线图
    self.klineView = [[TBKLineDrawView alloc] initWithFrame:CGRectMake(0, y, w, 300)];
    self.klineView.onSelectItem = ^(TBFinanceKLineItem *item) {
        self.ohlcLabel.text = [NSString stringWithFormat:@"%@  开 %.2f  高 %.2f  低 %.2f  收 %.2f  涨跌 %.2f%%",
                               item.date, item.open, item.high, item.low, item.close, item.changePercent];
    };
    self.klineView.onClearSelect = ^{
        self.ohlcLabel.text = @"长按K线查看某日详情";
    };
    self.klineView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.klineView];
    y += 316;

    // 信息区
    self.infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 10)];
    self.infoLabel.numberOfLines = 0;
    self.infoLabel.font = [UIFont systemFontOfSize:13];
    [self.scrollView addSubview:self.infoLabel];
    y += 10;

    self.scrollView.contentSize = CGSizeMake(w, y);
    [self updatePeriodButtonStyle];
}

- (UILabel *)makeLabel:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.font = [UIFont systemFontOfSize:size weight:bold ? UIFontWeightSemibold : UIFontWeightRegular];
    l.textColor = color;
    return l;
}

- (void)updatePeriodButtonStyle {
    [self.periodButtons enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *s) {
        BOOL on = (TBFinanceKLinePeriod)(101 + i) == self.currentPeriod;
        b.layer.borderColor = on ? [UIColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1].CGColor : [UIColor lightGrayColor].CGColor;
        b.layer.borderWidth = on ? 0 : 1;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.backgroundColor = on ? [UIColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1] : [UIColor clearColor];
    }];
}

#pragma mark - 实时轮询

- (void)startPolling {
    [self refreshPrice];
    self.pollTimer = [NSTimer timerWithTimeInterval:kPollInterval
                                             target:self
                                           selector:@selector(refreshPrice)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
}

- (void)refreshPrice {
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchQuotes:@[self.target.secid]
                                       completion:^(NSArray<TBFinanceQuote *> *quotes, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself || error || !quotes.count) return;
        [sself applyQuote:quotes.firstObject];
    }];
}

- (void)applyQuote:(TBFinanceQuote *)q {
    self.priceLabel.text = [NSString stringWithFormat:@"%.2f", q.price];
    UIColor *c = [TBFinanceColor colorForPercent:q.changePercent];
    self.priceLabel.textColor = c;
    self.changeLabel.textColor = c;
    self.changeLabel.text = [NSString stringWithFormat:@"%@  %@  %@",
                             q.change >= 0 ? @"+" : @"",
                             [NSString stringWithFormat:@"%+.2f", q.change],
                             [NSString stringWithFormat:@"%+.2f%%", q.changePercent]];
    self.timeLabel.text = [NSString stringWithFormat:@"%@ %@ · 实时轮询 %@.0fs", q.name ?: @"", q.timeText ?: @"", @(kPollInterval)];
}

#pragma mark - K 线

- (void)switchPeriod:(UIButton *)sender {
    self.currentPeriod = (TBFinanceKLinePeriod)(101 + sender.tag);
    [self updatePeriodButtonStyle];
    [self loadKLine];
}

- (void)loadKLine {
    if (!self.currentPeriod) self.currentPeriod = TBFinanceKLinePeriodDay;
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchKLine:self.target.secid
                                          period:self.currentPeriod
                                           limit:120
                                      completion:^(TBFinanceKLine *kline, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself || !kline) return;
        [sself.klineView reloadWithKLine:kline];
    }];
}

#pragma mark - 详情 / 信息区

- (void)loadExtraInfo {
    if (self.target.kind == 1) { [self loadFundInfo]; return; }
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchDetail:self.target.secid
                                       completion:^(NSDictionary *detail, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself || !detail) return;
        [sself renderMetrics:detail];
        [sself renderCompanyInfo:detail];
    }];
}

- (NSString *)metricText:(NSDictionary *)d key:(NSString *)key {
    return [self metricText:d key:key fmt:nil suffix:nil];
}

- (NSString *)metricText:(NSDictionary *)d key:(NSString *)key suffix:(NSString *)suffix {
    return [self metricText:d key:key fmt:nil suffix:suffix];
}

- (NSString *)metricText:(NSDictionary *)d key:(NSString *)key fmt:(NSString *)fmt {
    return [self metricText:d key:key fmt:fmt suffix:nil];
}

- (NSString *)metricText:(NSDictionary *)d key:(NSString *)key fmt:(NSString *)fmt suffix:(NSString *)suffix {
    id v = d[key];
    if ([v isKindOfClass:[NSNumber class]]) {
        return [NSString stringWithFormat:@"%@%@", [NSString stringWithFormat:fmt ?: @"%.2f", [v doubleValue]], suffix ?: @""];
    }
    return @"--";
}

- (void)renderMetrics:(NSDictionary *)d {
    // 宫格数据：4 列 3 行
    NSArray *rows = @[
        @[@{@"t": @"今开",   @"v": [self metricText:d key:@"f46"]},
          @{@"t": @"最高",   @"v": [self metricText:d key:@"f44"]},
          @{@"t": @"最低",   @"v": [self metricText:d key:@"f45"]},
          @{@"t": @"昨收",   @"v": [self metricText:d key:@"f60"]}],
        @[@{@"t": @"成交量", @"v": [self metricText:d key:@"f47" fmt:@"%.0f" suffix:@"手"]},
          @{@"t": @"成交额", @"v": [self metricText:d key:@"f48" fmt:@"%.0f" suffix:@"元"]},
          @{@"t": @"振幅",   @"v": [self metricText:d key:@"f171" suffix:@"%"]},
          @{@"t": @"换手率", @"v": [self metricText:d key:@"f168" suffix:@"%"]}],
        @[@{@"t": @"总市值", @"v": [self metricText:d key:@"f116" fmt:@"%.0f" suffix:@"元"]},
          @{@"t": @"市盈率", @"v": [self metricText:d key:@"f162"]},
          @{@"t": @"市净率", @"v": [self metricText:d key:@"f167"]},
          @{@"t": @"量比",   @"v": [self metricText:d key:@"f50"]}],
    ];
    for (NSArray *row in rows) {
        UIStackView *hs = [[UIStackView alloc] init];
        hs.axis = UILayoutConstraintAxisHorizontal;
        hs.distribution = UIStackViewDistributionFillEqually;
        for (NSDictionary *m in row) {
            UILabel *l = [[UILabel alloc] init];
            l.numberOfLines = 0;
            l.font = [UIFont systemFontOfSize:12];
            NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", m[@"t"], m[@"v"]]];
            [as addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11] range:NSMakeRange(0, ((NSString *)m[@"t"]).length)];
            [as addAttribute:NSForegroundColorAttributeName value:[UIColor grayColor] range:NSMakeRange(0, ((NSString *)m[@"t"]).length)];
            [as addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] range: NSMakeRange(((NSString *)m[@"t"]).length + 1, ((NSString *)m[@"v"]).length)];
            l.attributedText = as;
            [hs addArrangedSubview:l];
        }
        [self.metricsStack addArrangedSubview:hs];
    }
}

- (void)renderCompanyInfo:(NSDictionary *)d {
    NSMutableString *info = [NSMutableString stringWithString:@"—— 公司 / 标的信息 ——\n"];
    [info appendFormat:@"代码：%@  市场：%@  \n", d[@"f57"] ?: @"--", [self marketName:d[@"f107"]]];
    [info appendFormat:@"52周最高：%@  52周最低：%@\n", [self metricText:d key:@"f174" suffix:@""], @"--"];
    [info appendFormat:@"总股本：%@  流通股本：%@\n", [self metricText:d key:@"f84" fmt:@"%.0f"], [self metricText:d key:@"f85" fmt:@"%.0f"]];
    [info appendFormat:@"每股净资产：%@  每股收益：%@",
     [self metricText:d key:@"f92"], [self metricText:d key:@"f55" fmt:@"%.2f"]];
    self.infoLabel.text = info;
    [self.infoLabel sizeToFit];
    self.infoLabel.frame = CGRectMake(16, self.infoLabel.frame.origin.y,
                                      self.view.bounds.size.width - 32, MAX(self.infoLabel.frame.size.height, 40));
    CGFloat bottom = CGRectGetMaxY(self.infoLabel.frame) + 40;
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, MAX(bottom, self.scrollView.contentSize.height));
}

- (NSString *)marketName:(id)f107 {
    switch ([f107 integerValue]) {
        case 0: return @"深A"; case 1: return @"沪A";
        case 105: return @"美股"; case 106: return @"美股";
        case 116: return @"港股"; case 100: return @"全球指数";
        default: return @"--";
    }
}

- (void)loadFundInfo {
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchFundInfo:self.target.code
                                         completion:^(TBFinanceFundInfo *info, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself || !info) return;
        NSMutableString *ms = [NSMutableString stringWithString:@"—— 基金信息 ——\n"];
        [ms appendFormat:@"全称：%@（%@）\n", info.name, info.type];
        [ms appendFormat:@"基金公司：%@   基金经理：%@\n", info.company, info.manager];
        [ms appendFormat:@"成立日期：%@   规模：%.2f 亿元\n", info.established, info.scale];
        sself.infoLabel.text = ms;
        [sself.infoLabel sizeToFit];
        sself.infoLabel.frame = CGRectMake(16, sself.infoLabel.frame.origin.y,
                                           sself.view.bounds.size.width - 32, MAX(sself.infoLabel.frame.size.height, 40));
        sself.scrollView.contentSize = CGSizeMake(sself.view.bounds.size.width, CGRectGetMaxY(sself.infoLabel.frame) + 40);
    }];
}

@end
