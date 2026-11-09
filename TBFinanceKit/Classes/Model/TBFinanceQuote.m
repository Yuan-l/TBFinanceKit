//
//  TBFinanceQuote.m
//  TBFinanceKit
//

#import "TBFinanceQuote.h"

@implementation TBFinanceQuote

- (BOOL)isRising   { return self.changePercent > 0.005; }
- (BOOL)isFalling  { return self.changePercent < -0.005; }

@end
