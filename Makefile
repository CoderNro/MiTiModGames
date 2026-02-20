TARGET_NAME = MiTiModGames
SOURCES     = MiTiModGames.m
OUTPUT      = $(TARGET_NAME).dylib

SDK         = $(shell xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS     = 14.0
CLANG       = $(shell xcrun -f clang)

CFLAGS = \
    -fobjc-arc \
    -fmodules \
    -isysroot $(SDK) \
    -miphoneos-version-min=$(MIN_IOS) \
    -arch arm64 \
    -O2

LDFLAGS = \
    -dynamiclib \
    -isysroot $(SDK) \
    -miphoneos-version-min=$(MIN_IOS) \
    -arch arm64 \
    -framework UIKit \
    -framework Foundation \
    -framework QuartzCore \
    -Xlinker -install_name \
    -Xlinker @rpath/$(OUTPUT)

all: $(OUTPUT)

$(OUTPUT): $(SOURCES)
	$(CLANG) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "✅ Build thành công: $@"

clean:
	rm -f $(OUTPUT)
