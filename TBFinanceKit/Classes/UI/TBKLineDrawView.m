//
//  TBKLineDrawView.m
//  TBFinanceKit
//
//  绘制布局：
//  ┌──────────────────────┐
//  │  蜡烛区（高 72%）    │
//  ├──────────────────────┤
//  │  成交量区（高 20%）  │
//  ├──────────────────────┤
//  │  日期轴（高 8%）     │
//  └──────────────────────┘
//  长按显示十字光标 + OHLC 浮层由外部联动
//

#import "TBKLineDrawView.h"

static CGFloat const kCandleAreaRatio = 0.70;
static CGFloat const kVolumeAreaRatio = 0.22;
static CGFloat const kAxisAreaRatio   = 0.08;
static CGFloat const kRightPadding    = 52.0;   // 右侧价格刻度区

@interface TBKLineDrawView ()
@property (nonatomic, strong) TBFinanceKLine *kline;
@property (nonatomic, assign) NSUInteger selectIndex;
@end

@implementation TBKLineDrawView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor whiteColor];
        self.contentMode = UIViewContentModeRedraw;
        // 长按十字光标
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.15;
        [self addGestureRecognizer:lp];
        _selectIndex = NSNotFound;
    }
    return self;
}

- (void)reloadWithKLine:(TBFinanceKLine *)kline {
    self.kline = kline;
    self.selectIndex = NSNotFound;
    [self setNeedsDisplay];
}

#pragma mark - 手势

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (!self.kline.items.count) return;
    CGPoint p = [g locationInView:self];
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateBegan) {
        CGFloat plotW = self.bounds.size.width - kRightPadding;
        if (p.x < 0 || p.x > plotW) return;
        NSUInteger idx = p.x / plotW * self.kline.items.count;
        idx = MIN(idx, self.kline.items.count - 1);
        if (idx != self.selectIndex) {
            _selectIndex = idx;
            [self setNeedsDisplay];
            if (self.onSelectItem) self.onSelectItem(self.kline.items[idx]);
        }
    } else if (g.state == UIGestureRecognizerStateEnded) {
        _selectIndex = NSNotFound;
        [self setNeedsDisplay];
        if (self.onClearSelect) self.onClearSelect();
    }
}

