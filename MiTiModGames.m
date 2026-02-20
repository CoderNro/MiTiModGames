#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <string.h>

// ═══════════════════════════════════════════════════════
//  PASSTHROUGH WINDOW — Touch xuyên qua game
// ═══════════════════════════════════════════════════════

@interface MiTiPassthroughWindow : UIWindow
@end
@implementation MiTiPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ═══════════════════════════════════════════════════════
//  GLOBAL-METADATA PATCHER
//  Patch file: Data/Managed/Metadata/global-metadata.dat
// ═══════════════════════════════════════════════════════

static BOOL gDinhDau = NO; // trạng thái chức năng Dính Đầu

// Tìm file global-metadata.dat trong bundle
static NSString *findOriginalMetadata(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *candidates = @[
        [NSBundle.mainBundle.bundlePath
            stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"],
        [NSBundle.mainBundle.resourcePath
            stringByAppendingPathComponent:@"Data/Managed/Metadata/global-metadata.dat"],
    ];
    for (NSString *p in candidates)
        if ([fm fileExistsAtPath:p]) return p;

    // Tìm đệ quy
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:NSBundle.mainBundle.bundlePath];
    for (NSString *f in en) {
        if ([f.lastPathComponent isEqualToString:@"global-metadata.dat"])
            return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:f];
    }
    return nil;
}

// Đường dẫn bản copy trong Documents
static NSString *patchedPath(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [doc stringByAppendingPathComponent:@"MiTi_global-metadata.dat"];
}

// Copy file gốc sang Documents nếu chưa có
static BOOL ensureCopied(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dest = patchedPath();
    if ([fm fileExistsAtPath:dest]) return YES;
    NSString *src = findOriginalMetadata();
    if (!src) return NO;
    NSError *err;
    [fm copyItemAtPath:src toPath:dest error:&err];
    return err == nil;
}

// Tìm và thay thế bytes trong data — trả về số lần thay
static NSInteger replaceBytes(NSMutableData *data,
                               const uint8_t *find,    size_t fLen,
                               const uint8_t *replace, size_t rLen) {
    if (!data || fLen == 0 || fLen != rLen) return 0;
    uint8_t *bytes = (uint8_t *)data.mutableBytes;
    NSUInteger total = data.length;
    NSInteger count  = 0;
    for (NSUInteger i = 0; i + fLen <= total; i++) {
        if (memcmp(bytes + i, find, fLen) == 0) {
            memcpy(bytes + i, replace, rLen);
            NSLog(@"[MiTi] Replaced tại offset: 0x%lX", (unsigned long)i);
            count++;
            i += fLen - 1;
        }
    }
    return count;
}

// ══════════════════════════════════════════
//  CHỨC NĂNG DÍNH ĐẦU
//  Gộp 3 patch thành 1:
//  1. Neckbone_Spine1B  → Hipsbone_spine1B
//  2. Hipsbone_LeftToebone → Neckbone_LeftToebone
//  3. \0GET\0HEAD → \0GET\0    (xóa HEAD)
// ══════════════════════════════════════════

