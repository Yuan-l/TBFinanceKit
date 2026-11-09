//
//  TBFinanceService.m
//  TBFinanceKit
//
//  数据源（全部公开接口，2026-11 实测可用）：
//  - 行情/K线/详情/搜索：东方财富 push2 系列
//  - 基金：天天基金 mobapi + fundsuggest
//  - 期权：新浪财经 StockOptionService + hq.sinajs.cn（需 Referer）
//
//  域名 fallback：不同网络环境下部分 CDN 前缀域名空回复（实测 push2 主域、
//  push2his 主域在本机空回复），故每个接口维护候选域名列表，失败依次重试。
//

#import "TBFinanceService.h"

NSErrorDomain const TBFinanceErrorDomain = @"TBFinanceErrorDomain";

static NSString * const kUTToken = @"fa5fd1943c7b386f172d6893dbfba10b";
static NSString * const kSearchToken = @"D43BF722C8E33BDC906FB84D85E326E8";

static NSTimeInterval const kRequestTimeout = 10.0;

#pragma mark - 内部工具

/// 域名候选数组（多线程只读，不加密）
static NSArray<NSString *> *QuoteHosts(void) {
    static NSArray *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = @[@"82.push2.eastmoney.com",
                  @"push2.eastmoney.com",
                  @"23.push2.eastmoney.com"];
    });
    return hosts;
}

static NSArray<NSString *> *KLineHosts(void) {
    static NSArray *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = @[@"41.push2his.eastmoney.com",
                  @"18.push2his.eastmoney.com",
                  @"92.push2his.eastmoney.com",
                  @"push2his.eastmoney.com"];
    });
    return hosts;
}

@implementation TBFinanceFundInfo
@end

@implementation TBFinanceOptionInfo
@end

@implementation TBFinanceService

+ (instancetype)sharedService {
    static TBFinanceService *svc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ svc = [[self alloc] init]; });
    return svc;
}

#pragma mark - HTTP 基础

/// 在多域名上依次尝试 GET，返回首个成功且能解析为 JSON 的响应
- (void)getJSONPath:(NSString *)path
              query:(NSDictionary<NSString *, NSString *> *)query
              hosts:(NSArray<NSString *> *)hosts
         headers:(NSDictionary<NSString *, NSString *> *)extraHeaders
          isText:(BOOL)isText
       completion:(void (^)(id _Nullable json, NSError *_Nullable error))completion {
    NSMutableString *qs = [NSMutableString string];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [qs appendFormat:@"%@%@=%@",
         qs.length ? @"&" : @"",
         [k stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
         [v stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }];

    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableArray<NSString *> *hostList = [hosts mutableCopy];
    __block void (^attempt)(NSUInteger);
    __weak typeof(self) wself = self;

    attempt = ^(NSUInteger idx) {
        if (idx >= hostList.count) {
            completion(nil, [NSError errorWithDomain:TBFinanceErrorDomain
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"全部域名请求失败"}]);
            return;
        }
        NSString *host = hostList[idx];
        NSString *urlStr = [NSString stringWithFormat:@"https://%@%@%@", host, path, qs.length ? [@"?" stringByAppendingString:qs] : @""];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) {
            attempt(idx + 1);
            return;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:kRequestTimeout];
        [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
       forHTTPHeaderField:@"User-Agent"];
        [extraHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
            [req setValue:v forHTTPHeaderField:k];
        }];

        NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                                completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            BOOL ok = (!err && data.length > 0 &&
                       [((NSHTTPURLResponse *)resp) statusCode] == 200);
            if (!ok) {
                dispatch_async(dispatch_get_main_queue(), ^{ attempt(idx + 1); });
                return;
            }
            id parsed = nil;
            if (isText) {
                // 新浪接口 GBK 编码
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (!text) text = [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
                parsed = text;
            } else {
                parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            if (parsed == nil) {
                dispatch_async(dispatch_get_main_queue(), ^{ attempt(idx + 1); });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(parsed, nil); });
        }];
        [task resume];
    };
    attempt(0);
}

