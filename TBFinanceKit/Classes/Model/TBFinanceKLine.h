//
//  TBFinanceKLine.h
//  TBFinanceKit
//
//  K 线数据模型 + 周期枚举
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// K 线周期
typedef NS_ENUM(NSInteger, TBFinanceKLinePeriod) {
    TBFinanceKLinePeriodDay   = 101,   // 日 K
    TBFinanceKLinePeriodWeek  = 102,   // 周 K
    TBFinanceKLinePeriodMonth = 103,   // 月 K
};

@interface TBFinanceKLineItem : NSObject
/// 日期 yyyy-MM-dd
@property (nonatomic, copy) NSString *date;
@property (nonatomic, assign) double open;
@property (nonatomic, assign) double close;
@property (nonatomic, assign) double high;
@property (nonatomic, assign) double low;
/// 成交量（手）
@property (nonatomic, assign) double volume;
/// 成交额（元）
@property (nonatomic, assign) double turnover;
/// 相对上一根收盘的涨跌（首根用昨收算，无昨收为 0）
@property (nonatomic, assign) double changePercent;
@end

@interface TBFinanceKLine : NSObject
@property (nonatomic, copy) NSString *secid;
@property (nonatomic, copy) NSString *name;
/// 昨收（首根涨跌基准）
@property (nonatomic, assign) double preKPrice;
@property (nonatomic, copy) NSArray<TBFinanceKLineItem *> *items;
@end

NS_ASSUME_NONNULL_END