static void applyDinhDau(BOOL enable, void(^completion)(BOOL ok, NSString *msg)) {
    if (!ensureCopied()) {
        if (completion) completion(NO,
            @"❌ Không tìm thấy global-metadata.dat\n"
            @"Hãy mở game một lần để game tải file, sau đó thử lại.");
        return;
    }

    NSError *err;
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:patchedPath()
                                                        options:0 error:&err];
    if (!data) {
        if (completion) completion(NO,
            [NSString stringWithFormat:@"❌ Không đọc được file:\n%@", err]);
        return;
    }

    NSInteger total = 0;

    if (enable) {
        // ── BẬT: apply 3 patch ──

        // Patch 1: Neckbone_Spine1B → Hipsbone_spine1B (16 bytes)
        const uint8_t p1f[] = "Neckbone_Spine1B";
        const uint8_t p1r[] = "Hipsbone_spine1B";
        total += replaceBytes(data, p1f, 16, p1r, 16);

        // Patch 2: Hipsbone_LeftToebone → Neckbone_LeftToebone (20 bytes)
        const uint8_t p2f[] = "Hipsbone_LeftToebone";
        const uint8_t p2r[] = "Neckbone_LeftToebone";
        total += replaceBytes(data, p2f, 20, p2r, 20);

        // Patch 3: \0GET\0HEAD → \0GET\0    (9 bytes)
        const uint8_t p3f[] = {0x00,'G','E','T',0x00,'H','E','A','D'};
        const uint8_t p3r[] = {0x00,'G','E','T',0x00,0x20,0x20,0x20,0x20};
        total += replaceBytes(data, p3f, 9, p3r, 9);

    } else {
        // ── TẮT: restore 3 patch về gốc ──

        // Restore 1
        const uint8_t r1f[] = "Hipsbone_spine1B";
        const uint8_t r1r[] = "Neckbone_Spine1B";
        total += replaceBytes(data, r1f, 16, r1r, 16);

        // Restore 2
        const uint8_t r2f[] = "Neckbone_LeftToebone";
        const uint8_t r2r[] = "Hipsbone_LeftToebone";
        total += replaceBytes(data, r2f, 20, r2r, 20);

        // Restore 3
        const uint8_t r3f[] = {0x00,'G','E','T',0x00,0x20,0x20,0x20,0x20};
        const uint8_t r3r[] = {0x00,'G','E','T',0x00,'H','E','A','D'};
        total += replaceBytes(data, r3f, 9, r3r, 9);
    }

    // Ghi file
    BOOL ok = [data writeToFile:patchedPath() options:NSDataWritingAtomic error:&err];
    if (!ok) {
        if (completion) completion(NO,
            [NSString stringWithFormat:@"❌ Ghi file thất bại:\n%@", err]);
        return;
    }

    NSString *msg;
    if (enable) {
        msg = [NSString stringWithFormat:
            @"🎯 Dính Đầu đã BẬT!\n\n"
            @"✅ Patch 1: Neckbone_Spine1B → Hipsbone\n"
            @"✅ Patch 2: Hipsbone_LeftToe → Neckbone\n"
            @"✅ Patch 3: Xóa HEAD (HTTP)\n\n"
            @"Đã thay %ld chỗ trong file.\n"
            @"⚠️ Restart game để áp dụng!", (long)total];
    } else {
        msg = [NSString stringWithFormat:
            @"🔴 Dính Đầu đã TẮT!\n\n"
            @"✅ Đã khôi phục %ld chỗ về gốc.\n"
            @"⚠️ Restart game để áp dụng!", (long)total];
    }

    if (completion) completion(YES, msg);
}

// ═══════════════════════════════════════════
//  LINK HANDLER
// ═══════════════════════════════════════════

@interface MiTiLinkHandler : NSObject
+ (instancetype)shared;
- (void)buttonTapped:(UIButton *)sender;
@end

@implementation MiTiLinkHandler
+ (instancetype)shared {
    static MiTiLinkHandler *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MiTiLinkHandler new]; });
    return s;
}
- (void)buttonTapped:(UIButton *)sender {
    NSString *url = objc_getAssociatedObject(sender, "url");
    if (url) [[UIApplication sharedApplication]
        openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}
@end

// ═══════════════════════════════════════════
//  HUD — FPS + Pin + Giờ VN + Vị trí
// ═══════════════════════════════════════════

@interface MiTiHUD : NSObject <CLLocationManagerDelegate>
+ (void)start;
@end

@implementation MiTiHUD {
    CADisplayLink     *_dl;
    NSInteger          _frames;
    CFTimeInterval     _last;
    UIWindow          *_win;
    UILabel           *_lbl;
    NSInteger          _ci;
    CLLocationManager *_loc;
    NSString          *_city;
}

+ (instancetype)shared {
    static MiTiHUD *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MiTiHUD new]; });
    return s;
}
+ (void)start { [[self shared] setup]; }

- (void)setup {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (id)s; break; }
    if (!scene) return;

    CGFloat W = UIScreen.mainScreen.bounds.size.width;
    _win = [[MiTiPassthroughWindow alloc] initWithWindowScene:scene];
    _win.windowLevel = UIWindowLevelAlert + 300;
    _win.backgroundColor = UIColor.clearColor;
    _win.userInteractionEnabled = NO;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    _win.rootViewController = vc;
    [_win makeKeyAndVisible];

    // Bar sát trên cùng y=0
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 18)];
    bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    bar.userInteractionEnabled = NO;
    [vc.view addSubview:bar];

    _lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, W, 18)];
    _lbl.textAlignment = NSTextAlignmentCenter;
    _lbl.font = [UIFont boldSystemFontOfSize:9];
    _lbl.textColor = UIColor.greenColor;
    _lbl.text = @"©MiTiModGames";
    _lbl.userInteractionEnabled = NO;
    [bar addSubview:_lbl];

    _city = @"...";
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    _loc = [CLLocationManager new];
    _loc.delegate = self;
    _loc.desiredAccuracy = kCLLocationAccuracyKilometer;
    [_loc requestWhenInUseAuthorization];
    [_loc startUpdatingLocation];

    _frames = 0; _last = CACurrentMediaTime();
    _dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_dl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (UIColor *)rainbow {
    NSArray *c = @[
        [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1],
        [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1],
        [UIColor colorWithRed:1.0 green:1.0 blue:0.0 alpha:1],
        [UIColor colorWithRed:0.2 green:1.0 blue:0.2 alpha:1],
        [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1],
        [UIColor colorWithRed:0.6 green:0.2 blue:1.0 alpha:1],
        [UIColor colorWithRed:1.0 green:0.2 blue:0.8 alpha:1],
    ];
    _ci = (_ci + 1) % c.count;
    return c[_ci];
}

