//
//  TBKLineDrawView.h
//  TBFinanceKit
//
//  Core Graphics 手绘 K 线图（蜡烛 + 成交量柱 + 十字光标），无三方依赖
//

#import <UIKit/UIKit.h>
#import "TBFinanceKLine.h"

NS_ASSUME_NONNULL_BEGIN

@interface TBKLineDrawView : UIView

/// 更新数据并重绘
- (void)reloadWithKLine:(TBFinanceKLine *)kline;

/// 当前选中（长按十字光标）的 K 线索引，未选中为 NSNotFound
@property (nonatomic, assign, readonly) NSUInteger selectedIndex;

/// 选中变化回调（用于详情页顶部联动显示 OHLC）
@property (nonatomic, copy, nullable) void (^onSelectItem)(TBFinanceKLineItem *_Nullable item);

/// 触摸结束后取消选中
@property (nonatomic, copy, nullable) void (^onClearSelect)(void);

@end

NS_ASSUME_NONNULL_END
