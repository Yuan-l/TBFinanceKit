//
//  TBFinanceHomeViewController.m
//  TBFinanceKit
//
//  页签数据策略：
//  - 股票/指数：固定 secid 列表，3s 轮询刷新（模拟实时）
//  - 板块：clist 拉取（涨跌幅排序），手动刷新
//  - 基金：搜索进入，列表展示净值
//  - 期权：新浪链路，选标的 + 月份 + 认购/认沽
//

#import "TBFinanceHomeViewController.h"
#import "TBFinanceService.h"
#import "TBFinanceDetailViewController.h"
#import "TBFinanceColor.h"

static NSTimeInterval const kListPollInterval = 4.0;

@interface TBQuoteCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *changeLabel;
@end

@implementation TBQuoteCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [self.contentView addSubview:self.nameLabel];

        self.codeLabel = [[UILabel alloc] init];
        self.codeLabel.font = [UIFont systemFontOfSize:11];
        self.codeLabel.textColor = [UIColor lightGrayColor];
        [self.contentView addSubview:self.codeLabel];

        self.priceLabel = [[UILabel alloc] init];
        self.priceLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.priceLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.priceLabel];

        self.changeLabel = [[UILabel alloc] init];
        self.changeLabel.font = [UIFont systemFontOfSize:12];
        self.changeLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:self.changeLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    self.nameLabel.frame = CGRectMake(16, 10, w * 0.4, 20);
    self.codeLabel.frame = CGRectMake(16, 32, w * 0.4, 14);
    self.priceLabel.frame = CGRectMake(w * 0.48, 8, w * 0.24, 22);
    self.changeLabel.frame = CGRectMake(w * 0.48, 32, w * 0.24, 14);
}

- (void)bindQuote:(TBFinanceQuote *)q {
    self.nameLabel.text = q.name;
    self.codeLabel.text = q.code;
    self.priceLabel.text = [NSString stringWithFormat:@"%.2f", q.price];
    UIColor *c = [TBFinanceColor colorForPercent:q.changePercent];
    self.priceLabel.textColor = c;
    self.changeLabel.textColor = c;
    self.changeLabel.text = [NSString stringWithFormat:@"%+.2f%%", q.changePercent];
}

@end

@interface TBFinanceHomeViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) NSTimer *pollTimer;
// 当前 tab 数据
@property (nonatomic, strong) NSArray<TBFinanceQuote *> *quotes;          // 股票/指数/美股
@property (nonatomic, strong) NSArray<TBFinanceFundInfo *> *funds;        // 基金
@property (nonatomic, strong) NSArray<TBFinanceOptionInfo *> *options;    // 期权
@property (nonatomic, copy) NSString *optionUnderlying;                   // 当前期权标的
@property (nonatomic, copy) NSString *optionMonth;
@property (nonatomic, assign) BOOL optionIsCall;
// 搜索模式
@property (nonatomic, assign) BOOL searching;
@property (nonatomic, strong) NSArray<TBFinanceQuote *> *searchResults;
@end

@implementation TBFinanceHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"行情";

    [self buildUI];
    [self switchToSegment:self.segment.selectedSegmentIndex];
    [self startPolling];
}

- (void)dealloc {
    [_pollTimer invalidate];
}

#pragma mark - UI

- (void)buildUI {
    self.segment = [[UISegmentedControl alloc] initWithItems:@[@"A股", @"港股", @"美股", @"指数", @"板块", @"基金", @"期权"]];
    self.segment.selectedSegmentIndex = 0;
    self.segment.frame = CGRectMake(12, 8, self.view.bounds.size.width - 24, 32);
    self.segment.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.segment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segment];

    CGFloat ty = CGRectGetMaxY(self.segment.frame) + 8;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, ty, self.view.bounds.size.width, self.view.bounds.size.height - ty)
                                                  style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 52;
    [self.tableView registerClass:[TBQuoteCell class] forCellReuseIdentifier:@"q"];
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(manualRefresh) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refresh];
    [self.view addSubview:self.tableView];

    // 搜索按钮
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch
                                                                                           target:self
                                                                                           action:@selector(showSearch)];
}

- (void)segmentChanged:(UISegmentedControl *)seg {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    self.quotes = @[]; self.funds = @[]; self.options = @[];
    [self.tableView reloadData];
    [self switchToSegment:seg.selectedSegmentIndex];
    // 仅股票/指数类开启轮询
    if (seg.selectedSegmentIndex <= 3) [self startPolling];
}

- (void)manualRefresh {
    [self switchToSegment:self.segment.selectedSegmentIndex];
    [self.refresh endRefreshing];
}

