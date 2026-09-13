ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = surge++
surge++_FILES = Tweak.x UI.x
surge++_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
surge++_LDFLAGS = -framework UIKit \
                  -framework Foundation \
                  -framework ImageIO \
                  -lc++ \
                  -Wl,-headerpad_max_install_names \
                  -Wl,-no_warn_inits

include $(THEOS_MAKE_PATH)/library.mk
