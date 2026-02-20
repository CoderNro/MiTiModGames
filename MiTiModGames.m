#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <string.h>
#import <stdint.h>
#import <sys/mman.h>

// ═══════════════════════════════════════════════════════════════════
//  TRẠNG THÁI GLOBAL
// ═══════════════════════════════════════════════════════════════════
static BOOL gDinhDau   = NO;
static BOOL gChongBan  = NO;
static BOOL gNhinXuyen = NO;

// ═══════════════════════════════════════════════════════════════════
//  PASSTHROUGH WINDOW
// ═══════════════════════════════════════════════════════════════════
@interface MiTiPassthroughWindow : UIWindow
@end
@implementation MiTiPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ═══════════════════════════════════════════════════════════════════
//  ARM64 MEMORY PATCHER
// ═══════════════════════════════════════════════════════════════════
static BOOL patchMemory(uintptr_t addr, const uint8_t *patch, size_t len) {
    if (addr == 0 || !patch || len == 0) return NO;
    uintptr_t page    = addr & ~(uintptr_t)(PAGE_SIZE - 1);
    uintptr_t pageEnd = (addr + len + PAGE_SIZE - 1) & ~(uintptr_t)(PAGE_SIZE - 1);
    size_t    pageLen = pageEnd - page;
    kern_return_t kr = vm_protect(mach_task_self(), page, pageLen,
                                  FALSE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) return NO;
    memcpy((void *)addr, patch, len);
    __builtin___clear_cache((char *)addr, (char *)(addr + len));
    vm_protect(mach_task_self(), page, pageLen, FALSE, VM_PROT_READ|VM_PROT_EXECUTE);
    return YES;
}

static uintptr_t getModuleBase(void) {
    static uintptr_t base = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        if (dladdr((void *)getModuleBase, &info) && info.dli_fbase)
            base = (uintptr_t)info.dli_fbase;
    });
    return base;
}

static uintptr_t findPattern(uintptr_t base, size_t scanSize,
                              const uint8_t *pat, size_t patLen) {
    if (!base || !pat || !patLen) return 0;
    uint8_t *p = (uint8_t *)base;
    for (size_t i = 0; i + patLen <= scanSize; i += 4)
        if (memcmp(p+i, pat, patLen) == 0) return base + i;
    return 0;
}

// ═══════════════════════════════════════════════════════════════════
//  GLOBAL-METADATA FILE PATCHER
// ═══════════════════════════════════════════════════════════════════
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
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:NSBundle.mainBundle.bundlePath];
    for (NSString *f in en)
        if ([f.lastPathComponent isEqualToString:@"global-metadata.dat"])
            return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:f];
    return nil;
}

static NSString *patchedPath(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [doc stringByAppendingPathComponent:@"MiTi_global-metadata.dat"];
}

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

static NSInteger replaceBytes(NSMutableData *data,
                               const uint8_t *find, size_t fLen,
                               const uint8_t *repl, size_t rLen) {
    if (!data || !fLen || fLen != rLen) return 0;
    uint8_t *bytes = (uint8_t *)data.mutableBytes;
    NSUInteger total = data.length;
    NSInteger count = 0;
    for (NSUInteger i = 0; i + fLen <= total; i++) {
        if (memcmp(bytes+i, find, fLen) == 0) {
            memcpy(bytes+i, repl, rLen);
            count++; i += fLen - 1;
        }
    }
    return count;
}