- (void)tick:(CADisplayLink *)link {
    _frames++;
    CFTimeInterval now = CACurrentMediaTime(), diff = now - _last;
    if (diff < 1.0) return;
    NSInteger fps = (NSInteger)round(_frames / diff);
    _frames = 0; _last = now;
    float bat = [UIDevice currentDevice].batteryLevel * 100;
    NSString *batS = bat < 0 ? @"N/A" : [NSString stringWithFormat:@"%.0f%%", bat];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.timeZone   = [NSTimeZone timeZoneWithName:@"Asia/Ho_Chi_Minh"];
    fmt.dateFormat = @"HH:mm dd/MM";
    NSString *t = [fmt stringFromDate:NSDate.date], *city = _city;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_lbl.textColor = [self rainbow];
        self->_lbl.text = [NSString stringWithFormat:
            @"©MiTi  FPS:%ld  🔋%@  📍%@  🕐%@  Zalo:0559919099",
            (long)fps, batS, city, t];
    });
}

- (void)locationManager:(CLLocationManager *)m
     didUpdateLocations:(NSArray<CLLocation*>*)locs {
    [[CLGeocoder new] reverseGeocodeLocation:locs.lastObject
                           completionHandler:^(NSArray *marks, NSError *e) {
        if (!marks.count) return;
        CLPlacemark *p = marks[0];
        NSString *city = p.locality ?: p.administrativeArea ?: @"VN";
        dispatch_async(dispatch_get_main_queue(), ^{ self->_city = city; });
    }];
    [m stopUpdatingLocation];
}
@end

// ═══════════════════════════════════════════════════════
//  MENU MiTiGames — Icon nổi + Panel 1 nút Dính Đầu
// ═══════════════════════════════════════════════════════

@interface MiTiMenuManager : NSObject
+ (void)install;
@end

@implementation MiTiMenuManager {
    MiTiPassthroughWindow *_floatWin;
    MiTiPassthroughWindow *_panelWin;
    UIButton              *_iconBtn;
    UIButton              *_dinhDauBtn;
    UILabel               *_dinhDauLbl;
    UILabel               *_statusLbl;
    BOOL                   _panelVisible;
}

+ (instancetype)shared {
    static MiTiMenuManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [MiTiMenuManager new]; });
    return s;
}
+ (void)install { [[self shared] setup]; }

- (void)setup {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (id)s; break; }
    if (!scene) return;

    CGRect sc = UIScreen.mainScreen.bounds;
    CGFloat sz = 50;

    _floatWin = [[MiTiPassthroughWindow alloc] initWithWindowScene:scene];
    _floatWin.windowLevel = UIWindowLevelAlert + 400;
    _floatWin.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    _floatWin.rootViewController = vc;
    [_floatWin makeKeyAndVisible];

    _iconBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _iconBtn.frame = CGRectMake(sc.size.width-sz-6, sc.size.height/2-sz/2, sz, sz);
    _iconBtn.layer.cornerRadius = sz/2;
    _iconBtn.clipsToBounds = YES;
    _iconBtn.layer.borderWidth = 2;
    _iconBtn.layer.borderColor = [UIColor colorWithRed:0.5 green:0.3 blue:1 alpha:1].CGColor;

    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = CGRectMake(0,0,sz,sz);
    g.colors = @[
        (__bridge id)[UIColor colorWithRed:0.25 green:0.08 blue:0.75 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:0.65 green:0.08 blue:0.45 alpha:1].CGColor,
    ];
    g.startPoint = CGPointMake(0,0); g.endPoint = CGPointMake(1,1);
    [_iconBtn.layer insertSublayer:g atIndex:0];

    UILabel *emoji = [[UILabel alloc] initWithFrame:CGRectMake(0,0,sz,sz)];
    emoji.text = @"🎮"; emoji.font = [UIFont systemFontOfSize:20];
    emoji.textAlignment = NSTextAlignmentCenter;
    emoji.userInteractionEnabled = NO;
    [_iconBtn addSubview:emoji];

    [_iconBtn addTarget:self action:@selector(iconTapped)
      forControlEvents:UIControlEventTouchUpInside];
    [_iconBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(iconDrag:)]];
    [vc.view addSubview:_iconBtn];

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.fromValue=@1.0; pulse.toValue=@1.1; pulse.duration=1.0;
    pulse.autoreverses=YES; pulse.repeatCount=HUGE_VALF;
    [_iconBtn.layer addAnimation:pulse forKey:@"p"];
}

