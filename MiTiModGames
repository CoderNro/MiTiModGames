#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// ═══════════════════════════════════════════
//  HUD — FPS + Pin + Tên thiết bị
// ═══════════════════════════════════════════

@interface MiTiHUD : NSObject
+ (void)start;
@end

@implementation MiTiHUD {
    CADisplayLink *_displayLink;
    NSInteger      _frameCount;
    CFTimeInterval _lastTime;
    UIWindow      *_hudWindow;
    UILabel       *_hudLabel;
}

+ (instancetype)shared {
    static MiTiHUD *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MiTiHUD new]; });
    return s;
}

+ (void)start { [[self shared] setup]; }

- (void)setup {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;

    CGRect screen = [UIScreen mainScreen].bounds;

    _hudWindow = [[UIWindow alloc] initWithWindowScene:scene];
    _hudWindow.windowLevel = UIWindowLevelAlert + 300;
    _hudWindow.backgroundColor = [UIColor clearColor];
    _hudWindow.userInteractionEnabled = NO;
    _hudWindow.rootViewController = [[UIViewController alloc] init];
    _hudWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
    [_hudWindow makeKeyAndVisible];

    // HUD bar
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 44, screen.size.width, 22)];
    bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    [_hudWindow.rootViewController.view addSubview:bar];

    _hudLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, screen.size.width - 16, 22)];
    _hudLabel.font = [UIFont boldSystemFontOfSize:10];
    _hudLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.4 alpha:1];
    _hudLabel.text = @"@Copyright:MiTiModGames";
    [bar addSubview:_hudLabel];

    // Bật pin monitoring
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    // DisplayLink đếm FPS
    _frameCount = 0;
    _lastTime   = CACurrentMediaTime();
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)link {
    _frameCount++;
    CFTimeInterval now  = CACurrentMediaTime();
    CFTimeInterval diff = now - _lastTime;

    if (diff >= 1.0) {
        NSInteger fps = (NSInteger)round(_frameCount / diff);
        _frameCount = 0;
        _lastTime   = now;

        // Pin
        float battery = [UIDevice currentDevice].batteryLevel * 100;
        NSString *batStr = battery < 0
            ? @"N/A"
            : [NSString stringWithFormat:@"%.0f%%", battery];

        // Tên thiết bị
        NSString *device = [UIDevice currentDevice].name;

        // FPS màu theo mức
        UIColor *fpsColor;
        if (fps >= 55)      fpsColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.3 alpha:1]; // xanh
        else if (fps >= 30) fpsColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1]; // vàng
        else                fpsColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1]; // đỏ

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *text = [NSString stringWithFormat:
                @"©MiTiModGames  FPS:%ld  🔋%@  📱%@  Zalo:0559919099",
                (long)fps, batStr, device];

            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:text];
            NSRange fpsRange = [text rangeOfString:[NSString stringWithFormat:@"FPS:%ld", (long)fps]];
            if (fpsRange.location != NSNotFound)
                [attr addAttribute:NSForegroundColorAttributeName value:fpsColor range:fpsRange];
            [attr addAttribute:NSForegroundColorAttributeName
                         value:[UIColor colorWithRed:0.4 green:1.0 blue:0.4 alpha:1]
                         range:NSMakeRange(0, text.length)];
            if (fpsRange.location != NSNotFound)
                [attr addAttribute:NSForegroundColorAttributeName value:fpsColor range:fpsRange];

            self->_hudLabel.attributedText = attr;
        });
    }
}

@end

// ═══════════════════════════════════════════
//  MENU — MiTiModGames
// ═══════════════════════════════════════════

@interface MiTiModGamesMenu : NSObject
+ (void)show;
@end

@implementation MiTiModGamesMenu