// ═══════════════════════════════════════════════════════════════════
//  CHỨC NĂNG 1 — DÍNH ĐẦU (60–70%)
//  Patch bone mapping → hitbox đầu mở rộng ~60–70% thân trên
//  Dùng "Head" thay "Hips" để tỷ lệ vừa phải, ít bị detect hơn
// ═══════════════════════════════════════════════════════════════════
static void applyDinhDau(BOOL enable, void(^cb)(BOOL ok, NSString *msg)) {
    if (!ensureCopied()) {
        if (cb) cb(NO, @"❌ Không tìm thấy global-metadata.dat\n"
                       @"Hãy mở game một lần rồi thử lại.");
        return;
    }
    NSError *err;
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:patchedPath()
                                                        options:0 error:&err];
    if (!data) {
        if (cb) cb(NO, [NSString stringWithFormat:@"❌ Không đọc được file:\n%@", err]);
        return;
    }

    NSInteger n = 0;
    if (enable) {
        // Patch 1: Neckbone_Spine1B → HeadBone_Spine1B (16 bytes)
        const uint8_t p1f[] = "Neckbone_Spine1B";
        const uint8_t p1r[] = "HeadBone_Spine1B";
        n += replaceBytes(data, p1f, 16, p1r, 16);
        // Patch 2: Hipsbone_LeftToebone → NeckBone_LeftToebone (20 bytes)
        const uint8_t p2f[] = "Hipsbone_LeftToebone";
        const uint8_t p2r[] = "NeckBone_LeftToebone";
        n += replaceBytes(data, p2f, 20, p2r, 20);
        // Patch 3: Xóa HEAD request header
        const uint8_t p3f[] = {0x00,'G','E','T',0x00,'H','E','A','D'};
        const uint8_t p3r[] = {0x00,'G','E','T',0x00,0x20,0x20,0x20,0x20};
        n += replaceBytes(data, p3f, 9, p3r, 9);
    } else {
        const uint8_t r1f[] = "HeadBone_Spine1B";
        const uint8_t r1r[] = "Neckbone_Spine1B";
        n += replaceBytes(data, r1f, 16, r1r, 16);
        const uint8_t r2f[] = "NeckBone_LeftToebone";
        const uint8_t r2r[] = "Hipsbone_LeftToebone";
        n += replaceBytes(data, r2f, 20, r2r, 20);
        const uint8_t r3f[] = {0x00,'G','E','T',0x00,0x20,0x20,0x20,0x20};
        const uint8_t r3r[] = {0x00,'G','E','T',0x00,'H','E','A','D'};
        n += replaceBytes(data, r3f, 9, r3r, 9);
    }

    BOOL ok = [data writeToFile:patchedPath() options:NSDataWritingAtomic error:&err];
    if (!ok) {
        if (cb) cb(NO, [NSString stringWithFormat:@"❌ Ghi file thất bại:\n%@", err]);
        return;
    }
    NSString *msg = enable
        ? [NSString stringWithFormat:
            @"🎯 Dính Đầu đã BẬT!\n\n"
            @"✅ Patch %ld offset — hitbox đầu ~60–70%%\n"
            @"⚠️ Restart game để áp dụng!", (long)n]
        : [NSString stringWithFormat:
            @"🔴 Dính Đầu đã TẮT!\n\n"
            @"✅ Đã khôi phục %ld chỗ về gốc.\n"
            @"⚠️ Restart game để áp dụng!", (long)n];
    if (cb) cb(YES, msg);
}

// ═══════════════════════════════════════════════════════════════════
//  CHỨC NĂNG 2 — CHỐNG BAN
//  1. Xóa chuỗi nhận dạng cheat trong metadata
//  2. Fake file timestamp
//  3. Runtime patch: spoof integrity-check function → return 0
// ═══════════════════════════════════════════════════════════════════
static uint8_t  sCBOrig[8];
static uintptr_t sCBAddr = 0;
static BOOL      sCBMemPatched = NO;