#pragma mark - 实时行情

- (void)fetchQuotes:(NSArray<NSString *> *)secids
         completion:(void (^)(NSArray<TBFinanceQuote *> *, NSError *))completion {
    if (!secids.count) { completion(@[], nil); return; }

    NSDictionary *query = @{
        @"ut": kUTToken,
        @"fltt": @"2",
        @"invt": @"2",
        @"secids": [secids componentsJoinedByString:@","],
        @"fields": @"f2,f3,f4,f12,f13,f14,f18,f124",
    };
    [self getJSONPath:@"/api/qt/ulist.np/get" query:query hosts:QuoteHosts() headers:nil isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSArray *diff = json[@"data"][@"diff"] ?: @[];
        NSMutableArray<TBFinanceQuote *> *out = [NSMutableArray array];
        for (NSDictionary *d in diff) {
            TBFinanceQuote *q = [TBFinanceQuote new];
            NSInteger market = [d[@"f13"] integerValue];
            q.secid = [NSString stringWithFormat:@"%ld.%@", (long)market, d[@"f12"] ?: @""];
            q.market = market;
            q.code = d[@"f12"] ?: @"";
            q.name = d[@"f14"] ?: @"";
            q.price = [self safeDouble:d[@"f2"]];
            q.change = [self safeDouble:d[@"f3"]];
            // fltt=2 时 f3 已是涨跌幅百分比，f4 是涨跌额
            q.changePercent = [self safeDouble:d[@"f3"]];
            q.change = [self safeDouble:d[@"f4"]];
            q.preClose = [self safeDouble:d[@"f18"]];
            q.timeText = [self formatTickTime:d[@"f124"]];
            [out addObject:q];
        }
        completion(out, nil);
    }];
}

- (double)safeDouble:(id)v {
    if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    if ([v isKindOfClass:[NSString class]]) return [v doubleValue];
    return 0;   // "-" 等占位值
}

- (NSString *)formatTickTime:(id)f124 {
    if ([f124 isKindOfClass:[NSNumber class]]) {
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:[f124 doubleValue]];
        NSDateFormatter *f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"HH:mm:ss";
        return [f stringFromDate:d];
    }
    return nil;
}

#pragma mark - K 线

- (void)fetchKLine:(NSString *)secid
            period:(TBFinanceKLinePeriod)period
             limit:(NSInteger)limit
        completion:(void (^)(TBFinanceKLine *, NSError *))completion {
    NSDictionary *query = @{
        @"secid": secid,
        @"fields1": @"f1,f2,f3",
        @"fields2": @"f51,f52,f53,f54,f55,f56,f57",
        @"klt": [NSString stringWithFormat:@"%ld", (long)period],
        @"fqt": @"1",                 // 前复权
        @"lmt": [NSString stringWithFormat:@"%ld", (long)limit],
        @"end": @"20500101",
        @"ut": kUTToken,
    };
    [self getJSONPath:@"/api/qt/stock/kline/get" query:query hosts:KLineHosts() headers:nil isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSDictionary *data = json[@"data"];
        if (![data isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:TBFinanceErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey: @"K线数据为空"}]);
            return;
        }
        TBFinanceKLine *k = [TBFinanceKLine new];
        k.secid = secid;
        k.name = data[@"name"] ?: @"";
        k.preKPrice = [data[@"preKPrice"] doubleValue];
        NSMutableArray<TBFinanceKLineItem *> *items = [NSMutableArray array];
        double prevClose = k.preKPrice;
        for (NSString *line in data[@"klines"] ?: @[]) {
            NSArray *p = [line componentsSeparatedByString:@","];
            if (p.count < 7) continue;
            TBFinanceKLineItem *it = [TBFinanceKLineItem new];
            it.date = p[0];
            it.open = [p[1] doubleValue];
            it.close = [p[2] doubleValue];
            it.high = [p[3] doubleValue];
            it.low = [p[4] doubleValue];
            it.volume = [p[5] doubleValue];
            it.turnover = [p[6] doubleValue];
            if (prevClose > 0) it.changePercent = (it.close - prevClose) / prevClose * 100.0;
            prevClose = it.close;
            [items addObject:it];
        }
        k.items = items;
        completion(k, nil);
    }];
}