- (void)switchToSegment:(NSInteger)idx {
    __weak typeof(self) wself = self;
    TBFinanceService *svc = [TBFinanceService sharedService];

    switch (idx) {
        case 0: case 1: case 2: case 3: {
            TBFinanceCategory cat = (TBFinanceCategory)(idx == 3 ? TBFinanceCategory全球指数 : idx);
            [svc fetchQuotes:[TBFinanceService defaultSecidsForCategory:cat]
                  completion:^(NSArray<TBFinanceQuote *> *quotes, NSError *error) {
                __strong typeof(wself) sself = wself;
                if (!sself) return;
                sself.quotes = quotes;
                [sself.tableView reloadData];
            }];
            break;
        }
        case 4: {   // 板块：东财 clist 涨幅榜
            [self fetchSectorList];
            break;
        }
        case 5: {   // 基金：默认搜几只热门
            [svc searchFunds:@"消费" completion:^(NSArray<TBFinanceFundInfo *> *funds, NSError *error) {
                __strong typeof(wself) sself = wself;
                if (!sself) return;
                sself.funds = funds;
                [sself.tableView reloadData];
                // 拉净值
                for (TBFinanceFundInfo *f in funds) { [sself fetchFundNav:f]; }
            }];
            break;
        }
        case 6: {   // 期权：默认 300ETF
            self.optionUnderlying = @"510300";
            self.optionMonth = [self currentOptionMonth];
            self.optionIsCall = YES;
            [self fetchOptionChain];
            break;
        }
    }
}

- (NSString *)currentOptionMonth {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"yyyyMM";
    return [f stringFromDate:[NSDate date]];
}

- (void)startPolling {
    [self.pollTimer invalidate];
    __weak typeof(self) wself = self;
    self.pollTimer = [NSTimer timerWithTimeInterval:kListPollInterval target:self selector:@selector(pollQuotes) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
}

- (void)pollQuotes {
    __weak typeof(self) wself = self;
    if (self.segment.selectedSegmentIndex > 3) return;
    TBFinanceCategory cat = (TBFinanceCategory)(self.segment.selectedSegmentIndex == 3 ? TBFinanceCategory全球指数 : self.segment.selectedSegmentIndex);
    [[TBFinanceService sharedService] fetchQuotes:[TBFinanceService defaultSecidsForCategory:cat]
                                       completion:^(NSArray<TBFinanceQuote *> *quotes, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself || !quotes.count) return;
        sself.quotes = quotes;
        [sself.tableView reloadData];
    }];
}

#pragma mark - 板块 / 基金 / 期权加载

- (void)fetchSectorList {
    // 板块榜单走 clist（见 TBFinanceService 之外独立封装，直接用 secid=m:90 前缀批量换算）
    // 简化：用固定几个热门板块指数 secid
    NSArray *sectorSecids = @[@"90.BK0475", @"90.BK0737", @"90.BK0448", @"90.BK1036", @"90.BK0910", @"90.BK0478", @"90.BK0733", @"90.BK0428"];
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchQuotes:sectorSecids completion:^(NSArray<TBFinanceQuote *> *quotes, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        sself.quotes = quotes;
        [sself.tableView reloadData];
    }];
}

- (void)fetchFundNav:(TBFinanceFundInfo *)fund {
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchFundNavHistory:fund.code limit:1 completion:^(NSArray<NSDictionary *> *rows, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself || !rows.count) return;
        NSDictionary *r = rows.firstObject;
        TBFinanceQuote *q = [TBFinanceQuote new];
        q.secid = fund.code;
        q.code = fund.code;
        q.name = fund.name;
        q.price = [r[@"DWJZ"] doubleValue];
        q.changePercent = [r[@"JZZZL"] doubleValue];
        q.change = [r[@"JZZZL"] doubleValue];
        q.timeText = r[@"FSRQ"];
        NSMutableArray *arr = [sself.funds mutableCopy];
        // 防重
        for (TBFinanceQuote *exist in sself.quotes) { if ([exist.code isEqualToString:fund.code]) return; }
        // funds 数组保持原样；quotes 混入净值行情用于展示
        NSMutableArray *qs = [sself.quotes ?: @[] mutableCopy];
        [qs addObject:q];
        sself.quotes = qs;
        [sself.tableView reloadData];
    }];
}

- (void)fetchOptionChain {
    __weak typeof(self) wself = self;
    [[TBFinanceService sharedService] fetchOptionChain:self.optionUnderlying
                                                month:self.optionMonth
                                                isCall:self.optionIsCall
                                            completion:^(NSArray<TBFinanceOptionInfo *> *contracts, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!sself) return;
        sself.options = contracts;
        [sself.tableView reloadData];
    }];
}