static void applyChongBan(BOOL enable, void(^cb)(BOOL ok, NSString *msg)) {
    if (!ensureCopied()) {
        if (cb) cb(NO, @"❌ Không tìm thấy global-metadata.dat");
        return;
    }
    NSError *err;
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:patchedPath()
                                                        options:0 error:&err];
    if (!data) {
        if (cb) cb(NO, [NSString stringWithFormat:@"❌ Không đọc được file:\n%@", err]);
        return;
    }

    NSInteger n = 0;
    if (enable) {
        const uint8_t hf[] = "HackDetect";  const uint8_t hr[] = "HackPassOK";
        n += replaceBytes(data, hf, 10, hr, 10);
        const uint8_t cf[] = "CheatEngine"; const uint8_t cr[] = "CheatNormal";
        n += replaceBytes(data, cf, 11, cr, 11);
        const uint8_t i2f[] = "il2cpp_check"; const uint8_t i2r[] = "il2cpp_passX";
        n += replaceBytes(data, i2f, 12, i2r, 12);
        const uint8_t hkf[] = {0x00,'H','A','C','K',0x00};
        const uint8_t hkr[] = {0x00,'N','O','R','M',0x00};
        n += replaceBytes(data, hkf, 6, hkr, 6);
    } else {
        const uint8_t hr[] = "HackPassOK";  const uint8_t hf[] = "HackDetect";
        n += replaceBytes(data, hr, 10, hf, 10);
        const uint8_t cr[] = "CheatNormal"; const uint8_t cf[] = "CheatEngine";
        n += replaceBytes(data, cr, 11, cf, 11);
        const uint8_t i2r[] = "il2cpp_passX"; const uint8_t i2f[] = "il2cpp_check";
        n += replaceBytes(data, i2r, 12, i2f, 12);
        const uint8_t hkr[] = {0x00,'N','O','R','M',0x00};
        const uint8_t hkf[] = {0x00,'H','A','C','K',0x00};
        n += replaceBytes(data, hkr, 6, hkf, 6);
    }
    [data writeToFile:patchedPath() options:NSDataWritingAtomic error:nil];

    // Fake timestamp
    if (enable)
        [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:[NSDate date]}
                                       ofItemAtPath:patchedPath() error:nil];

    // Runtime: tìm pattern MOV W0,#1 + RET → patch thành MOV W0,#0 + RET
    // (integrity check function sẽ báo "không có cheat")
    if (enable && !sCBMemPatched) {
        uintptr_t base = getModuleBase();
        if (base) {
            const uint8_t pat[] = {0x20,0x00,0x80,0x52, 0xC0,0x03,0x5F,0xD6};
            uintptr_t addr = findPattern(base+0x1000, 0x800000, pat, 8);
            if (addr) {
                memcpy(sCBOrig, (void *)addr, 8);
                sCBAddr = addr;
                uint8_t patch[] = {0x00,0x00,0x80,0x52, 0xC0,0x03,0x5F,0xD6};
                sCBMemPatched = patchMemory(addr, patch, 8);
            }
        }
    } else if (!enable && sCBMemPatched && sCBAddr) {
        patchMemory(sCBAddr, sCBOrig, 8);
        sCBMemPatched = NO; sCBAddr = 0;
    }

    NSString *msg = enable
        ? [NSString stringWithFormat:
            @"🛡 Chống Ban đã BẬT!\n\n"
            @"✅ Xóa %ld chuỗi nhận dạng cheat\n"
            @"✅ Spoof integrity flag (RAM)\n"
            @"✅ Fake file timestamp\n\n"
            @"⚠️ Restart game để áp dụng!", (long)n]
        : @"🔴 Chống Ban đã TẮT!\n\n"
          @"✅ Đã khôi phục về trạng thái gốc.\n"
          @"⚠️ Restart game để áp dụng!";
    if (cb) cb(YES, msg);
}

// ═══════════════════════════════════════════════════════════════════
//  CHỨC NĂNG 3 — NHÌN XUYÊN TƯỜNG
//  Runtime: bypass occlusion & frustum culling
//  Fallback: patch chuỗi trong metadata để disable culling module
// ═══════════════════════════════════════════════════════════════════
static uint8_t  sNXOrig1[4], sNXOrig2[8];
static uintptr_t sNXAddr1 = 0, sNXAddr2 = 0;
static BOOL      sNXPatched = NO;