#pragma mark - 详情

- (void)fetchDetail:(NSString *)secid
         completion:(void (^)(NSDictionary *, NSError *))completion {
    NSDictionary *query = @{
        @"secid": secid,
        @"invt": @"2", @"fltt": @"2",
        @"ut": kUTToken,
        @"fields": @"f43,f44,f45,f46,f47,f48,f50,f57,f58,f60,f62,f84,f85,f107,f116,f117,f162,f167,f168,f169,f170,f171,f173,f183,f184,f185,f186,f187,f188,f189",
    };
    [self getJSONPath:@"/api/qt/stock/get" query:query hosts:QuoteHosts() headers:nil isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSDictionary *data = json[@"data"];
        completion([data isKindOfClass:[NSDictionary class]] ? data : nil,
                   data ? nil : [NSError errorWithDomain:TBFinanceErrorDomain code:-3 userInfo:@{NSLocalizedDescriptionKey: @"详情为空"}]);
    }];
}

#pragma mark - 搜索

- (void)search:(NSString *)keyword
    completion:(void (^)(NSArray<TBFinanceQuote *> *, NSError *))completion {
    NSDictionary *query = @{
        @"input": keyword,
        @"type": @"14",
        @"token": kSearchToken,
        @"count": @"20",
    };
    [self getJSONPath:@"/api/suggest/get" query:query hosts:@[@"searchadapter.eastmoney.com"] headers:nil isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSArray *rows = json[@"QuotationCodeTable"][@"Data"] ?: @[];
        NSMutableArray<TBFinanceQuote *> *out = [NSMutableArray array];
        for (NSDictionary *d in rows) {
            TBFinanceQuote *q = [TBFinanceQuote new];
            q.secid = d[@"QuoteID"] ?: @"";
            q.code = d[@"Code"] ?: @"";
            q.name = d[@"Name"] ?: @"";
            q.market = [d[@"MktNum"] integerValue];
            [out addObject:q];
        }
        completion(out, nil);
    }];
}

#pragma mark - 基金

- (void)searchFunds:(NSString *)keyword
         completion:(void (^)(NSArray<TBFinanceFundInfo *> *, NSError *))completion {
    NSDictionary *query = @{
        @"callback": @"",
        @"m": @"1",
        @"key": keyword ?: @"",
    };
    [self getJSONPath:@"/FundSearch/api/FundSearchAPI.ashx" query:query
                hosts:@[@"fundsuggest.eastmoney.com"]
             headers:@{@"Referer": @"http://fundsuggest.eastmoney.com/"} isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSArray *rows = json[@"Datas"] ?: @[];
        NSMutableArray<TBFinanceFundInfo *> *out = [NSMutableArray array];
        for (NSDictionary *d in rows) {
            if ([d[@"CATEGORY"] integerValue] != 700) continue;   // 700 = 基金
            TBFinanceFundInfo *f = [TBFinanceFundInfo new];
            f.code = d[@"CODE"] ?: @"";
            f.name = d[@"NAME"] ?: @"";
            [out addObject:f];
        }
        completion(out, nil);
    }];
}

- (void)fetchFundInfo:(NSString *)fundCode
           completion:(void (^)(TBFinanceFundInfo *, NSError *))completion {
    NSDictionary *query = @{
        @"FCODE": fundCode,
        @"deviceid": @"Wap", @"plat": @"Wap", @"product": @"EFund", @"version": @"6.2.5",
    };
    [self getJSONPath:@"/FundMNewApi/FundMNDetailInformation" query:query
                hosts:@[@"fundmobapi.eastmoney.com"] headers:nil isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSDictionary *d = json[@"Datas"];
        if (![d isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:TBFinanceErrorDomain code:-4 userInfo:@{NSLocalizedDescriptionKey: @"基金详情为空"}]);
            return;
        }
        TBFinanceFundInfo *f = [TBFinanceFundInfo new];
        f.code = d[@"FCODE"] ?: @"";
        f.name = d[@"SHORTNAME"] ?: @"";
        f.type = d[@"FTYPE"] ?: @"";
        f.company = d[@"JJGS"] ?: @"";
        f.manager = d[@"JJJL"] ?: @"";
        f.established = d[@"ESTABDATE"] ?: @"";
        f.scale = [d[@"ENDNAV"] doubleValue] / 1e8;
        completion(f, nil);
    }];
}