+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        if (!scene) return;

        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat cardW = MIN(screen.size.width - 60, 300);
        CGFloat cardH = 340;
        CGFloat cardX = (screen.size.width - cardW) / 2;
        CGFloat cardY = (screen.size.height - cardH) / 2;

        UIWindow *win = [[UIWindow alloc] initWithWindowScene:scene];
        win.windowLevel = UIWindowLevelAlert + 200;
        win.backgroundColor = [UIColor clearColor];
        win.rootViewController = [[UIViewController alloc] init];
        win.rootViewController.view.backgroundColor = [UIColor clearColor];
        [win makeKeyAndVisible];

        UIView *dim = [[UIView alloc] initWithFrame:screen];
        dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
        [win.rootViewController.view addSubview:dim];

        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, screen.size.height, cardW, cardH)];
        card.layer.cornerRadius  = 22;
        card.layer.masksToBounds = NO;
        card.layer.shadowColor   = [UIColor colorWithRed:0.4 green:0.1 blue:1.0 alpha:0.6].CGColor;
        card.layer.shadowOffset  = CGSizeMake(0, 8);
        card.layer.shadowRadius  = 24;
        card.layer.shadowOpacity = 1;

        UIView *cardBg = [[UIView alloc] initWithFrame:CGRectMake(0,0,cardW,cardH)];
        cardBg.layer.cornerRadius = 22;
        cardBg.clipsToBounds = YES;
        CAGradientLayer *bg = [CAGradientLayer layer];
        bg.frame  = cardBg.bounds;
        bg.colors = @[
            (__bridge id)[UIColor colorWithRed:0.06 green:0.06 blue:0.16 alpha:0.97].CGColor,
            (__bridge id)[UIColor colorWithRed:0.10 green:0.06 blue:0.22 alpha:0.97].CGColor,
        ];
        bg.startPoint = CGPointMake(0,0); bg.endPoint = CGPointMake(1,1);
        [cardBg.layer insertSublayer:bg atIndex:0];
        [card addSubview:cardBg];
        [win.rootViewController.view addSubview:card];

        CAGradientLayer *accent = [CAGradientLayer layer];
        accent.frame  = CGRectMake(0,0,cardW,3);
        accent.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:1.0 green:0.3 blue:0.6 alpha:1].CGColor,
        ];
        accent.startPoint = CGPointMake(0,0); accent.endPoint = CGPointMake(1,0);
        [cardBg.layer addSublayer:accent];

        UIView *logo = [[UIView alloc] initWithFrame:CGRectMake((cardW-48)/2,16,48,48)];
        logo.layer.cornerRadius = 24; logo.clipsToBounds = YES;
        CAGradientLayer *lg = [CAGradientLayer layer];
        lg.frame  = logo.bounds;
        lg.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
        ];
        lg.startPoint = CGPointMake(0,0); lg.endPoint = CGPointMake(1,1);
        [logo.layer insertSublayer:lg atIndex:0];
        UILabel *ll = [[UILabel alloc] initWithFrame:logo.bounds];
        ll.text = @"🎮"; ll.font = [UIFont systemFontOfSize:22]; ll.textAlignment = NSTextAlignmentCenter;
        [logo addSubview:ll]; [cardBg addSubview:logo];

        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @1.0; pulse.toValue = @1.1; pulse.duration = 0.9;
        pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        [logo.layer addAnimation:pulse forKey:@"pulse"];

        UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(0,70,cardW,22)];
        titleLbl.text = @"MiTiModGames"; titleLbl.textAlignment = NSTextAlignmentCenter;
        titleLbl.font = [UIFont boldSystemFontOfSize:17]; titleLbl.textColor = [UIColor whiteColor];
        [cardBg addSubview:titleLbl];

        UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(0,94,cardW,16)];
        subLbl.text = @"Kênh chia sẻ mod & game"; subLbl.textAlignment = NSTextAlignmentCenter;
        subLbl.font = [UIFont systemFontOfSize:11]; subLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1];
        [cardBg addSubview:subLbl];

        UIView *div = [[UIView alloc] initWithFrame:CGRectMake(16,116,cardW-32,1)];
        div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
        [cardBg addSubview:div];

        NSArray *links = @[
            @{@"icon":@"▶️",@"title":@"YouTube", @"sub":@"@ymt139",    @"url":@"https://www.youtube.com/@ymt139",
              @"r1":@0.9f,@"g1":@0.1f,@"b1":@0.1f,@"r2":@1.0f,@"g2":@0.3f,@"b2":@0.1f},
            @{@"icon":@"🎵",@"title":@"TikTok",  @"sub":@"@yel123321",@"url":@"https://www.tiktok.com/@yel123321",
              @"r1":@0.1f,@"g1":@0.1f,@"b1":@0.1f,@"r2":@0.3f,@"g2":@0.3f,@"b2":@0.3f},
            @{@"icon":@"💬",@"title":@"Zalo",    @"sub":@"0559919099",@"url":@"https://zalo.me/0559919099",
              @"r1":@0.0f,@"g1":@0.4f,@"b1":@0.9f,@"r2":@0.0f,@"g2":@0.6f,@"b2":@1.0f},
        ];

        CGFloat rowY = 124;
        for (NSDictionary *item in links) {
            NSString *capturedURL = item[@"url"];
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(12,rowY,cardW-24,52);
            row.layer.cornerRadius = 13; row.clipsToBounds = YES;
            row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];

            UIView *iconBg = [[UIView alloc] initWithFrame:CGRectMake(10,9,34,34)];
            iconBg.layer.cornerRadius = 10; iconBg.clipsToBounds = YES;
            CAGradientLayer *ig = [CAGradientLayer layer];
            ig.frame  = iconBg.bounds;
            ig.colors = @[
                (__bridge id)[UIColor colorWithRed:[item[@"r1"] floatValue] green:[item[@"g1"] floatValue] blue:[item[@"b1"] floatValue] alpha:0.9].CGColor,
                (__bridge id)[UIColor colorWithRed:[item[@"r2"] floatValue] green:[item[@"g2"] floatValue] blue:[item[@"b2"] floatValue] alpha:0.9].CGColor,
            ];
            ig.startPoint = CGPointMake(0,0); ig.endPoint = CGPointMake(1,1);
            [iconBg.layer insertSublayer:ig atIndex:0];
            UILabel *iconL = [[UILabel alloc] initWithFrame:iconBg.bounds];
            iconL.text = item[@"icon"]; iconL.font = [UIFont systemFontOfSize:15];
            iconL.textAlignment = NSTextAlignmentCenter;
            [iconBg addSubview:iconL]; [row addSubview:iconBg];

            UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(52,8,cardW-90,20)];
            tl.text = item[@"title"]; tl.textColor = [UIColor whiteColor];
            tl.font = [UIFont boldSystemFontOfSize:14]; [row addSubview:tl];

            UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(52,28,cardW-90,15)];
            sl.text = item[@"sub"]; sl.textColor = [UIColor colorWithWhite:0.45 alpha:1];
            sl.font = [UIFont systemFontOfSize:11]; [row addSubview:sl];

            UILabel *arr = [[UILabel alloc] initWithFrame:CGRectMake(cardW-38,14,20,24)];
            arr.text = @"›"; arr.textColor = [UIColor colorWithWhite:0.35 alpha:1];
            arr.font = [UIFont boldSystemFontOfSize:20]; [row addSubview:arr];

            objc_setAssociatedObject(row, "openBlock", ^{ 
                NSURL *url = [NSURL URLWithString:capturedURL];
                if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [row addTarget:row action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
            [cardBg addSubview:row];
            rowY += 58;
        }

        // Countdown bar
        UIView *barBg = [[UIView alloc] initWithFrame:CGRectMake(16,cardH-40,cardW-32,4)];
        barBg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
        barBg.layer.cornerRadius = 2;
        [cardBg addSubview:barBg];

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,cardW-32,4)];
        bar.layer.cornerRadius = 2; bar.clipsToBounds = YES;
        CAGradientLayer *barG = [CAGradientLayer layer];
        barG.frame = bar.bounds;
        barG.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
        ];
        barG.startPoint = CGPointMake(0,0); barG.endPoint = CGPointMake(1,0);
        [bar.layer insertSublayer:barG atIndex:0];
        [barBg addSubview:bar];

        UILabel *countLbl = [[UILabel alloc] initWithFrame:CGRectMake(0,cardH-32,cardW,16)];
        countLbl.text = @"Tự đóng sau 10 giây";
        countLbl.textAlignment = NSTextAlignmentCenter;
        countLbl.font = [UIFont systemFontOfSize:10];
        countLbl.textColor = [UIColor colorWithWhite:0.35 alpha:1];
        [cardBg addSubview:countLbl];

        [UIView animateWithDuration:0.08 animations:^{
            dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        }];
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75
              initialSpringVelocity:0.5 options:0 animations:^{
            card.frame = CGRectMake(cardX,cardY,cardW,cardH);
        } completion:nil];

        void (^closeMenu)(void) = ^{
            [UIView animateWithDuration:0.28 animations:^{
                card.alpha = 0;
                card.transform = CGAffineTransformMakeScale(0.92,0.92);
                dim.backgroundColor = [UIColor clearColor];
            } completion:^(BOOL d){ win.hidden = YES; }];
        };

        __block NSInteger sec = 10;
        CGFloat totalW = cardW - 32;
        NSTimer *tmr = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            sec--;
            dispatch_async(dispatch_get_main_queue(), ^{
                countLbl.text = [NSString stringWithFormat:@"Tự đóng sau %ld giây", (long)sec];
                [UIView animateWithDuration:0.8 animations:^{
                    bar.frame = CGRectMake(0,0,totalW * MAX(0,sec/10.0),4);
                }];
                if (sec <= 0) { [t invalidate]; closeMenu(); }
            });
        }];
        [[NSRunLoop mainRunLoop] addTimer:tmr forMode:NSRunLoopCommonModes];

        UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
        [dimTap addTarget:^(__unused id x){ [tmr invalidate]; closeMenu(); } action:@selector(invoke)];
        [dim addGestureRecognizer:dimTap];
    });
}

@end

@implementation UIButton (MiTiTap)
- (void)handleTap {
    void (^block)(void) = objc_getAssociatedObject(self, "openBlock");
    if (block) block();
}
@end

// ── Constructor ──
__attribute__((constructor))
static void MiTiModGamesInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [MiTiHUD start];
        [MiTiModGamesMenu show];
    });
}