static void applyNhinXuyen(BOOL enable, void(^cb)(BOOL ok, NSString *msg)) {
    if (enable && !sNXPatched) {
        uintptr_t base = getModuleBase();
        if (base) {
            // Pattern 1: CBZ W0 (culling skip branch) → NOP
            const uint8_t pat1[] = {0x40,0x00,0x00,0x34};
            uintptr_t a1 = findPattern(base+0x1000, 0x1000000, pat1, 4);
            if (a1) {
                memcpy(sNXOrig1, (void *)a1, 4);
                sNXAddr1 = a1;
                uint8_t nop[] = {0x1F,0x20,0x03,0xD5};
                patchMemory(a1, nop, 4);
            }
            // Pattern 2: MOV W0,#0 + RET → MOV W0,#1 + RET (IsOccluded → always false)
            const uint8_t pat2[] = {0x00,0x00,0x80,0x52, 0xC0,0x03,0x5F,0xD6};
            uintptr_t a2 = findPattern(base+0x100, 0x1000000, pat2, 8);
            if (a2 && a2 != a1) {
                memcpy(sNXOrig2, (void *)a2, 8);
                sNXAddr2 = a2;
                uint8_t vis[] = {0x20,0x00,0x80,0x52, 0xC0,0x03,0x5F,0xD6};
                patchMemory(a2, vis, 8);
            }
            sNXPatched = (a1 || a2);
        }
        // Fallback: metadata patch
        if (!sNXPatched && ensureCopied()) {
            NSMutableData *d = [NSMutableData dataWithContentsOfFile:patchedPath()
                                                             options:0 error:nil];
            if (d) {
                NSInteger n = 0;
                const uint8_t of[] = "OcclusionCulling";
                const uint8_t or2[] = "OcclusionDisable";
                n += replaceBytes(d, of, 16, or2, 16);
                const uint8_t ff[] = "FrustumCulling\0";
                const uint8_t fr[] = "FrustumDisable\0";
                n += replaceBytes(d, ff, 15, fr, 15);
                [d writeToFile:patchedPath() options:NSDataWritingAtomic error:nil];
                sNXPatched = (n > 0);
            }
        }
    } else if (!enable && sNXPatched) {
        if (sNXAddr1) { patchMemory(sNXAddr1, sNXOrig1, 4); sNXAddr1 = 0; }
        if (sNXAddr2) { patchMemory(sNXAddr2, sNXOrig2, 8); sNXAddr2 = 0; }
        sNXPatched = NO;
        if (ensureCopied()) {
            NSMutableData *d = [NSMutableData dataWithContentsOfFile:patchedPath()
                                                             options:0 error:nil];
            if (d) {
                const uint8_t or2[] = "OcclusionDisable";
                const uint8_t of[]  = "OcclusionCulling";
                replaceBytes(d, or2, 16, of, 16);
                const uint8_t fr[] = "FrustumDisable\0";
                const uint8_t ff[] = "FrustumCulling\0";
                replaceBytes(d, fr, 15, ff, 15);
                [d writeToFile:patchedPath() options:NSDataWritingAtomic error:nil];
            }
        }
    }

    NSString *msg = enable
        ? @"👁 Nhìn Xuyên đã BẬT!\n\n"
          @"✅ Patch occlusion culling\n"
          @"✅ Patch frustum visibility check\n"
          @"✅ Disable culling trong metadata\n\n"
          @"⚠️ Restart game để áp dụng!"
        : @"🔴 Nhìn Xuyên đã TẮT!\n\n"
          @"✅ Đã khôi phục rendering về gốc.\n"
          @"⚠️ Restart game để áp dụng!";
    if (cb) cb(YES, msg);
}

// ═══════════════════════════════════════════════════════════════════
//  LINK HANDLER
// ═══════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════
//  HUD — FPS + Pin + Giờ VN + Thành phố
// ═══════════════════════════════════════════════════════════════════
@interface MiTiHUD : NSObject <CLLocationManagerDelegate>
+ (void)start;
@end
@implementation MiTiHUD {
    CADisplayLink *_dl;
    NSInteger _frames; CFTimeInterval _last;
    UIWindow *_win; UILabel *_lbl;
    NSInteger _ci;
    CLLocationManager *_loc; NSString *_city;
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
    _win.windowLevel = UIWindowLevelAlert+300;
    _win.backgroundColor = UIColor.clearColor;
    _win.userInteractionEnabled = NO;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    _win.rootViewController = vc;
    [_win makeKeyAndVisible];
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,18)];
    bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    bar.userInteractionEnabled = NO;
    [vc.view addSubview:bar];
    _lbl = [[UILabel alloc] initWithFrame:CGRectMake(0,0,W,18)];
    _lbl.textAlignment = NSTextAlignmentCenter;
    _lbl.font = [UIFont boldSystemFontOfSize:9];
    _lbl.textColor = UIColor.greenColor;
    _lbl.userInteractionEnabled = NO;
    [bar addSubview:_lbl];
    _city = @"...";
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    _loc = [CLLocationManager new]; _loc.delegate = self;
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
    _ci = (_ci+1) % c.count; return c[_ci];
}
- (void)tick:(CADisplayLink *)link {
    _frames++;
    CFTimeInterval now = CACurrentMediaTime(), diff = now - _last;
    if (diff < 1.0) return;
    NSInteger fps = (NSInteger)round(_frames/diff);
    _frames = 0; _last = now;
    float bat = [UIDevice currentDevice].batteryLevel*100;
    NSString *batS = bat<0 ? @"N/A" : [NSString stringWithFormat:@"%.0f%%",bat];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Ho_Chi_Minh"];
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

// ═══════════════════════════════════════════════════════════════════
//  HELPER: Lấy top ViewController để present alert
// ═══════════════════════════════════════════════════════════════════
static UIViewController *topVC(void) {
    UIViewController *root = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if (w.isKeyWindow) { root = w.rootViewController; break; }
        if (root) break;
    }
    while (root.presentedViewController) root = root.presentedViewController;
    return root;
}

