//
//  TBFinanceQuote.h
//  TBFinanceKit
//
//  标的实时行情模型（股票 / 指数 / 港美股 / 板块 / 期权 / 基金通用）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBFinanceQuote : NSObject

/// 东财 secid，如 1.600519 / 116.00700 / 105.AAPL / 100.NDX
@property (nonatomic, copy) NSString *secid;
/// 标的代码（600519 / 00700 / AAPL）
@property (nonatomic, copy) NSString *code;
/// 标的名称
@property (nonatomic, copy) NSString *name;
/// 市场（东财 f13：1沪 0深 116港 105美股 100全球指数）
@property (nonatomic, assign) NSInteger market;

/// 最新价（基金为净值）
@property (nonatomic, assign) double price;
/// 涨跌额
@property (nonatomic, assign) double change;
/// 涨跌幅（%）
@property (nonatomic, assign) double changePercent;
/// 昨收
@property (nonatomic, assign) double preClose;
/// 成交额（元，可能为 0 = 无该字段）
@property (nonatomic, assign) double turnover;
/// 行情时间文本（可能为空）
@property (nonatomic, copy, nullable) NSString *timeText;

- (BOOL)isRising;
- (BOOL)isFalling;

@end

NS_ASSUME_NONNULL_END