#pragma mark - 搜索

- (void)showSearch {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"搜索标的"
                                                                   message:@"支持 A股/港股/美股/指数/基金（如：茅台、00700、AAPL、白酒）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"代码或名称"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"搜标的" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *kw = alert.textFields.firstObject.text ?: @"";
        if (!kw.length) return;
        __weak typeof(self) wself = self;
        [[TBFinanceService sharedService] search:kw completion:^(NSArray<TBFinanceQuote *> *results, NSError *error) {
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            sself.searching = YES;
            sself.searchResults = results;
            sself.navigationItem.title = [NSString stringWithFormat:@"搜索:%@ (%lu)", kw, (unsigned long)results.count];
            [sself.tableView reloadData];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"搜基金" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *kw = alert.textFields.firstObject.text ?: @"";
        if (!kw.length) return;
        __weak typeof(self) wself = self;
        [[TBFinanceService sharedService] searchFunds:kw completion:^(NSArray<TBFinanceFundInfo *> *funds, NSError *error) {
            __strong typeof(wself) sself = wself;
            if (!sself) return;
            sself.segment.selectedSegmentIndex = 5;
            sself.funds = funds;
            [sself.tableView reloadData];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"返回列表" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        __weak typeof(self) wself = self;
        wself.searching = NO;
        wself.navigationItem.title = @"行情";
        [wself.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.searching) return self.searchResults.count;
    switch (self.segment.selectedSegmentIndex) {
        case 5: return self.funds.count;
        case 6: return self.options.count;
        default: return self.quotes.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TBQuoteCell *cell = [tableView dequeueReusableCellWithIdentifier:@"q" forIndexPath:indexPath];

    if (self.searching) {
        TBFinanceQuote *q = self.searchResults[indexPath.row];
        [cell bindQuote:q];
        cell.priceLabel.text = @"--";
        cell.changeLabel.text = q.secid;
        cell.changeLabel.textColor = [UIColor lightGrayColor];
        return cell;
    }

    switch (self.segment.selectedSegmentIndex) {
        case 5: {
            TBFinanceFundInfo *f = self.funds[indexPath.row];
            TBFinanceQuote *match = nil;
            for (TBFinanceQuote *q in self.quotes) if ([q.code isEqualToString:f.code]) { match = q; break; }
            if (match) { [cell bindQuote:match]; }
            else {
                cell.nameLabel.text = f.name; cell.codeLabel.text = f.code;
                cell.priceLabel.text = @"--"; cell.changeLabel.text = @"加载净值…";
                cell.priceLabel.textColor = [UIColor blackColor]; cell.changeLabel.textColor = [UIColor grayColor];
            }
            break;
        }
        case 6: {
            TBFinanceOptionInfo *o = self.options[indexPath.row];
            cell.nameLabel.text = o.name;
            cell.codeLabel.text = [NSString stringWithFormat:@"%@ 行权%.0f 持仓%.0f", o.contractCode, o.strike, o.openInterest];
            cell.priceLabel.text = [NSString stringWithFormat:@"%.4f", o.price];
            UIColor *c = [TBFinanceColor colorForPercent:o.changePercent];
            cell.priceLabel.textColor = c;
            cell.changeLabel.textColor = c;
            cell.changeLabel.text = [NSString stringWithFormat:@"%+.2f%%", o.changePercent];
            break;
        }
        default: {
            [cell bindQuote:self.quotes[indexPath.row]];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    TBFinanceTarget *t = [TBFinanceTarget new];
    if (self.searching) {
        TBFinanceQuote *q = self.searchResults[indexPath.row];
        t.secid = q.secid; t.code = q.code; t.name = q.name;
    } else {
        switch (self.segment.selectedSegmentIndex) {
            case 5: {
                TBFinanceFundInfo *f = self.funds[indexPath.row];
                t.secid = f.code; t.code = f.code; t.name = f.name;
                t.kind = 1;
                break;
            }
            case 6: {
                TBFinanceOptionInfo *o = self.options[indexPath.row];
                t.secid = [NSString stringWithFormat:@"8.%@", o.contractCode];   // 期权无东财 K 线，占位
                t.code = o.contractCode; t.name = o.name;
                t.kind = 2; t.extraCode = o.contractCode;
                break;
            }
            default: {
                TBFinanceQuote *q = self.quotes[indexPath.row];
                t.secid = q.secid; t.code = q.code; t.name = q.name;
            }
        }
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:[[TBFinanceDetailViewController alloc] initWithTarget:t] animated:YES];
}

@end
