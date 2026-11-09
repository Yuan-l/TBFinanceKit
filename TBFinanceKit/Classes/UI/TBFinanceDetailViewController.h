//
//  TBFinanceDetailViewController.h
//  TBFinanceKit
//
//  标的详情页：实时价格（轮询刷新）+ 关键行情 + 公司信息 + K线（日/周/月）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 详情页展示的标的信息（由列表页传入）
@interface TBFinanceTarget : NSObject
@property (nonatomic, copy) NSString *secid;   // 东财 secid
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
/// 附加类型：0 股票/指数 1 基金 2 期权
@property (nonatomic, assign) NSInteger kind;
/// 基金代码 / 期权合约代码（kind>0 时使用）
@property (nonatomic, copy, nullable) NSString *extraCode;
@end

@interface TBFinanceDetailViewController : UIViewController
- (instancetype)initWithTarget:(TBFinanceTarget *)target;
@end

NS_ASSUME_NONNULL_END