- (void)iconDrag:(UIPanGestureRecognizer *)gr {
    CGPoint d = [gr translationInView:_iconBtn.superview];
    CGPoint c = _iconBtn.center;
    c.x += d.x; c.y += d.y;
    CGRect sc = UIScreen.mainScreen.bounds;
    CGFloat r = _iconBtn.bounds.size.width/2;
    c.x = MAX(r+6, MIN(sc.size.width-r-6,  c.x));
    c.y = MAX(r+6, MIN(sc.size.height-r-6, c.y));
    _iconBtn.center = c;
    [gr setTranslation:CGPointZero inView:_iconBtn.superview];
}

- (void)iconTapped {
    _panelVisible ? [self hidePanel] : [self showPanel];
}

- (void)showPanel {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (id)s; break; }
    if (!scene) return;

    CGRect sc = UIScreen.mainScreen.bounds;
    CGFloat W = 290, H = 280;
    CGFloat X = (sc.size.width-W)/2, Y = (sc.size.height-H)/2;

    _panelWin = [[MiTiPassthroughWindow alloc] initWithWindowScene:scene];
    _panelWin.windowLevel = UIWindowLevelAlert + 350;
    _panelWin.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    _panelWin.rootViewController = vc;
    [_panelWin makeKeyAndVisible];

    // Dim
    UIView *dim = [[UIView alloc] initWithFrame:sc];
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
    [dim addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(hidePanel)]];
    [vc.view addSubview:dim];

    // Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(X, sc.size.height, W, H)];
    card.layer.cornerRadius=20; card.layer.masksToBounds=NO;
    card.layer.shadowColor=[UIColor colorWithRed:0.4 green:0.1 blue:1 alpha:0.7].CGColor;
    card.layer.shadowOffset=CGSizeMake(0,6);
    card.layer.shadowRadius=20; card.layer.shadowOpacity=1;

    UIView *cbg = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,H)];
    cbg.layer.cornerRadius=20; cbg.clipsToBounds=YES;
    CAGradientLayer *bgG = [CAGradientLayer layer]; bgG.frame=cbg.bounds;
    bgG.colors=@[
        (__bridge id)[UIColor colorWithRed:0.05 green:0.05 blue:0.14 alpha:0.97].CGColor,
        (__bridge id)[UIColor colorWithRed:0.09 green:0.04 blue:0.20 alpha:0.97].CGColor,
    ];
    bgG.startPoint=CGPointMake(0,0); bgG.endPoint=CGPointMake(1,1);
    [cbg.layer insertSublayer:bgG atIndex:0];
    [card addSubview:cbg]; [vc.view addSubview:card];

    // Accent top
    CAGradientLayer *acc = [CAGradientLayer layer];
    acc.frame=CGRectMake(0,0,W,3);
    acc.colors=@[
        (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:1.0 green:0.3 blue:0.6 alpha:1].CGColor,
    ];
    acc.startPoint=CGPointMake(0,0); acc.endPoint=CGPointMake(1,0);
    [cbg.layer addSublayer:acc];

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,12,W,24)];
    title.text=@"🎮  MiTiGames";
    title.textAlignment=NSTextAlignmentCenter;
    title.font=[UIFont boldSystemFontOfSize:16];
    title.textColor=UIColor.whiteColor;
    [cbg addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0,36,W,14)];
    sub.text=@"Free Fire — Cheat Menu";
    sub.textAlignment=NSTextAlignmentCenter;
    sub.font=[UIFont systemFontOfSize:10];
    sub.textColor=[UIColor colorWithWhite:0.42 alpha:1];
    [cbg addSubview:sub];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(14,54,W-28,1)];
    div.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07];
    [cbg addSubview:div];

    // ══ NÚT DÍNH ĐẦU LỚN ══
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(14,62,W-28,90)];
    row.layer.cornerRadius=16;
    row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.04];
    [cbg addSubview:row];

    // Icon mục tiêu
    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(16,14,52,52)];
    icon.text=@"🎯";
    icon.font=[UIFont systemFontOfSize:34];
    icon.textAlignment=NSTextAlignmentCenter;
    [row addSubview:icon];

    // Tên chức năng
    UILabel *nameLbl = [[UILabel alloc] initWithFrame:CGRectMake(76,10,W-180,26)];
    nameLbl.text=@"Dính Đầu";
    nameLbl.textColor=UIColor.whiteColor;
    nameLbl.font=[UIFont boldSystemFontOfSize:18];
    [row addSubview:nameLbl];

    // Mô tả
    UILabel *descLbl = [[UILabel alloc] initWithFrame:CGRectMake(76,36,W-180,42)];
    descLbl.text=@"Patch 3 offset trong\nglobal-metadata.dat";
    descLbl.textColor=[UIColor colorWithWhite:0.45 alpha:1];
    descLbl.font=[UIFont systemFontOfSize:10];
    descLbl.numberOfLines=2;
    [row addSubview:descLbl];

    // Toggle switch lớn
    UIButton *tog = [UIButton buttonWithType:UIButtonTypeCustom];
    tog.frame = CGRectMake(W-28-78, 28, 72, 34);
    tog.layer.cornerRadius=17; tog.clipsToBounds=YES;
    tog.backgroundColor = gDinhDau
        ? [UIColor colorWithRed:0.18 green:0.72 blue:0.32 alpha:1]
        : [UIColor colorWithRed:0.2  green:0.2  blue:0.25 alpha:1];

    _dinhDauLbl = [[UILabel alloc] initWithFrame:tog.bounds];
    _dinhDauLbl.text = gDinhDau ? @"BẬT" : @"TẮT";
    _dinhDauLbl.textColor = gDinhDau
        ? UIColor.whiteColor
        : [UIColor colorWithWhite:0.5 alpha:1];
    _dinhDauLbl.font=[UIFont boldSystemFontOfSize:13];
    _dinhDauLbl.textAlignment=NSTextAlignmentCenter;
    _dinhDauLbl.userInteractionEnabled=NO;
    [tog addSubview:_dinhDauLbl];
    [tog addTarget:self action:@selector(dinhDauTapped:)
  forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:tog];
    _dinhDauBtn = tog;

    // Status label
    _statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(14,160,W-28,20)];
    _statusLbl.text = gDinhDau
        ? @"✅ Đang bật — Restart game để áp dụng"
        : @"⚪ Chưa bật";
    _statusLbl.textAlignment=NSTextAlignmentCenter;
    _statusLbl.font=[UIFont systemFontOfSize:11];
    _statusLbl.textColor = gDinhDau
        ? [UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1]
        : [UIColor colorWithWhite:0.4 alpha:1];
    [cbg addSubview:_statusLbl];

    // Divider
    UIView *div2 = [[UIView alloc] initWithFrame:CGRectMake(14,186,W-28,1)];
    div2.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06];
    [cbg addSubview:div2];

    // Chi tiết 3 patch nhỏ
    NSArray *details = @[
        @"① Neckbone_Spine1B → Hipsbone_spine1B",
        @"② Hipsbone_LeftToebone → Neckbone_LeftToebone",
        @"③ Byte 474554 → xóa HEAD",
    ];
    CGFloat dy = 194;
    for (NSString *d in details) {
        UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(16,dy,W-32,18)];
        dl.text=d; dl.font=[UIFont systemFontOfSize:10];
        dl.textColor=[UIColor colorWithWhite:0.38 alpha:1];
        [cbg addSubview:dl]; dy+=20;
    }

    // Animate in
    [UIView animateWithDuration:0.12 animations:^{
        dim.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.45];
    }];
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.76
          initialSpringVelocity:0.5 options:0 animations:^{
        card.frame=CGRectMake(X,Y,W,H);
    } completion:nil];

    _panelVisible=YES;
    objc_setAssociatedObject(self,"card",card,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self,"dim", dim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dinhDauTapped:(UIButton *)sender {
    BOOL isOn = !gDinhDau;

    // Feedback tức thì
    sender.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.15 animations:^{
        sender.backgroundColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.2 alpha:1];
        self->_dinhDauLbl.text = @"...";
        self->_statusLbl.text = @"⏳ Đang patch file...";
        self->_statusLbl.textColor = [UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1];
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        applyDinhDau(isOn, ^(BOOL ok, NSString *msg) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sender.userInteractionEnabled = YES;

                if (ok) {
                    gDinhDau = isOn;
                    [UIView animateWithDuration:0.2 animations:^{
                        if (isOn) {
                            sender.backgroundColor =
                                [UIColor colorWithRed:0.18 green:0.72 blue:0.32 alpha:1];
                            self->_dinhDauLbl.text=@"BẬT";
                            self->_dinhDauLbl.textColor=UIColor.whiteColor;
                            self->_statusLbl.text=@"✅ Đang bật — Restart game để áp dụng";
                            self->_statusLbl.textColor=
                                [UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1];
                        } else {
                            sender.backgroundColor =
                                [UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:1];
                            self->_dinhDauLbl.text=@"TẮT";
                            self->_dinhDauLbl.textColor=[UIColor colorWithWhite:0.5 alpha:1];
                            self->_statusLbl.text=@"⚪ Chưa bật";
                            self->_statusLbl.textColor=[UIColor colorWithWhite:0.4 alpha:1];
                        }
                    }];
                } else {
                    // Thất bại — restore UI
                    [UIView animateWithDuration:0.2 animations:^{
                        sender.backgroundColor = gDinhDau
                            ? [UIColor colorWithRed:0.18 green:0.72 blue:0.32 alpha:1]
                            : [UIColor colorWithRed:0.2  green:0.2  blue:0.25 alpha:1];
                        self->_dinhDauLbl.text = gDinhDau ? @"BẬT" : @"TẮT";
                        self->_statusLbl.text=@"❌ Patch thất bại";
                        self->_statusLbl.textColor=[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1];
                    }];
                }

                // Hiển thị thông báo
                UIAlertController *alert=[UIAlertController
                    alertControllerWithTitle:isOn ? @"🎯 Dính Đầu" : @"🔴 Dính Đầu"
                    message:msg
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                    style:UIAlertActionStyleDefault handler:nil]];
                UIViewController *root =
                    UIApplication.sharedApplication.keyWindow.rootViewController;
                while (root.presentedViewController) root=root.presentedViewController;
                [root presentViewController:alert animated:YES completion:nil];
            });
        });
    });
}

