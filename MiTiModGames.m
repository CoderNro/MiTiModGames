#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>

// ═══════════════════════════════════════════
//  Link Handler
// ═══════════════════════════════════════════

@interface MiTiLinkHandler : NSObject
+ (instancetype)shared;
- (void)buttonTapped:(UIButton *)sender;
@end

@implementation MiTiLinkHandler
+ (instancetype)shared {
    static MiTiLinkHandler *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MiTiLinkHandler new]; });
    return s;
}
- (void)buttonTapped:(UIButton *)sender {
    NSString *urlStr = objc_getAssociatedObject(sender, "url");
    if (!urlStr) return;
    NSURL *url = [NSURL URLWithString:urlStr];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
@end

// ═══════════════════════════════════════════
//  Memory Patch Utilities
// ═══════════════════════════════════════════

static BOOL patchMemoryBytes(uintptr_t addr, const uint8_t *newBytes, size_t len) {
    mach_port_t task = mach_task_self();
    kern_return_t kr;
    kr = vm_protect(task, (vm_address_t)addr, len, NO,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) return NO;
    memcpy((void *)addr, newBytes, len);
    kr = vm_protect(task, (vm_address_t)addr, len, NO,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    return kr == KERN_SUCCESS;
}

static uintptr_t findPattern(uint32_t imageIndex, const uint8_t *pattern, size_t patLen) {
    const struct mach_header *header = _dyld_get_image_header(imageIndex);
    if (!header) return 0;
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    uint8_t *ptr = (uint8_t *)header;
    uint32_t ncmds = header->ncmds;
    ptr += (header->magic == 0xFEEDFACF) ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    for (uint32_t i = 0; i < ncmds; i++) {
        struct load_command *lc = (struct load_command *)ptr;
        if (lc->cmd == 0x19) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            uintptr_t start = (uintptr_t)(seg->vmaddr + slide);
            uintptr_t end   = start + seg->vmsize;
            for (uintptr_t addr = start; addr + patLen <= end; addr++) {
                if (memcmp((void *)addr, pattern, patLen) == 0) return addr;
            }
        }
        ptr += lc->cmdsize;
    }
    return 0;
}

static uintptr_t findString(const char *str) {
    size_t len = strlen(str);
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        uintptr_t addr = findPattern(i, (const uint8_t *)str, len);
        if (addr) return addr;
    }
    return 0;
}

static BOOL patchString(uintptr_t addr, const char *newStr, size_t originalLen) {
    uint8_t buf[256] = {0};
    size_t newLen = strlen(newStr);
    if (newLen > originalLen) return NO;
    memcpy(buf, newStr, newLen);
    memset(buf + newLen, ' ', originalLen - newLen);
    return patchMemoryBytes(addr, buf, originalLen);
}

// ═══════════════════════════════════════════
//  Patch Functions
// ═══════════════════════════════════════════

// Patch 1: Neckbone_Spine1B → Hipsbone_spine1B
static void applyPatch1(BOOL enable) {
    uintptr_t addr = findString("Neckbone_Spine1B");
    if (!addr) { NSLog(@"[MiTi] Không tìm thấy Neckbone_Spine1B"); return; }
    if (enable)
        patchString(addr, "Hipsbone_spine1B", strlen("Neckbone_Spine1B"));
    else
        patchString(addr, "Neckbone_Spine1B", strlen("Neckbone_Spine1B"));
}

// Patch 2: Hipsbone_LeftToebone → Neckbone_LeftToebone
static void applyPatch2(BOOL enable) {
    uintptr_t addr = findString("Hipsbone_LeftToebone");
    if (!addr) { NSLog(@"[MiTi] Không tìm thấy Hipsbone_LeftToebone"); return; }
    if (enable)
        patchString(addr, "Neckbone_LeftToebone", strlen("Hipsbone_LeftToebone"));
    else
        patchString(addr, "Hipsbone_LeftToebone", strlen("Hipsbone_LeftToebone"));
}

