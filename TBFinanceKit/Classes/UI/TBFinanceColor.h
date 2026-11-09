//
//  TBFinanceColor.h
//  TBFinanceKit
//
//  行情配色：A股习惯红涨绿跌
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBFinanceColor : NSObject
+ (UIColor *)rising;    // 涨 - 红
+ (UIColor *)falling;   // 跌 - 绿
+ (UIColor *)flat;      // 平 - 灰
+ (UIColor *)colorForPercent:(double)percent;
@end

NS_ASSUME_NONNULL_END
