//
//  TBFinanceService.h
//  TBFinanceKit
//
//  金融数据服务：统一封装东方财富 push2 / 天天基金 mobapi / 新浪财经三路公开数据源。
//
//  设计要点：
//  1. 多域名 fallback：本机/运营商对各 CDN 前缀域名（82.push2 / 41.push2his 等）
//     可达性不同，请求失败自动换下一个域名重试。
//  2. 全部为公开数据接口，无鉴权（ut token 为站点公共 token）。
//  3. 回调统一主线程，错误统一 NSError(domain:TBFinanceErrorDomain)。
//

#import <Foundation/Foundation.h>
#import "TBFinanceQuote.h"
#import "TBFinanceKLine.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const TBFinanceErrorDomain;

/// 标的分类（决定列表 secid 来源与展示 tab）
typedef NS_ENUM(NSInteger, TBFinanceCategory) {
    TBFinanceCategoryA股       = 0,
    TBFinanceCategory港股      = 1,
    TBFinanceCategory美股      = 2,
    TBFinanceCategory全球指数  = 3,
    TBFinanceCategory行业板块  = 4,
    TBFinanceCategory基金      = 5,
    TBFinanceCategory期权      = 6,
};

@class TBFinanceService;

#pragma mark - 基金模型

@interface TBFinanceFundInfo : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;        // 基金类型
@property (nonatomic, copy) NSString *company;     // 基金公司
@property (nonatomic, copy) NSString *manager;     // 基金经理
@property (nonatomic, copy) NSString *established; // 成立日期
@property (nonatomic, assign) double nav;          // 单位净值
@property (nonatomic, copy, nullable) NSString *navDate;
@property (nonatomic, assign) double navChangePercent; // 日增长率%
@property (nonatomic, assign) double scale;        // 规模（亿元）
@end

@interface TBFinanceOptionInfo : NSObject
@property (nonatomic, copy) NSString *contractCode;  // 10012663
@property (nonatomic, copy) NSString *name;          // 合约简称
@property (nonatomic, assign) double price;          // 最新价
@property (nonatomic, assign) double changePercent;  // 涨幅%
@property (nonatomic, assign) double strike;         // 行权价
@property (nonatomic, assign) double volume;         // 成交量
@property (nonatomic, assign) double openInterest;   // 持仓量
@property (nonatomic, copy, nullable) NSString *timeText;
@property (nonatomic, assign) BOOL isCall;           // 是否认购
@end

#pragma mark - Service

@interface TBFinanceService : NSObject

+ (instancetype)sharedService;

#pragma mark 实时行情（轮询用，建议 3~5s 一次）

/// 批量实时行情（东财 ulist.np，支持混排 secid）
/// @param secids 如 @[@"1.600519", @"116.00700", @"105.AAPL"]
- (void)fetchQuotes:(NSArray<NSString *> *)secids
         completion:(void (^)(NSArray<TBFinanceQuote *> *quotes, NSError *_Nullable error))completion;

#pragma mark K 线

/// K 线（日/周/月）
- (void)fetchKLine:(NSString *)secid
            period:(TBFinanceKLinePeriod)period
             limit:(NSInteger)limit
        completion:(void (^)(TBFinanceKLine *_Nullable kline, NSError *_Nullable error))completion;

#pragma mark 详情

/// 标的详情（含公司信息、估值、换手、振幅、市值等），返回原始字段字典
- (void)fetchDetail:(NSString *)secid
         completion:(void (^)(NSDictionary *_Nullable detail, NSError *_Nullable error))completion;

#pragma mark 搜索

/// 全局标的搜索（东财 searchadapter）
- (void)search:(NSString *)keyword
    completion:(void (^)(NSArray<TBFinanceQuote *> *results, NSError *_Nullable error))completion;

#pragma mark 基金

/// 基金搜索
- (void)searchFunds:(NSString *)keyword
         completion:(void (^)(NSArray<TBFinanceFundInfo *> *funds, NSError *_Nullable error))completion;

/// 基金详情
- (void)fetchFundInfo:(NSString *)fundCode
           completion:(void (^)(TBFinanceFundInfo *_Nullable info, NSError *_Nullable error))completion;

/// 基金历史净值（每项：fsrq 日期 / dwjz 单位净值 / jzzzl 日增长率）
- (void)fetchFundNavHistory:(NSString *)fundCode
                     limit:(NSInteger)limit
                completion:(void (^)(NSArray<NSDictionary *> *rows, NSError *_Nullable error))completion;

#pragma mark 期权（新浪链路）

/// 期权标的列表（内置常见 ETF 期权：50ETF/300ETF/500ETF/科创50）
- (void)fetchOptionUnderlyings:(void (^)(NSArray<NSDictionary *> *items, NSError *_Nullable error))completion;

/// 某标的某月份的期权合约链（isCall=NO 为认沽）
/// @param underlying 如 510300；@param month 如 202612
- (void)fetchOptionChain:(NSString *)underlying
                   month:(NSString *)month
                   isCall:(BOOL)isCall
               completion:(void (^)(NSArray<TBFinanceOptionInfo *> *contracts, NSError *_Nullable error))completion;

#pragma mark 内置数据

/// 各分类 tab 的默认标的（真实 secid，非 mock——数据全部来自公开接口实时返回）
+ (NSArray<NSString *> *)defaultSecidsForCategory:(TBFinanceCategory)category;

@end

NS_ASSUME_NONNULL_END