- (void)hidePanel {
    UIView *card=objc_getAssociatedObject(self,"card");
    UIView *dim =objc_getAssociatedObject(self,"dim");
    [UIView animateWithDuration:0.22 animations:^{
        card.alpha=0;
        card.transform=CGAffineTransformMakeScale(0.90,0.90);
        dim.backgroundColor=UIColor.clearColor;
    } completion:^(BOOL d){
        self->_panelWin.hidden=YES;
        self->_panelWin=nil;
        self->_panelVisible=NO;
    }];
}

@end

// ═══════════════════════════════════════════
//  MENU SOCIAL — MiTiModGames (tự đóng 10s)
// ═══════════════════════════════════════════

@interface MiTiModGamesMenu : NSObject
+ (void)show;
@end

@implementation MiTiModGamesMenu

+ (UIImage *)imageWithColor:(UIColor *)c {
    UIGraphicsBeginImageContext(CGSizeMake(1,1));
    [c setFill]; UIRectFill(CGRectMake(0,0,1,1));
    UIImage *img=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext(); return img;
}

+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene=nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:UIWindowScene.class]) { scene=(id)s; break; }
        if (!scene) return;

        CGRect sc=UIScreen.mainScreen.bounds;
        CGFloat W=MIN(sc.size.width-60,300), H=340;
        CGFloat X=(sc.size.width-W)/2, Y=(sc.size.height-H)/2;

        MiTiPassthroughWindow *win=[[MiTiPassthroughWindow alloc] initWithWindowScene:scene];
        win.windowLevel=UIWindowLevelAlert+200;
        win.backgroundColor=UIColor.clearColor;
        UIViewController *vc=[UIViewController new];
        vc.view.backgroundColor=UIColor.clearColor;
        win.rootViewController=vc;
        [win makeKeyAndVisible];

        UIView *dim=[[UIView alloc] initWithFrame:sc];
        dim.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0];
        [vc.view addSubview:dim];

        UIView *card=[[UIView alloc] initWithFrame:CGRectMake(X,sc.size.height,W,H)];
        card.layer.cornerRadius=22; card.layer.masksToBounds=NO;
        card.layer.shadowColor=[UIColor colorWithRed:0.4 green:0.1 blue:1 alpha:0.6].CGColor;
        card.layer.shadowOffset=CGSizeMake(0,8);
        card.layer.shadowRadius=24; card.layer.shadowOpacity=1;

        UIView *cbg=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,H)];
        cbg.layer.cornerRadius=22; cbg.clipsToBounds=YES;
        CAGradientLayer *bg=[CAGradientLayer layer]; bg.frame=cbg.bounds;
        bg.colors=@[
            (__bridge id)[UIColor colorWithRed:0.06 green:0.06 blue:0.16 alpha:0.97].CGColor,
            (__bridge id)[UIColor colorWithRed:0.10 green:0.06 blue:0.22 alpha:0.97].CGColor,
        ];
        bg.startPoint=CGPointMake(0,0); bg.endPoint=CGPointMake(1,1);
        [cbg.layer insertSublayer:bg atIndex:0];
        [card addSubview:cbg]; [vc.view addSubview:card];

        CAGradientLayer *acc=[CAGradientLayer layer]; acc.frame=CGRectMake(0,0,W,3);
        acc.colors=@[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:1.0 green:0.3 blue:0.6 alpha:1].CGColor,
        ];
        acc.startPoint=CGPointMake(0,0); acc.endPoint=CGPointMake(1,0);
        [cbg.layer addSublayer:acc];

        UIView *logo=[[UIView alloc] initWithFrame:CGRectMake((W-48)/2,16,48,48)];
        logo.layer.cornerRadius=24; logo.clipsToBounds=YES;
        CAGradientLayer *lg=[CAGradientLayer layer]; lg.frame=logo.bounds;
        lg.colors=@[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1 alpha:1].CGColor,
        ];
        lg.startPoint=CGPointMake(0,0); lg.endPoint=CGPointMake(1,1);
        [logo.layer insertSublayer:lg atIndex:0];
        UILabel *ll=[[UILabel alloc] initWithFrame:logo.bounds];
        ll.text=@"🎮"; ll.font=[UIFont systemFontOfSize:22];
        ll.textAlignment=NSTextAlignmentCenter;
        [logo addSubview:ll]; [cbg addSubview:logo];

        CABasicAnimation *p=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
        p.fromValue=@1.0; p.toValue=@1.1; p.duration=0.9;
        p.autoreverses=YES; p.repeatCount=HUGE_VALF;
        [logo.layer addAnimation:p forKey:@"p"];

        UILabel *tl=[[UILabel alloc] initWithFrame:CGRectMake(0,70,W,22)];
        tl.text=@"MiTiModGames"; tl.textAlignment=NSTextAlignmentCenter;
        tl.font=[UIFont boldSystemFontOfSize:17]; tl.textColor=UIColor.whiteColor;
        [cbg addSubview:tl];

        UILabel *stl=[[UILabel alloc] initWithFrame:CGRectMake(0,94,W,16)];
        stl.text=@"Kênh chia sẻ mod & game";
        stl.textAlignment=NSTextAlignmentCenter;
        stl.font=[UIFont systemFontOfSize:11];
        stl.textColor=[UIColor colorWithWhite:0.5 alpha:1];
        [cbg addSubview:stl];

        UIView *dv=[[UIView alloc] initWithFrame:CGRectMake(16,116,W-32,1)];
        dv.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07]; [cbg addSubview:dv];

        NSArray *links=@[
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

        CGFloat ry=124;
        for (NSDictionary *item in links) {
            UIButton *row=[UIButton buttonWithType:UIButtonTypeCustom];
            row.frame=CGRectMake(12,ry,W-24,52);
            row.layer.cornerRadius=13; row.clipsToBounds=YES;
            row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.05];
            [row setBackgroundImage:[self imageWithColor:[UIColor colorWithWhite:1 alpha:0.12]]
                           forState:UIControlStateHighlighted];

            UIView *ib=[[UIView alloc] initWithFrame:CGRectMake(10,9,34,34)];
            ib.layer.cornerRadius=10; ib.clipsToBounds=YES;
            CAGradientLayer *ig=[CAGradientLayer layer]; ig.frame=ib.bounds;
            ig.colors=@[
                (__bridge id)[UIColor colorWithRed:[item[@"r1"] floatValue]
                    green:[item[@"g1"] floatValue] blue:[item[@"b1"] floatValue] alpha:0.9].CGColor,
                (__bridge id)[UIColor colorWithRed:[item[@"r2"] floatValue]
                    green:[item[@"g2"] floatValue] blue:[item[@"b2"] floatValue] alpha:0.9].CGColor,
            ];
            ig.startPoint=CGPointMake(0,0); ig.endPoint=CGPointMake(1,1);
            [ib.layer insertSublayer:ig atIndex:0];
            UILabel *il=[[UILabel alloc] initWithFrame:ib.bounds];
            il.text=item[@"icon"]; il.font=[UIFont systemFontOfSize:15];
            il.textAlignment=NSTextAlignmentCenter;
            [ib addSubview:il]; [row addSubview:ib];

            UILabel *tlt=[[UILabel alloc] initWithFrame:CGRectMake(52,8,W-90,20)];
            tlt.text=item[@"title"]; tlt.textColor=UIColor.whiteColor;
            tlt.font=[UIFont boldSystemFontOfSize:14]; tlt.userInteractionEnabled=NO;
            [row addSubview:tlt];

            UILabel *slt=[[UILabel alloc] initWithFrame:CGRectMake(52,28,W-90,15)];
            slt.text=item[@"sub"]; slt.textColor=[UIColor colorWithWhite:0.45 alpha:1];
            slt.font=[UIFont systemFontOfSize:11]; slt.userInteractionEnabled=NO;
            [row addSubview:slt];

            UILabel *arr=[[UILabel alloc] initWithFrame:CGRectMake(W-38,14,20,24)];
            arr.text=@"›"; arr.textColor=[UIColor colorWithWhite:0.4 alpha:1];
            arr.font=[UIFont boldSystemFontOfSize:20]; arr.userInteractionEnabled=NO;
            [row addSubview:arr];

            objc_setAssociatedObject(row,"url",item[@"url"],OBJC_ASSOCIATION_COPY_NONATOMIC);
            [row addTarget:[MiTiLinkHandler shared] action:@selector(buttonTapped:)
          forControlEvents:UIControlEventTouchUpInside];
            [cbg addSubview:row]; ry+=58;
        }

        UIView *barBg=[[UIView alloc] initWithFrame:CGRectMake(16,H-40,W-32,4)];
        barBg.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07];
        barBg.layer.cornerRadius=2; [cbg addSubview:barBg];

        UIView *bar=[[UIView alloc] initWithFrame:CGRectMake(0,0,W-32,4)];
        bar.layer.cornerRadius=2; bar.clipsToBounds=YES;
        CAGradientLayer *barG=[CAGradientLayer layer]; barG.frame=bar.bounds;
        barG.colors=@[
            (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1 alpha:1].CGColor,
        ];
        barG.startPoint=CGPointMake(0,0); barG.endPoint=CGPointMake(1,0);
        [bar.layer insertSublayer:barG atIndex:0]; [barBg addSubview:bar];

        UILabel *cntLbl=[[UILabel alloc] initWithFrame:CGRectMake(0,H-30,W,16)];
        cntLbl.text=@"Tự đóng sau 10 giây";
        cntLbl.textAlignment=NSTextAlignmentCenter;
        cntLbl.font=[UIFont systemFontOfSize:10];
        cntLbl.textColor=[UIColor colorWithWhite:0.35 alpha:1];
        [cbg addSubview:cntLbl];

        [UIView animateWithDuration:0.08 animations:^{
            dim.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.5];
        }];
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.75
              initialSpringVelocity:0.5 options:0 animations:^{
            card.frame=CGRectMake(X,Y,W,H);
        } completion:nil];

        void(^close)(void)=^{
            [UIView animateWithDuration:0.28 animations:^{
                card.alpha=0;
                card.transform=CGAffineTransformMakeScale(0.92,0.92);
                dim.backgroundColor=UIColor.clearColor;
            } completion:^(BOOL d){ win.hidden=YES; }];
        };

        __block NSInteger sec=10;
        CGFloat tw=W-32;
        NSTimer *tmr=[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t){
            sec--;
            dispatch_async(dispatch_get_main_queue(),^{
                cntLbl.text=[NSString stringWithFormat:@"Tự đóng sau %ld giây",(long)sec];
                [UIView animateWithDuration:0.8 animations:^{
                    bar.frame=CGRectMake(0,0,tw*MAX(0,sec/10.0),4);
                }];
                if(sec<=0){[t invalidate];close();}
            });
        }];
        [[NSRunLoop mainRunLoop] addTimer:tmr forMode:NSRunLoopCommonModes];

        UITapGestureRecognizer *dt=[[UITapGestureRecognizer alloc]
            initWithTarget:nil action:nil];
        [dt addTarget:^(__unused id x){[tmr invalidate];close();}
               action:@selector(invoke)];
        [dim addGestureRecognizer:dt];
    });
}
@end

// ── Constructor ──
__attribute__((constructor))
static void MiTiInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{
        [MiTiHUD start];
        [MiTiMenuManager install];
        [MiTiModGamesMenu show];
    });
}