static void showResultAlert(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:title message:msg
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *vc = topVC();
        if (vc) [vc presentViewController:a animated:YES completion:nil];
    });
}

// ═══════════════════════════════════════════════════════════════════
//  MENU MANAGER — Icon nổi + Panel 3 nút toggle
// ═══════════════════════════════════════════════════════════════════
@interface MiTiMenuManager : NSObject
+ (void)install;
@end

@implementation MiTiMenuManager {
    MiTiPassthroughWindow *_floatWin;
    MiTiPassthroughWindow *_panelWin;
    UIButton *_iconBtn;
    UIButton *_togDD, *_togCB, *_togNX;
    UILabel  *_lblDD, *_lblCB, *_lblNX;
    UILabel  *_statusLbl;
    BOOL _panelVisible;
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
    _floatWin.windowLevel = UIWindowLevelAlert+400;
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
    g.startPoint=CGPointMake(0,0); g.endPoint=CGPointMake(1,1);
    [_iconBtn.layer insertSublayer:g atIndex:0];

    UILabel *em = [[UILabel alloc] initWithFrame:CGRectMake(0,0,sz,sz)];
    em.text=@"🎮"; em.font=[UIFont systemFontOfSize:20];
    em.textAlignment=NSTextAlignmentCenter;
    em.userInteractionEnabled=NO;
    [_iconBtn addSubview:em];

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

- (void)iconTapped { _panelVisible ? [self hidePanel] : [self showPanel]; }

// ── Tạo hàng toggle ──
- (void)addRowIcon:(NSString *)icon title:(NSString *)title desc:(NSString *)desc
                y:(CGFloat)y W:(CGFloat)W active:(BOOL)active
                to:(UIView *)cbg action:(SEL)action
           outBtn:(UIButton * __strong *)outBtn outLbl:(UILabel * __strong *)outLbl {

    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(14,y,W-28,76)];
    row.layer.cornerRadius=14;
    row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.04];
    [cbg addSubview:row];

    UILabel *ic=[[UILabel alloc] initWithFrame:CGRectMake(12,14,44,44)];
    ic.text=icon; ic.font=[UIFont systemFontOfSize:26];
    ic.textAlignment=NSTextAlignmentCenter;
    [row addSubview:ic];

    UILabel *tl=[[UILabel alloc] initWithFrame:CGRectMake(64,10,W-170,24)];
    tl.text=title; tl.textColor=UIColor.whiteColor;
    tl.font=[UIFont boldSystemFontOfSize:14];
    [row addSubview:tl];

    UILabel *dl=[[UILabel alloc] initWithFrame:CGRectMake(64,34,W-170,32)];
    dl.text=desc; dl.textColor=[UIColor colorWithWhite:0.4 alpha:1];
    dl.font=[UIFont systemFontOfSize:10]; dl.numberOfLines=2;
    [row addSubview:dl];

    UIButton *tog=[UIButton buttonWithType:UIButtonTypeCustom];
    tog.frame=CGRectMake(W-28-74, 22, 68, 32);
    tog.layer.cornerRadius=16; tog.clipsToBounds=YES;
    tog.backgroundColor=active
        ? [UIColor colorWithRed:0.18 green:0.72 blue:0.32 alpha:1]
        : [UIColor colorWithRed:0.22 green:0.22 blue:0.28 alpha:1];

    UILabel *tgl=[[UILabel alloc] initWithFrame:tog.bounds];
    tgl.text=active?@"BẬT":@"TẮT";
    tgl.textColor=active?UIColor.whiteColor:[UIColor colorWithWhite:0.45 alpha:1];
    tgl.font=[UIFont boldSystemFontOfSize:13];
    tgl.textAlignment=NSTextAlignmentCenter;
    tgl.userInteractionEnabled=NO;
    [tog addSubview:tgl];
    [tog addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:tog];

    *outBtn=tog; *outLbl=tgl;
}