// Patch 3: Xóa "HEAD" - tìm byte 00 47 45 54 (GET) rồi null "HEAD"
static void applyPatch3(BOOL enable) {
    uintptr_t headAddr = findString("HEAD");
    if (!headAddr) { NSLog(@"[MiTi] Không tìm thấy HEAD"); return; }
    if (enable) {
        uint8_t blank[] = {0x20, 0x20, 0x20, 0x20};
        patchMemoryBytes(headAddr, blank, 4);
    } else {
        uint8_t orig[] = {'H','E','A','D'};
        patchMemoryBytes(headAddr, orig, 4);
    }
}

// ═══════════════════════════════════════════
//  HUD — FPS + Pin + Giờ VN + Vị trí
// ═══════════════════════════════════════════

@interface MiTiHUD : NSObject <CLLocationManagerDelegate>
+ (void)start;
@end

@implementation MiTiHUD {
    CADisplayLink     *_displayLink;
    NSInteger          _frameCount;
    CFTimeInterval     _lastTime;
    UIWindow          *_hudWindow;
    UILabel           *_hudLabel;
    NSInteger          _colorIndex;
    CLLocationManager *_locManager;
    NSString          *_cityName;
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

    // HUD bar — sát trên cùng màn hình (y = 0)
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screen.size.width, 18)];
    bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    [_hudWindow.rootViewController.view addSubview:bar];

    _hudLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, screen.size.width, 18)];
    _hudLabel.textAlignment = NSTextAlignmentCenter;
    _hudLabel.font = [UIFont boldSystemFontOfSize:9];
    _hudLabel.textColor = [UIColor greenColor];
    _hudLabel.text = @"©MiTiModGames";
    [bar addSubview:_hudLabel];

    _colorIndex = 0;
    _cityName   = @"...";

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    _locManager = [[CLLocationManager alloc] init];
    _locManager.delegate = self;
    _locManager.desiredAccuracy = kCLLocationAccuracyKilometer;
    [_locManager requestWhenInUseAuthorization];
    [_locManager startUpdatingLocation];

    _frameCount  = 0;
    _lastTime    = CACurrentMediaTime();
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (UIColor *)rainbowColor {
    NSArray *colors = @[
        [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1],
        [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1],
        [UIColor colorWithRed:1.0 green:1.0 blue:0.0 alpha:1],
        [UIColor colorWithRed:0.2 green:1.0 blue:0.2 alpha:1],
        [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1],
        [UIColor colorWithRed:0.6 green:0.2 blue:1.0 alpha:1],
        [UIColor colorWithRed:1.0 green:0.2 blue:0.8 alpha:1],
    ];
    _colorIndex = (_colorIndex + 1) % colors.count;
    return colors[_colorIndex];
}

- (NSString *)vnTime {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.timeZone   = [NSTimeZone timeZoneWithName:@"Asia/Ho_Chi_Minh"];
    fmt.dateFormat = @"HH:mm:ss dd/MM/yyyy";
    return [fmt stringFromDate:[NSDate date]];
}

- (void)tick:(CADisplayLink *)link {
    _frameCount++;
    CFTimeInterval now  = CACurrentMediaTime();
    CFTimeInterval diff = now - _lastTime;
    if (diff >= 1.0) {
        NSInteger fps = (NSInteger)round(_frameCount / diff);
        _frameCount = 0; _lastTime = now;
        float battery = [UIDevice currentDevice].batteryLevel * 100;
        NSString *bat  = battery < 0 ? @"N/A" : [NSString stringWithFormat:@"%.0f%%", battery];
        NSString *time = [self vnTime];
        NSString *city = _cityName;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_hudLabel.textColor = [self rainbowColor];
            self->_hudLabel.text = [NSString stringWithFormat:
                @"©MiTiModGames  FPS:%ld  🔋%@  📍%@  🕐%@  Zalo:0559919099",
                (long)fps, bat, city, time];
        });
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    CLGeocoder *geo = [[CLGeocoder alloc] init];
    [geo reverseGeocodeLocation:loc completionHandler:^(NSArray *marks, NSError *err) {
        if (marks.count > 0) {
            CLPlacemark *mark = marks[0];
            NSString *city = mark.locality ?: mark.administrativeArea ?: @"VN";
            dispatch_async(dispatch_get_main_queue(), ^{ self->_cityName = city; });
        }
    }];
    [manager stopUpdatingLocation];
}
@end