#pragma mark - 绘制

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    NSArray<TBFinanceKLineItem *> *items = self.kline.items;
    if (!items.count) {
        [@"加载中…" drawAtPoint:CGPointMake(rect.size.width / 2 - 30, rect.size.height / 2)
                 withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14],
                                  NSForegroundColorAttributeName: [UIColor lightGrayColor]}];
        return;
    }

    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;
    CGFloat plotW = w - kRightPadding;
    CGFloat candleH = h * kCandleAreaRatio;
    CGFloat volumeY = h * (kCandleAreaRatio + kAxisAreaRatio) + 6;
    CGFloat volumeH = h * kVolumeAreaRatio - 6;
    CGFloat axisY = h - h * kAxisAreaRatio;

    // 数据范围
    double minP = DBL_MAX, maxP = -DBL_MAX, maxV = 0;
    for (TBFinanceKLineItem *it in items) {
        minP = MIN(minP, it.low);
        maxP = MAX(maxP, it.high);
        maxV = MAX(maxV, it.volume);
    }
    if (minP >= maxP) { maxP = minP + 1; }
    CGFloat pad = (maxP - minP) * 0.06;
    minP -= pad; maxP += pad;

    CGFloat cw = plotW / items.count;          // 每根蜡烛宽度
    CGFloat bodyW = MAX(cw * 0.65, 1.0);

    // 价格 → y
    CGFloat (^py)(double) = ^(double p) {
        return candleH - (p - minP) / (maxP - minP) * candleH + 4;
    };

    // 网格线 + 价格刻度
    UIFont *tickFont = [UIFont systemFontOfSize:9];
    [@[UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1] enumerateObjectsUsingBlock:^(id c, NSUInteger i, BOOL *s){}];
    for (int i = 0; i <= 4; i++) {
        double price = maxP - (maxP - minP) * i / 4.0;
        CGFloat y = py(price);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1].CGColor);
        CGContextMoveToPoint(ctx, 0, y);
        CGContextAddLineToPoint(ctx, plotW, y);
        CGContextStrokePath(ctx);
        NSString *label = [NSString stringWithFormat:@"%.2f", price];
        [label drawAtPoint:CGPointMake(plotW + 4, y - 6)
            withAttributes:@{NSFontAttributeName: tickFont,
                             NSForegroundColorAttributeName: [UIColor grayColor]}];
    }

    // 蜡烛 + 成交量
    UIColor *upColor = [UIColor colorWithRed:0.88 green:0.19 blue:0.19 alpha:1];   // 红涨（收盘>=开盘）
    UIColor *downColor = [UIColor colorWithRed:0.10 green:0.62 blue:0.35 alpha:1]; // 绿跌

    for (NSUInteger i = 0; i < items.count; i++) {
        TBFinanceKLineItem *it = items[i];
        BOOL up = it.close >= it.open;
        UIColor *c = up ? upColor : downColor;
        CGFloat x = i * cw + (cw - bodyW) / 2;
        CGFloat cx = i * cw + cw / 2;

        // 影线
        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextMoveToPoint(ctx, cx, py(it.high));
        CGContextAddLineToPoint(ctx, cx, py(it.low));
        CGContextStrokePath(ctx);

        // 实体
        CGFloat top = py(MAX(it.open, it.close));
        CGFloat bh = MAX(fabs(py(it.open) - py(it.close)), 1.0);
        CGContextSetFillColorWithColor(ctx, c.CGColor);
        CGContextFillRect(ctx, CGRectMake(x, top, bodyW, bh));

        // 成交量
        CGFloat vh = maxV > 0 ? it.volume / maxV * volumeH : 0;
        CGContextFillRect(ctx, CGRectMake(x, volumeY + volumeH - vh, bodyW, vh));

        // 日期轴（均取 5 个点）
        NSUInteger step = MAX(items.count / 5, 1);
        if (i % step == 0) {
            NSString *d = it.date.length >= 10 ? [it.date substringFromIndex:5] : it.date;
            CGSize sz = [d sizeWithAttributes:@{NSFontAttributeName: tickFont}];
            [d drawAtPoint:CGPointMake(MAX(cx - sz.width / 2, 0), axisY + 4)
              withAttributes:@{NSFontAttributeName: tickFont,
                               NSForegroundColorAttributeName: [UIColor grayColor]}];
        }
    }

    // 十字光标
    if (self.selectIndex != NSNotFound && self.selectIndex < items.count) {
        TBFinanceKLineItem *it = items[self.selectIndex];
        CGFloat cx = self.selectIndex * cw + cw / 2;
        CGFloat cy = py(it.close);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.3 green:0.3 blue:0.75 alpha:1].CGColor);
        CGContextSetLineDash(ctx, 0, (CGFloat[]){4, 3}, 2);
        CGContextMoveToPoint(ctx, cx, 0); CGContextAddLineToPoint(ctx, cx, candleH + 4);
        CGContextMoveToPoint(ctx, 0, cy); CGContextAddLineToPoint(ctx, plotW, cy);
        CGContextStrokePath(ctx);
        CGContextSetLineDash(ctx, 0, NULL, 0);

        // 价格气泡
        NSString *pText = [NSString stringWithFormat:@"%.2f", it.close];
        CGSize tsz = [pText sizeWithAttributes:@{NSFontAttributeName: tickFont}];
        CGRect bubble = CGRectMake(plotW, cy - 9, tsz.width + 8, 18);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.3 green:0.3 blue:0.75 alpha:1].CGColor);
        CGContextFillRect(ctx, bubble);
        [pText drawAtPoint:CGPointMake(bubble.origin.x + 4, cy - 6.5)
             withAttributes:@{NSFontAttributeName: tickFont,
                              NSForegroundColorAttributeName: [UIColor whiteColor]}];
    }
}

@end
