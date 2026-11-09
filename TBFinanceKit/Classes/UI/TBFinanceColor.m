//
//  TBFinanceColor.m
//  TBFinanceKit
//

#import "TBFinanceColor.h"

@implementation TBFinanceColor

+ (UIColor *)rising  { return [UIColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1]; }
+ (UIColor *)falling { return [UIColor colorWithRed:0.10 green:0.62 blue:0.35 alpha:1]; }
+ (UIColor *)flat    { return [UIColor colorWithRed:0.55 green:0.55 blue:0.58 alpha:1]; }

+ (UIColor *)colorForPercent:(double)percent {
    if (percent > 0.005) return [self rising];
    if (percent < -0.005) return [self falling];
    return [self flat];
}

@end