// ═══════════════════════════════════════════
//  MENU MiTiGames — Floating Icon + Panel chức năng
// ═══════════════════════════════════════════

@interface MiTiMenuManager : NSObject
+ (void)install;
@end

@implementation MiTiMenuManager {
    UIWindow *_menuWindow;
    UIWindow *_panelWindow;
    UIButton *_iconBtn;
    BOOL      _panelVisible;
}

+ (instancetype)shared {
    static MiTiMenuManager *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MiTiMenuManager new]; });
    return s;
}
+ (void)install { [[self shared] setup]; }

- (void)setup {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;

    CGRect screen = [UIScreen mainScreen].bounds;

    _menuWindow = [[UIWindow alloc] initWithWindowScene:scene];
    _menuWindow.windowLevel = UIWindowLevelAlert + 400;
    _menuWindow.backgroundColor = [UIColor clearColor];
    UIViewController *iconVC = [[UIViewController alloc] init];
    iconVC.view.backgroundColor = [UIColor clearColor];
    _menuWindow.rootViewController = iconVC;
    [_menuWindow makeKeyAndVisible];

    CGFloat iconSize = 52;
    _iconBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _iconBtn.frame = CGRectMake(screen.size.width - iconSize - 8,
                                screen.size.height / 2 - iconSize / 2,
                                iconSize, iconSize);
    _iconBtn.layer.cornerRadius = iconSize / 2;
    _iconBtn.clipsToBounds = YES;
    _iconBtn.layer.borderWidth = 2;
    _iconBtn.layer.borderColor = [UIColor colorWithRed:0.5 green:0.3 blue:1.0 alpha:0.9].CGColor;

    CAGradientLayer *iconGrad = [CAGradientLayer layer];
    iconGrad.frame  = _iconBtn.bounds;
    iconGrad.colors = @[
        (__bridge id)[UIColor colorWithRed:0.3 green:0.1 blue:0.8 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:0.7 green:0.1 blue:0.5 alpha:1].CGColor,
    ];
    iconGrad.startPoint = CGPointMake(0, 0);
    iconGrad.endPoint   = CGPointMake(1, 1);
    [_iconBtn.layer insertSublayer:iconGrad atIndex:0];

    UILabel *emoji = [[UILabel alloc] initWithFrame:_iconBtn.bounds];
    emoji.text = @"🎮";
    emoji.font = [UIFont systemFontOfSize:22];
    emoji.textAlignment = NSTextAlignmentCenter;
    emoji.userInteractionEnabled = NO;
    [_iconBtn addSubview:emoji];

    [_iconBtn addTarget:self action:@selector(iconTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(iconDragged:)];
    [_iconBtn addGestureRecognizer:pan];
    [iconVC.view addSubview:_iconBtn];

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue = @1.0; pulse.toValue = @1.08;
    pulse.duration = 1.0; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
    [_iconBtn.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)iconDragged:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:_iconBtn.superview];
    CGPoint center = _iconBtn.center;
    center.x += delta.x; center.y += delta.y;
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat r = _iconBtn.bounds.size.width / 2;
    center.x = MAX(r+8, MIN(screen.size.width-r-8,   center.x));
    center.y = MAX(r+8, MIN(screen.size.height-r-8,  center.y));
    _iconBtn.center = center;
    [pan setTranslation:CGPointZero inView:_iconBtn.superview];
}

- (void)iconTapped {
    _panelVisible ? [self hidePanel] : [self showPanel];
}