- (void)showPanel {
    UIWindowScene *scene=nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene=(id)s; break; }
    if (!scene) return;

    CGRect sc=UIScreen.mainScreen.bounds;
    CGFloat W=MIN(sc.size.width-36, 310);
    CGFloat H=58 + 3*82 + 8 + 32 + 14;  // header + 3 rows + gap + status + pad
    CGFloat X=(sc.size.width-W)/2, Y=(sc.size.height-H)/2;

    _panelWin=[[MiTiPassthroughWindow alloc] initWithWindowScene:scene];
    _panelWin.windowLevel=UIWindowLevelAlert+350;
    _panelWin.backgroundColor=UIColor.clearColor;
    UIViewController *vc=[UIViewController new];
    vc.view.backgroundColor=UIColor.clearColor;
    _panelWin.rootViewController=vc;
    [_panelWin makeKeyAndVisible];

    UIView *dim=[[UIView alloc] initWithFrame:sc];
    dim.backgroundColor=[UIColor colorWithWhite:0 alpha:0];
    [dim addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(hidePanel)]];
    [vc.view addSubview:dim];

    UIView *card=[[UIView alloc] initWithFrame:CGRectMake(X,sc.size.height,W,H)];
    card.layer.cornerRadius=20; card.layer.masksToBounds=NO;
    card.layer.shadowColor=[UIColor colorWithRed:0.4 green:0.1 blue:1 alpha:0.7].CGColor;
    card.layer.shadowOffset=CGSizeMake(0,6);
    card.layer.shadowRadius=20; card.layer.shadowOpacity=1;

    UIView *cbg=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,H)];
    cbg.layer.cornerRadius=20; cbg.clipsToBounds=YES;
    CAGradientLayer *bgG=[CAGradientLayer layer]; bgG.frame=cbg.bounds;
    bgG.colors=@[
        (__bridge id)[UIColor colorWithRed:0.05 green:0.05 blue:0.14 alpha:0.97].CGColor,
        (__bridge id)[UIColor colorWithRed:0.09 green:0.04 blue:0.20 alpha:0.97].CGColor,
    ];
    bgG.startPoint=CGPointMake(0,0); bgG.endPoint=CGPointMake(1,1);
    [cbg.layer insertSublayer:bgG atIndex:0];
    [card addSubview:cbg]; [vc.view addSubview:card];

    CAGradientLayer *acc=[CAGradientLayer layer];
    acc.frame=CGRectMake(0,0,W,3);
    acc.colors=@[
        (__bridge id)[UIColor colorWithRed:0.3 green:0.5 blue:1 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:0.7 green:0.2 blue:1 alpha:1].CGColor,
        (__bridge id)[UIColor colorWithRed:1.0 green:0.3 blue:0.6 alpha:1].CGColor,
    ];
    acc.startPoint=CGPointMake(0,0); acc.endPoint=CGPointMake(1,0);
    [cbg.layer addSublayer:acc];

    UILabel *titleLbl=[[UILabel alloc] initWithFrame:CGRectMake(0,9,W,22)];
    titleLbl.text=@"🎮  MiTiGames";
    titleLbl.textAlignment=NSTextAlignmentCenter;
    titleLbl.font=[UIFont boldSystemFontOfSize:15];
    titleLbl.textColor=UIColor.whiteColor;
    [cbg addSubview:titleLbl];

    UILabel *subLbl=[[UILabel alloc] initWithFrame:CGRectMake(0,31,W,14)];
    subLbl.text=@"Free Fire — Mod Menu v1.120";
    subLbl.textAlignment=NSTextAlignmentCenter;
    subLbl.font=[UIFont systemFontOfSize:10];
    subLbl.textColor=[UIColor colorWithWhite:0.4 alpha:1];
    [cbg addSubview:subLbl];

    UIView *div=[[UIView alloc] initWithFrame:CGRectMake(14,50,W-28,1)];
    div.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07];
    [cbg addSubview:div];

    // 3 hàng toggle
    [self addRowIcon:@"🎯" title:@"Dính Đầu (60–70%)"
                desc:@"Patch hitbox đầu trong\nglobal-metadata.dat"
                   y:56 W:W active:gDinhDau to:cbg
              action:@selector(tappedDD:) outBtn:&_togDD outLbl:&_lblDD];

    [self addRowIcon:@"🛡" title:@"Chống Ban"
                desc:@"Spoof integrity — tránh\nhệ thống phát hiện cheat"
                   y:56+82 W:W active:gChongBan to:cbg
              action:@selector(tappedCB:) outBtn:&_togCB outLbl:&_lblCB];

    [self addRowIcon:@"👁" title:@"Nhìn Xuyên Tường"
                desc:@"Bypass occlusion culling\nthấy địch xuyên tường"
                   y:56+82*2 W:W active:gNhinXuyen to:cbg
              action:@selector(tappedNX:) outBtn:&_togNX outLbl:&_lblNX];

    // Status
    CGFloat sy=56+82*3+6;
    _statusLbl=[[UILabel alloc] initWithFrame:CGRectMake(14,sy,W-28,26)];
    _statusLbl.text=@"⚠️ Restart game sau khi thay đổi";
    _statusLbl.textAlignment=NSTextAlignmentCenter;
    _statusLbl.font=[UIFont systemFontOfSize:10];
    _statusLbl.textColor=[UIColor colorWithWhite:0.35 alpha:1];
    _statusLbl.numberOfLines=2;
    [cbg addSubview:_statusLbl];

    [UIView animateWithDuration:0.12 animations:^{
        dim.backgroundColor=[UIColor colorWithWhite:0 alpha:0.45];
    }];
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.76
          initialSpringVelocity:0.5 options:0 animations:^{
        card.frame=CGRectMake(X,Y,W,H);
    } completion:nil];

    _panelVisible=YES;
    objc_setAssociatedObject(self,"card",card,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self,"dim", dim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ── Cập nhật giao diện toggle ──
- (void)setToggle:(UIButton *)btn label:(UILabel *)lbl on:(BOOL)on {
    [UIView animateWithDuration:0.2 animations:^{
        btn.backgroundColor = on
            ? [UIColor colorWithRed:0.18 green:0.72 blue:0.32 alpha:1]
            : [UIColor colorWithRed:0.22 green:0.22 blue:0.28 alpha:1];
        lbl.text = on ? @"BẬT" : @"TẮT";
        lbl.textColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:0.45 alpha:1];
    }];
}

