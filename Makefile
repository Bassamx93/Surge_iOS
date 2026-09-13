ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = CloudKit 
CloudKit_FILES = CloudKit.m fishhook.c
CloudKit_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
CloudKit_LDFLAGS = -framework Foundation \
                   -framework Security \
                   -lc++ \
                   -Wl,-headerpad_max_install_names \
                   -Wl,-no_warn_inits

include $(THEOS_MAKE_PATH)/library.mk