- (void)showPanel {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat W = 280, H = 260;
    CGFloat X = (screen.size.width - W) / 2;
    CGFloat Y = (screen.size.height - H) / 2;

    _panelWindow = [[UIWindow alloc] initWithWindowScene:scene];
    _panelWindow.windowLevel = UIWindowLevelAlert + 350;
    _panelWindow.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    _panelWindow.rootViewController = vc;
    [_panelWindow makeKeyAndVisible];

    UIView *dim = [[UIView alloc] initWithFrame:screen];
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
    UITapGestureRecognizer *dimTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(hidePanel)];
    [dim addGestureRecognizer:dimTap];
    [vc.view addSubview:dim];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(X, screen.size.height, W, H)];
    card.layer.cornerRadius  = 20;
    card.layer.masksToBounds = NO;
    card.layer.shadowColor   = [UIColor colorWithRed:0.4 green:0.1 blue:1.0 alpha:0.7].CGColor;
    card.layer.shadowOffset  = CGSizeMake(0, 6);
    card.layer.shadowRadius  = 20;
    card.layer.shadowOpacity = 1;

    UIView *cardBg = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,H)];
    cardBg.layer.cornerRadius = 20; cardBg.clipsToBounds = YES;
    CAGradientLayer *bg = [CAGradientLayer layer];
    bg.frame  = cardBg.bounds;
    bg.colors = @[
        (__bridge id)[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.97].CGColor,
        (__bridge id)[UIColor colorWithRed:0.10 green:0.05 blue:0.20 alpha:0.97].CGColor,
    ];
    bg.startPoint = CGPointMake(0,0); bg.endPoint = CGPointMake(1,1);
    [cardBg.layer insertSublayer:bg atIndex:0];
    [card addSubview:cardBg]; [vc.view addSubview:card];

    CAGradientLayer *accent = [CAGradientLayer layer];
    accent.frame  = CGRectMake(0,0,W,3);
    accent.colors = @[
        (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:1.0 green:0.3 blue:0.6 alpha:1].CGColor,
    ];
    accent.startPoint = CGPointMake(0,0); accent.endPoint = CGPointMake(1,0);
    [cardBg.layer addSublayer:accent];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(0,10,W,24)];
    titleLbl.text = @"🎮  MiTiGames";
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.font = [UIFont boldSystemFontOfSize:16];
    titleLbl.textColor = [UIColor whiteColor];
    [cardBg addSubview:titleLbl];

    UILabel *subLbl = [[UILabel alloc] initWithFrame:CGRectMake(0,34,W,14)];
    subLbl.text = @"Free Fire — MegaData Patch";
    subLbl.textAlignment = NSTextAlignmentCenter;
    subLbl.font = [UIFont systemFontOfSize:10];
    subLbl.textColor = [UIColor colorWithWhite:0.45 alpha:1];
    [cardBg addSubview:subLbl];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(16,54,W-32,1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    [cardBg addSubview:div];

    // 3 chức năng
    NSArray *features = @[
        @"Neckbone_Spine1B → Hipsbone",
        @"Hipsbone_LeftToe → Neckbone",
        @"Xóa HEAD (HTTP Method)",
    ];

    CGFloat rowY = 62;
    for (NSInteger i = 0; i < 3; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(12, rowY, W-24, 50)];
        row.layer.cornerRadius = 12;
        row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
        [cardBg addSubview:row];

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(12,8,W-100,34)];
        lbl.text = features[i];
        lbl.textColor = [UIColor whiteColor];
        lbl.font = [UIFont systemFontOfSize:12];
        lbl.numberOfLines = 2;
        [row addSubview:lbl];

        UIButton *toggle = [UIButton buttonWithType:UIButtonTypeCustom];
        toggle.frame = CGRectMake(W-24-60, 12, 52, 26);
        toggle.layer.cornerRadius = 13;
        toggle.clipsToBounds = YES;
        toggle.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
        toggle.tag = i;

        UILabel *toggleTxt = [[UILabel alloc] initWithFrame:toggle.bounds];
        toggleTxt.text = @"TẮT";
        toggleTxt.font = [UIFont boldSystemFontOfSize:10];
        toggleTxt.textAlignment = NSTextAlignmentCenter;
        toggleTxt.textColor = [UIColor colorWithWhite:0.5 alpha:1];
        toggleTxt.tag = 99;
        toggleTxt.userInteractionEnabled = NO;
        [toggle addSubview:toggleTxt];

        [toggle addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:toggle];
        rowY += 56;
    }

    [UIView animateWithDuration:0.1 animations:^{
        dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    }];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.78
          initialSpringVelocity:0.5 options:0 animations:^{
        card.frame = CGRectMake(X, Y, W, H);
    } completion:nil];

    _panelVisible = YES;
    objc_setAssociatedObject(self, "card", card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "dim",  dim,  OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)toggleTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    BOOL isOn = ![objc_getAssociatedObject(sender, "on") boolValue];
    objc_setAssociatedObject(sender, "on", @(isOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *lbl = (UILabel *)[sender viewWithTag:99];
    [UIView animateWithDuration:0.25 animations:^{
        if (isOn) {
            sender.backgroundColor = [UIColor colorWithRed:0.25 green:0.75 blue:0.35 alpha:1];
            lbl.text = @"BẬT"; lbl.textColor = [UIColor whiteColor];
        } else {
            sender.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
            lbl.text = @"TẮT"; lbl.textColor = [UIColor colorWithWhite:0.5 alpha:1];
        }
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (idx == 0) applyPatch1(isOn);
        else if (idx == 1) applyPatch2(isOn);
        else if (idx == 2) applyPatch3(isOn);
    });
}

- (void)hidePanel {
    UIView *card = objc_getAssociatedObject(self, "card");
    UIView *dim  = objc_getAssociatedObject(self, "dim");
    [UIView animateWithDuration:0.25 animations:^{
        card.alpha = 0;
        card.transform = CGAffineTransformMakeScale(0.92, 0.92);
        dim.backgroundColor = [UIColor clearColor];
    } completion:^(BOOL d){
        self->_panelWindow.hidden = YES;
        self->_panelWindow = nil;
        self->_panelVisible = NO;
    }];
}

@end

// ═══════════════════════════════════════════
//  MENU Social — MiTiModGames (tự đóng 10s)
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
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        win.rootViewController = vc;
        [win makeKeyAndVisible];

        UIView *dim = [[UIView alloc] initWithFrame:screen];
        dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
        [vc.view addSubview:dim];

        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, screen.size.height, cardW, cardH)];
        card.layer.cornerRadius  = 22; card.layer.masksToBounds = NO;
        card.layer.shadowColor   = [UIColor colorWithRed:0.4 green:0.1 blue:1.0 alpha:0.6].CGColor;
        card.layer.shadowOffset  = CGSizeMake(0, 8);
        card.layer.shadowRadius  = 24; card.layer.shadowOpacity = 1;

        UIView *cardBg = [[UIView alloc] initWithFrame:CGRectMake(0,0,cardW,cardH)];
        cardBg.layer.cornerRadius = 22; cardBg.clipsToBounds = YES;
        CAGradientLayer *bg = [CAGradientLayer layer];
        bg.frame = cardBg.bounds;
        bg.colors = @[
            (__bridge id)[UIColor colorWithRed:0.06 green:0.06 blue:0.16 alpha:0.97].CGColor,
            (__bridge id)[UIColor colorWithRed:0.10 green:0.06 blue:0.22 alpha:0.97].CGColor,
        ];
        bg.startPoint = CGPointMake(0,0); bg.endPoint = CGPointMake(1,1);
        [cardBg.layer insertSublayer:bg atIndex:0];
        [card addSubview:cardBg]; [vc.view addSubview:card];

        CAGradientLayer *accent = [CAGradientLayer layer];
        accent.frame = CGRectMake(0,0,cardW,3);
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
        lg.frame = logo.bounds;
        lg.colors = @[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1.0 alpha:1].CGColor,
        ];
        lg.startPoint = CGPointMake(0,0); lg.endPoint = CGPointMake(1,1);
        [logo.layer insertSublayer:lg atIndex:0];
        UILabel *ll = [[UILabel alloc] initWithFrame:logo.bounds];
        ll.text = @"🎮"; ll.font = [UIFont systemFontOfSize:22];
        ll.textAlignment = NSTextAlignmentCenter;
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

        UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(16,116,cardW-32,1)];
        divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
        [cardBg addSubview:divider];

        NSArray *links = @[
            @{@"icon":@"▶️",@"title":@"YouTube",@"sub":@"@ymt139",
              @"url":@"https://www.youtube.com/@ymt139",
              @"r1":@0.9f,@"g1":@0.1f,@"b1":@0.1f,@"r2":@1.0f,@"g2":@0.3f,@"b2":@0.1f},
            @{@"icon":@"🎵",@"title":@"TikTok",@"sub":@"@yel123321",
              @"url":@"https://www.tiktok.com/@yel123321",
              @"r1":@0.1f,@"g1":@0.1f,@"b1":@0.1f,@"r2":@0.3f,@"g2":@0.3f,@"b2":@0.3f},
            @{@"icon":@"💬",@"title":@"Zalo",@"sub":@"0559919099",
              @"url":@"https://zalo.me/0559919099",
              @"r1":@0.0f,@"g1":@0.4f,@"b1":@0.9f,@"r2":@0.0f,@"g2":@0.6f,@"b2":@1.0f},
        ];

        CGFloat rowY = 124;
        for (NSDictionary *item in links) {
            NSString *urlStr = item[@"url"];
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(12,rowY,cardW-24,52);
            row.layer.cornerRadius = 13; row.clipsToBounds = YES;
            row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
            [row setBackgroundImage:[self imageWithColor:[UIColor colorWithWhite:1 alpha:0.12]] forState:UIControlStateHighlighted];

            UIView *iconBg = [[UIView alloc] initWithFrame:CGRectMake(10,9,34,34)];
            iconBg.layer.cornerRadius = 10; iconBg.clipsToBounds = YES;
            CAGradientLayer *ig = [CAGradientLayer layer];
            ig.frame = iconBg.bounds;
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
            tl.font = [UIFont boldSystemFontOfSize:14]; tl.userInteractionEnabled = NO;
            [row addSubview:tl];

            UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(52,28,cardW-90,15)];
            sl.text = item[@"sub"]; sl.textColor = [UIColor colorWithWhite:0.45 alpha:1];
            sl.font = [UIFont systemFontOfSize:11]; sl.userInteractionEnabled = NO;
            [row addSubview:sl];

            UILabel *arr = [[UILabel alloc] initWithFrame:CGRectMake(cardW-38,14,20,24)];
            arr.text = @"›"; arr.textColor = [UIColor colorWithWhite:0.4 alpha:1];
            arr.font = [UIFont boldSystemFontOfSize:20]; arr.userInteractionEnabled = NO;
            [row addSubview:arr];

            objc_setAssociatedObject(row, "url", urlStr, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [row addTarget:[MiTiLinkHandler shared] action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cardBg addSubview:row];
            rowY += 58;
        }

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
            card.frame = CGRectMake(cardX, cardY, cardW, cardH);
        } completion:nil];

        void (^closeMenu)(void) = ^{
            [UIView animateWithDuration:0.28 animations:^{
                card.alpha = 0;
                card.transform = CGAffineTransformMakeScale(0.92, 0.92);
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

+ (UIImage *)imageWithColor:(UIColor *)color {
    CGRect r = CGRectMake(0,0,1,1);
    UIGraphicsBeginImageContext(r.size);
    [color setFill]; UIRectFill(r);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end

// ── Constructor ──
__attribute__((constructor))
static void MiTiModGamesInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [MiTiHUD start];
        [MiTiMenuManager install];
        [MiTiModGamesMenu show];
    });
}