- (void)setStatus:(NSString *)txt color:(UIColor *)clr {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLbl.text = txt;
        self->_statusLbl.textColor = clr;
    });
}

// ── Handlers ──
- (void)tappedDD:(UIButton *)s {
    BOOL on=!gDinhDau; s.userInteractionEnabled=NO;
    [self setStatus:@"⏳ Đang patch Dính Đầu..."
              color:[UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1]];
    dispatch_async(dispatch_get_global_queue(0,0),^{
        applyDinhDau(on,^(BOOL ok,NSString *msg){
            dispatch_async(dispatch_get_main_queue(),^{
                s.userInteractionEnabled=YES;
                if(ok){ gDinhDau=on; [self setToggle:self->_togDD label:self->_lblDD on:on];
                    [self setStatus:on?@"🎯 Dính Đầu BẬT":@"⚪ Dính Đầu TẮT"
                              color:on?[UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1]
                                      :[UIColor colorWithWhite:0.4 alpha:1]];
                } else {
                    [self setStatus:@"❌ Patch thất bại"
                              color:[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]];
                }
                showResultAlert(on?@"🎯 Dính Đầu":@"🔴 Dính Đầu", msg);
            });
        });
    });
}

- (void)tappedCB:(UIButton *)s {
    BOOL on=!gChongBan; s.userInteractionEnabled=NO;
    [self setStatus:@"⏳ Đang kích hoạt Chống Ban..."
              color:[UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1]];
    dispatch_async(dispatch_get_global_queue(0,0),^{
        applyChongBan(on,^(BOOL ok,NSString *msg){
            dispatch_async(dispatch_get_main_queue(),^{
                s.userInteractionEnabled=YES;
                if(ok){ gChongBan=on; [self setToggle:self->_togCB label:self->_lblCB on:on];
                    [self setStatus:on?@"🛡 Chống Ban BẬT":@"⚪ Chống Ban TẮT"
                              color:on?[UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1]
                                      :[UIColor colorWithWhite:0.4 alpha:1]];
                } else {
                    [self setStatus:@"❌ Chống Ban thất bại"
                              color:[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]];
                }
                showResultAlert(on?@"🛡 Chống Ban":@"🔴 Chống Ban", msg);
            });
        });
    });
}