- (void)fetchFundNavHistory:(NSString *)fundCode
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    NSDictionary *query = @{
        @"FCODE": fundCode,
        @"pageIndex": @"1",
        @"pageSize": [NSString stringWithFormat:@"%ld", (long)limit],
        @"deviceid": @"Wap", @"plat": @"Wap", @"product": @"EFund", @"version": @"6.2.5",
    };
    [self getJSONPath:@"/FundMNewApi/FundMNHisNetList" query:query
                hosts:@[@"fundmobapi.eastmoney.com"] headers:nil isText:NO
           completion:^(NSDictionary *json, NSError *err) {
        if (err) { completion(nil, err); return; }
        completion(json[@"Datas"] ?: @[], nil);
    }];
}

#pragma mark - 期权（新浪）

- (void)fetchOptionUnderlyings:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    // 内置常见 ETF 期权标的（合约月份走新浪 getStockName 动态获取）
    completion(@[
        @{@"underlying": @"510050", @"name": @"50ETF"},
        @{@"underlying": @"510300", @"name": @"300ETF"},
        @{@"underlying": @"510500", @"name": @"500ETF"},
        @{@"underlying": @"588000", @"name": @"科创50ETF"},
    ], nil);
}

- (void)fetchOptionChain:(NSString *)underlying
                   month:(NSString *)month
                  isCall:(BOOL)isCall
               completion:(void (^)(NSArray<TBFinanceOptionInfo *> *, NSError *))completion {
    // month: 202612 → yymm: 2612
    NSString *yymm = month.length >= 4 ? [month substringFromIndex:2] : month;
    NSString *listKey = [NSString stringWithFormat:@"%@_%@%@", isCall ? @"OP_UP" : @"OP_DOWN", underlying, yymm];

    // 第一步：拿合约代码列表（文本，GB8? 实为 UTF-8）
    NSDictionary *listQuery = @{@"list": listKey};
    [self getJSONPath:@"" query:listQuery
                hosts:@[@"hq.sinajs.cn"]
             headers:@{@"Referer": @"https://finance.sina.com.cn"} isText:YES
           completion:^(NSString *text, NSError *err) {
        if (err || !text) { completion(nil, err ?: [NSError errorWithDomain:TBFinanceErrorDomain code:-5 userInfo:@{NSLocalizedDescriptionKey: @"期权列表为空"}]); return; }

        // var hq_str_OP_UP_5103002612="CON_OP_10012663,CON_OP_10012623,...";
        NSRange r = [text rangeOfString:@"\""];
        if (r.location == NSNotFound) { completion(@[], nil); return; }
        NSRange r2 = [text rangeOfString:@"\"" options:NSBackwardsSearch];
        if (r2.location <= r.location) { completion(@[], nil); return; }
        NSString *inner = [text substringWithRange:NSMakeRange(r.location + 1, r2.location - r.location - 1)];
        NSMutableArray<NSString *> *codes = [NSMutableArray array];
        for (NSString *token in [inner componentsSeparatedByString:@","]) {
            NSString *c = [token stringByReplacingOccurrencesOfString:@"CON_OP_" withString:@""];
            if (c.length) [codes addObject:c];
        }
        if (!codes.count) { completion(@[], nil); return; }

        // 第二步：批量实时行情（CON_OP_ 每次最多约 60 个，分批）
        NSMutableArray<TBFinanceOptionInfo *> *out = [NSMutableArray array];
        __block NSInteger pending = 0;
        __block BOOL failed = NO;
        NSArray *batches = [self splitArray:codes batchSize:50];
        pending = batches.count;
        for (NSArray *batch in batches) {
            NSDictionary *q = @{@"list": [NSString stringWithFormat:@"CON_OP_%@", [batch componentsJoinedByString:@",CON_OP_"]]};
            [self getJSONPath:@"" query:q hosts:@[@"hq.sinajs.cn"]
                     headers:@{@"Referer": @"https://finance.sina.com.cn"} isText:YES
                   completion:^(NSString *quoteText, NSError *e2) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    pending--;
                    if (e2) failed = YES;
                    if (quoteText) {
                        [out addObjectsFromArray:[self parseOptionQuotes:quoteText isCall:isCall]];
                    }
                    if (pending == 0) {
                        completion(failed && out.count == 0 ? nil : out,
                                   (failed && out.count == 0) ? [NSError errorWithDomain:TBFinanceErrorDomain code:-6 userInfo:@{NSLocalizedDescriptionKey: @"期权行情获取失败"}] : nil);
                    }
                });
            }];
        }
    }];
}

