#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// ═══════════════════════════════════════════
//  MiTiModGames — Floating Menu
// ═══════════════════════════════════════════

@interface MiTiModGamesMenu : NSObject
+ (void)show;
@end

@implementation MiTiModGamesMenu

+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) return;

        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat cardW = MIN(screen.size.width - 40, 340);
        CGFloat cardH = 480;
        CGFloat cardX = (screen.size.width - cardW) / 2;
        CGFloat cardY = (screen.size.height - cardH) / 2;

        // ── Window ──
        UIWindow *win = [[UIWindow alloc] initWithWindowScene:scene];
        win.windowLevel = UIWindowLevelAlert + 200;
        win.backgroundColor = [UIColor clearColor];
        win.rootViewController = [[UIViewController alloc] init];
        win.rootViewController.view.backgroundColor = [UIColor clearColor];
        [win makeKeyAndVisible];

        // ── Dim overlay ──
        UIView *dim = [[UIView alloc] initWithFrame:screen];
        dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
        [win.rootViewController.view addSubview:dim];

        // ── Card ──
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, screen.size.height, cardW, cardH)];
        card.layer.cornerRadius = 26;
        card.clipsToBounds = NO;
        card.layer.masksToBounds = NO;
        card.layer.shadowColor = [UIColor colorWithRed:0.4 green:0.1 blue:1.0 alpha:0.7].CGColor;
        card.layer.shadowOffset = CGSizeMake(0, 12);
        card.layer.shadowRadius = 30;
        card.layer.shadowOpacity = 1;

        // Card background gradient
        UIView *cardBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardW, cardH)];
        cardBg.layer.cornerRadius = 26;
        cardBg.clipsToBounds = YES;
        CAGradientLayer *bg = [CAGradientLayer layer];
        bg.frame = cardBg.bounds;
        bg.colors = @[
            (__bridge id)[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.97].CGColor,
            (__bridge id)[UIColor colorWithRed:0.08 green:0.05 blue:0.20 alpha:0.97].CGColor,
        ];
        bg.startPoint = CGPointMake(0, 0);
        bg.endPoint   = CGPointMake(1, 1);
        [cardBg.layer insertSublayer:bg atIndex:0];
        [card addSubview:cardBg];
        [win.rootViewController.view addSubview:card];

        // ── Top accent line ──
        CAGradientLayer *accent = [CAGradientLayer layer];
        accent.frame  = CGRectMake(0, 0, cardW, 3);
        accent.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:1.0 green:0.3 blue:0.6 alpha:1].CGColor,
        ];
        accent.startPoint = CGPointMake(0, 0);
        accent.endPoint   = CGPointMake(1, 0);
        [cardBg.layer addSublayer:accent];

        // ── Header ──
        // Logo circle
        UIView *logo = [[UIView alloc] initWithFrame:CGRectMake((cardW-60)/2, 20, 60, 60)];
        logo.layer.cornerRadius = 30;
        logo.clipsToBounds = YES;
        CAGradientLayer *logoGrad = [CAGradientLayer layer];
        logoGrad.frame  = logo.bounds;
        logoGrad.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
        ];
        logoGrad.startPoint = CGPointMake(0, 0);
        logoGrad.endPoint   = CGPointMake(1, 1);
        [logo.layer insertSublayer:logoGrad atIndex:0];

        UILabel *logoLbl = [[UILabel alloc] initWithFrame:logo.bounds];
        logoLbl.text          = @"🎮";
        logoLbl.font          = [UIFont systemFontOfSize:28];
        logoLbl.textAlignment = NSTextAlignmentCenter;
        [logo addSubview:logoLbl];
        [cardBg addSubview:logo];

        // Pulse animation on logo
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue    = @1.0;
        pulse.toValue      = @1.12;
        pulse.duration     = 0.9;
        pulse.autoreverses = YES;
        pulse.repeatCount  = HUGE_VALF;
        [logo.layer addAnimation:pulse forKey:@"pulse"];

        // Title
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 88, cardW, 26)];
        title.text          = @"MiTiModGames";
        title.textAlignment = NSTextAlignmentCenter;
        title.font          = [UIFont boldSystemFontOfSize:20];
        title.textColor     = [UIColor whiteColor];
        [cardBg addSubview:title];

        // Subtitle
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0, 116, cardW, 18)];
        sub.text          = @"Kênh chia sẻ mod & game";
        sub.textAlignment = NSTextAlignmentCenter;
        sub.font          = [UIFont systemFontOfSize:12];
        sub.textColor     = [UIColor colorWithWhite:0.55 alpha:1];
        [cardBg addSubview:sub];

        // Divider
        UIView *div = [[UIView alloc] initWithFrame:CGRectMake(20, 142, cardW-40, 1)];
        div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
        [cardBg addSubview:div];

        // ── Link rows ──
        NSArray *links = @[
            @{ @"icon": @"▶️", @"title": @"YouTube",  @"sub": @"@ymt139",          @"url": @"https://www.youtube.com/@ymt139",                          @"c1": @[@0.9,@0.1,@0.1], @"c2": @[@1.0,@0.4,@0.1] },
            @{ @"icon": @"🎵", @"title": @"TikTok",   @"sub": @"@yel123321",        @"url": @"https://www.tiktok.com/@yel123321?r=1&t=ZS-944JwG88i0a",  @"c1": @[@0.0,@0.0,@0.0], @"c2": @[@0.2,@0.2,@0.2] },
            @{ @"icon": @"💬", @"title": @"Zalo",     @"sub": @"0559919099",        @"url": @"https://zalo.me/0559919099",                              @"c1": @[@0.0,@0.4,@0.9], @"c2": @[@0.0,@0.6,@1.0] },
        ];

        CGFloat rowY = 154;
        for (NSDictionary *item in links) {
            NSArray *c1 = item[@"c1"], *c2 = item[@"c2"];

            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(16, rowY, cardW-32, 62);
            row.layer.cornerRadius = 16;
            row.clipsToBounds = YES;

            CAGradientLayer *rowBg = [CAGradientLayer layer];
            rowBg.frame  = row.bounds;
            rowBg.colors = @[
                (__bridge id)[UIColor colorWithWhite:1 alpha:0.06].CGColor,
                (__bridge id)[UIColor colorWithWhite:1 alpha:0.03].CGColor,
            ];
            rowBg.startPoint = CGPointMake(0,0);
            rowBg.endPoint   = CGPointMake(1,1);
            [row.layer insertSublayer:rowBg atIndex:0];

            // Icon bg
            UIView *iconBg = [[UIView alloc] initWithFrame:CGRectMake(12, 12, 38, 38)];
            iconBg.layer.cornerRadius = 12;
            iconBg.clipsToBounds = YES;
            CAGradientLayer *ig = [CAGradientLayer layer];
            ig.frame  = iconBg.bounds;
            ig.colors = @[
                (__bridge id)[UIColor colorWithRed:[c1[0] floatValue] green:[c1[1] floatValue] blue:[c1[2] floatValue] alpha:0.8].CGColor,
                (__bridge id)[UIColor colorWithRed:[c2[0] floatValue] green:[c2[1] floatValue] blue:[c2[2] floatValue] alpha:0.8].CGColor,
            ];
            ig.startPoint = CGPointMake(0,0);
            ig.endPoint   = CGPointMake(1,1);
            [iconBg.layer insertSublayer:ig atIndex:0];

            UILabel *iconL = [[UILabel alloc] initWithFrame:iconBg.bounds];
            iconL.text          = item[@"icon"];
            iconL.font          = [UIFont systemFontOfSize:18];
            iconL.textAlignment = NSTextAlignmentCenter;
            [iconBg addSubview:iconL];
            [row addSubview:iconBg];

            UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(60, 10, cardW-110, 22)];
            tl.text      = item[@"title"];
            tl.textColor = [UIColor whiteColor];
            tl.font      = [UIFont boldSystemFontOfSize:15];
            [row addSubview:tl];

            UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(60, 32, cardW-110, 18)];
            sl.text      = item[@"sub"];
            sl.textColor = [UIColor colorWithWhite:0.5 alpha:1];
            sl.font      = [UIFont systemFontOfSize:12];
            [row addSubview:sl];

            UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectMake(cardW-52, 18, 24, 26)];
            arrow.text      = @"›";
            arrow.textColor = [UIColor colorWithWhite:0.35 alpha:1];
            arrow.font      = [UIFont boldSystemFontOfSize:22];
            [row addSubview:arrow];

            NSString *urlStr = item[@"url"];
            [row addTarget:[NSObject new] action:nil forControlEvents:0];
            objc_setAssociatedObject(row, "url", urlStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // Touch highlight
            [row addTarget:nil action:@selector(highlightRow:) forControlEvents:UIControlEventTouchDown];
            [row addTarget:nil action:@selector(openURL:) forControlEvents:UIControlEventTouchUpInside];

            [cardBg addSubview:row];
            rowY += 70;
        }

        // ── Countdown bar ──
        UIView *barBg = [[UIView alloc] initWithFrame:CGRectMake(20, cardH-52, cardW-40, 6)];
        barBg.backgroundColor    = [UIColor colorWithWhite:1 alpha:0.08];
        barBg.layer.cornerRadius = 3;
        [cardBg addSubview:barBg];

        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardW-40, 6)];
        bar.layer.cornerRadius = 3;
        bar.clipsToBounds = YES;
        CAGradientLayer *barGrad = [CAGradientLayer layer];
        barGrad.frame  = bar.bounds;
        barGrad.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
        ];
        barGrad.startPoint = CGPointMake(0,0);
        barGrad.endPoint   = CGPointMake(1,0);
        [bar.layer insertSublayer:barGrad atIndex:0];
        [barBg addSubview:bar];

        // Countdown label
        UILabel *countLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, cardH-44, cardW, 18)];
        countLbl.text          = @"Tự đóng sau 10 giây";
        countLbl.textAlignment = NSTextAlignmentCenter;
        countLbl.font          = [UIFont systemFontOfSize:11];
        countLbl.textColor     = [UIColor colorWithWhite:0.4 alpha:1];
        [cardBg addSubview:countLbl];

        // ── Animate in ──
        [UIView animateWithDuration:0.08 animations:^{
            dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        }];
        [UIView animateWithDuration:0.5 delay:0
             usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            card.frame = CGRectMake(cardX, cardY, cardW, cardH);
        } completion:nil];

        // ── Countdown 10s ──
        __block NSInteger sec = 10;
        __block CALayer *barLayer = bar.layer;
        __block UILabel *cntRef   = countLbl;
        __block UIView  *barRef   = bar;

        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            sec--;
            dispatch_async(dispatch_get_main_queue(), ^{
                cntRef.text = [NSString stringWithFormat:@"Tự đóng sau %ld giây", (long)sec];

                // Shrink bar
                CGFloat ratio = sec / 10.0;
                [UIView animateWithDuration:0.8 animations:^{
                    barRef.frame = CGRectMake(0, 0, (cardW-40) * ratio, 6);
                    barLayer.frame = CGRectMake(0, 0, (cardW-40) * ratio, 6);
                }];

                if (sec <= 0) {
                    [t invalidate];
                    // Animate out
                    [UIView animateWithDuration:0.35 delay:0
                                        options:UIViewAnimationOptionCurveEaseIn
                                     animations:^{
                        card.alpha = 0;
                        card.transform = CGAffineTransformMakeScale(0.9, 0.9);
                        dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
                    } completion:^(BOOL done) {
                        win.hidden = YES;
                    }];
                }
            });
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];

        // Tap dim to close
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
        [tap addTarget:^(__unused id x) {
            [timer invalidate];
            [UIView animateWithDuration:0.3 animations:^{
                card.alpha = 0;
                card.transform = CGAffineTransformMakeScale(0.9, 0.9);
                dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
            } completion:^(BOOL done) {
                win.hidden = YES;
            }];
        } action:@selector(invoke)];
        [dim addGestureRecognizer:tap];
    });
}

@end

// ── URL open helper ──
@interface MiTiLinkOpener : NSObject
+ (void)open:(NSString *)url;
@end
@implementation MiTiLinkOpener
+ (void)open:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url];
    if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
}
@end

// ── Constructor ──
__attribute__((constructor))
static void MiTiModGamesInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [MiTiModGamesMenu show];
    });
}