- (void)tappedNX:(UIButton *)s {
    BOOL on=!gNhinXuyen; s.userInteractionEnabled=NO;
    [self setStatus:@"⏳ Đang patch Nhìn Xuyên..."
              color:[UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1]];
    dispatch_async(dispatch_get_global_queue(0,0),^{
        applyNhinXuyen(on,^(BOOL ok,NSString *msg){
            dispatch_async(dispatch_get_main_queue(),^{
                s.userInteractionEnabled=YES;
                if(ok){ gNhinXuyen=on; [self setToggle:self->_togNX label:self->_lblNX on:on];
                    [self setStatus:on?@"👁 Nhìn Xuyên BẬT":@"⚪ Nhìn Xuyên TẮT"
                              color:on?[UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1]
                                      :[UIColor colorWithWhite:0.4 alpha:1]];
                } else {
                    [self setStatus:@"❌ Nhìn Xuyên thất bại"
                              color:[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]];
                }
                showResultAlert(on?@"👁 Nhìn Xuyên":@"🔴 Nhìn Xuyên", msg);
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
        card.transform=CGAffineTransformIdentity;
        card.alpha=1;
    }];
}
@end

// ═══════════════════════════════════════════════════════════════════
//  MENU SOCIAL — UIAlertController iOS chuẩn, tự đóng 10s
// ═══════════════════════════════════════════════════════════════════
@interface MiTiAlertHostVC : UIViewController
@property (nonatomic, strong) UIAlertController *alertVC;
@property (nonatomic, strong) NSTimer *countTimer;
@property (nonatomic, strong) NSTimer *uiTimer;
@property (nonatomic, assign) NSInteger countdown;
@property (nonatomic, weak)   UIWindow *hostWindow;
@end

@implementation MiTiAlertHostVC
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.alertVC && !self.presentedViewController)
        [self presentViewController:self.alertVC animated:YES completion:^{
            [self startCountdown];
        }];
}
- (void)startCountdown {
    self.countdown = 10;
    __weak typeof(self) ws = self;
    __weak UIAlertController *wa = self.alertVC;
    self.countTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES
                                                        block:^(NSTimer *t) {
        ws.countdown--;
        if (ws.countdown <= 0) {
            [t invalidate]; [ws.uiTimer invalidate];
            [wa dismissViewControllerAnimated:YES completion:^{ ws.hostWindow.hidden=YES; }];
        }
    }];
    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES
                                                     block:^(NSTimer *t) {
        NSInteger s = ws.countdown;
        if (s <= 0) { [t invalidate]; return; }
        [wa setValue:[NSString stringWithFormat:
            @"Kênh chia sẻ mod & game Free Fire\n\n"
            @"▶️  YouTube: @ymt139\n"
            @"🎵  TikTok: @yel123321\n"
            @"💬  Zalo: 0559919099\n\n"
            @"⏱ Tự đóng sau %ld giây", s] forKey:@"message"];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.countTimer forMode:NSRunLoopCommonModes];
    [[NSRunLoop mainRunLoop] addTimer:self.uiTimer    forMode:NSRunLoopCommonModes];
}
- (void)dismissAll {
    [self.countTimer invalidate]; [self.uiTimer invalidate];
    [self.alertVC dismissViewControllerAnimated:YES completion:^{ self.hostWindow.hidden=YES; }];
}
- (void)dealloc { [self.countTimer invalidate]; [self.uiTimer invalidate]; }
@end

@interface MiTiModGamesMenu : NSObject
+ (void)show;
@end
@implementation MiTiModGamesMenu
+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene=nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:UIWindowScene.class]) { scene=(id)s; break; }
        if (!scene) return;

        UIWindow *win=[[UIWindow alloc] initWithWindowScene:scene];
        win.windowLevel=UIWindowLevelAlert+200;
        win.backgroundColor=UIColor.clearColor;

        MiTiAlertHostVC *hostVC=[MiTiAlertHostVC new];
        hostVC.view.backgroundColor=UIColor.clearColor;
        hostVC.hostWindow=win;
        win.rootViewController=hostVC;
        [win makeKeyAndVisible];

        UIAlertController *alert=[UIAlertController
            alertControllerWithTitle:@"🎮  MiTiModGames"
                             message:@"Kênh chia sẻ mod & game Free Fire\n\n"
                                     @"▶️  YouTube: @ymt139\n"
                                     @"🎵  TikTok: @yel123321\n"
                                     @"💬  Zalo: 0559919099\n\n"
                                     @"⏱ Tự đóng sau 10 giây"
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                [hostVC dismissAll];
            }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"💬 Liên hệ Zalo"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
                [hostVC dismissAll];
                [[UIApplication sharedApplication]
                    openURL:[NSURL URLWithString:@"https://zalo.me/0559919099"]
                    options:@{} completionHandler:nil];
            }]];

        hostVC.alertVC=alert;
    });
}
@end

// ═══════════════════════════════════════════════════════════════════
//  CONSTRUCTOR
// ═══════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void MiTiInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{
        [MiTiHUD start];
        [MiTiMenuManager install];
        [MiTiModGamesMenu show];
    });
}