/// 解析 CON_OP_ 批量行情（43 字段）
- (NSArray<TBFinanceOptionInfo *> *)parseOptionQuotes:(NSString *)text isCall:(BOOL)isCall {
    NSMutableArray<TBFinanceOptionInfo *> *out = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@";\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *varName = [line substringToIndex:eq.location];           // var hq_str_CON_OP_10012663
        NSString *body = [line substringFromIndex:eq.location + 1];
        body = [body stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"; \r\n"]];
        if (!body.length) continue;

        NSRange codeRange = [varName rangeOfString:@"CON_OP_"];
        if (codeRange.location == NSNotFound) continue;
        NSString *code = [varName substringFromIndex:NSMaxRange(codeRange)];

        NSArray *f = [body componentsSeparatedByString:@","];
        if (f.count < 43) continue;

        TBFinanceOptionInfo *o = [TBFinanceOptionInfo new];
        o.contractCode = code;
        o.name = f[37];
        o.price = [f[2] doubleValue];
        o.changePercent = [f[6] doubleValue];
        o.strike = [f[7] doubleValue];
        o.volume = [f[41] doubleValue];
        o.openInterest = [f[5] doubleValue];
        o.timeText = f[32];
        o.isCall = isCall;
        [out addObject:o];
    }
    return out;
}

- (NSArray<NSArray *> *)splitArray:(NSArray *)arr batchSize:(NSUInteger)n {
    NSMutableArray<NSArray *> *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < arr.count; i += n) {
        NSUInteger end = MIN(i + n, arr.count);
        [out addObject:[arr subarrayWithRange:NSMakeRange(i, end - i)]];
    }
    return out;
}

#pragma mark - 各分类默认标的

+ (NSArray<NSString *> *)defaultSecidsForCategory:(TBFinanceCategory)category {
    switch (category) {
        case TBFinanceCategoryA股:
            return @[@"1.600519", @"1.601398", @"1.601318", @"0.000001", @"0.000858", @"0.300750", @"0.002594", @"1.688981", @"1.600036", @"0.002230"];
        case TBFinanceCategory港股:
            return @[@"116.00700", @"116.09988", @"116.03690", @"116.01810", @"116.01211", @"116.00388", @"116.00285", @"116.00941"];
        case TBFinanceCategory美股:
            return @[@"105.AAPL", @"105.MSFT", @"105.NVDA", @"105.TSLA", @"105.AMZN", @"105.GOOG", @"105.META", @"106.BABA", @"106.PDD", @"106.NIO"];
        case TBFinanceCategory全球指数:
            return @[@"100.NDX", @"100.DJIA", @"100.SPX", @"100.HSI", @"100.HSTECH", @"100.N225", @"100.FTSE", @"100.GDAXI"];
        case TBFinanceCategory行业板块:
            return @[];   // 走 clist 动态拉取
        case TBFinanceCategory基金:
            return @[];   // 走基金搜索
        case TBFinanceCategory期权:
            return @[];   // 走新浪期权链
    }
}

@end
