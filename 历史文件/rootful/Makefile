# 插件：显编译成功，显示的信息
PACKAGE_IDENTIFIER = com.pxx917144686.Surge
PACKAGE_NAME = Surge++
PACKAGE_VERSION = 0.6.0
PACKAGE_ARCHITECTURE = arm64 arm64e
PACKAGE_REVISION = 1640
PACKAGE_SECTION = Tweaks
PACKAGE_DEPENDS = firmware (>= 14.0)
PACKAGE_DESCRIPTION = 修复 “已知问题”

# 插件：编译时，引用的信息
define Package/surge++
  Package: com.pxx917144686.surge
  Name: Surge++
  Version: 0.6.0
  Architecture: arm64 arm64e
  Author: pxx917144686
  Section: Tweaks
  Depends: firmware (>= 14.0)
  Description: 修复 “已知问题”
endef

# 直接输出到根路径
export THEOS_PACKAGE_DIR = $(CURDIR)

# TARGET
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

# 目标进程
INSTALL_TARGET_PROCESSES = Surge-iOS

# 引入 Theos 的通用设置
include $(THEOS)/makefiles/common.mk

# 插件名称
TWEAK_NAME = surge++

# 源代码文件
surge++_FILES = Tweak.x

# SHA256、MD5 等哈希算法、AES 等对称加密算法，需要OpenSSL！所以保留
# 添加 OpenSSL 头文件路径
surge++_CFLAGS = -fobjc-arc -I$(OPENSSL_PATH)/include

# OpenSSL 路径
OPENSSL_PATH = /Users/pxx917144686/openssl-ios

# 链接选项，添加 OpenSSL 库
surge++_LDFLAGS = -L$(OPENSSL_PATH)/lib -lssl -lcrypto \
                  -framework UIKit \
                  -framework Foundation \
                  -lc++

# Theos 编译规则
include $(THEOS_MAKE_PATH)/tweak.mk







# ========= 报错：ld: warning: -multiply_defined is obsolete ===========
# 解释：为什么会出现这个问题？
# 原因：新版本的 Apple 链接器 (ld64) 不再推荐使用 -multiply_defined；Theos 是为了兼容老的iOS，才默认加入了这个选项。
# 解决：在文件 theos/makefiles/targets/_common/darwin_tail.mk 打开文件，搜索找到并删除：-multiply_defined suppress





# ======= 使用 DobbyHook 替换 原有的 Hook 方法 MSHookFunction ========
# 克隆 Dobby 源码：(--depth=1 表示只下载最新版本)
# git clone https://github.com/jmpews/Dobby.git --depth=1
# 克隆 ios-cmake 工具链
# git clone https://github.com/leetal/ios-cmake.git

# 编译 Dobby
# 终端执行：cd Dobby
# 终端执行：mkdir build
# 终端执行：cd build
# 终端执行：cmake -DCMAKE_TOOLCHAIN_FILE=../ios-cmake/ios.toolchain.cmake \
# 终端执行：      -DPLATFORM=OS64 \
# 终端执行：      -DCMAKE_OSX_ARCHITECTURES=arm64e \
# 终端执行：      -DENABLE_PTRAUTH=ON \
# 终端执行：      -DCMAKE_C_FLAGS="-arch arm64e" \
# 终端执行：      -DCMAKE_CXX_FLAGS="-arch arm64e" ..
# 终端执行：make

# 验证: arm64 arm64e
# 终端执行：lipo -info libdobby.a

# 复制 libdobby.a 和 dobby.h 到当前项目的根目录
# Dobby/build/libdobby.a
# Dobby/include/dobby.h




# 解释：
# 报错：warning: ignoring file '/usr/local/Cellar/openssl@3/3.4.0/lib/libcrypto.3.dylib': found architecture 'x86_64', required architecture 'arm64e'

# 解释：英特尔的Mac x86_64 不匹配架构 OpenSSL 库。
# 检查： Mac架构方法，终端执行： uname -m
#                    输出： x86_64 表示 Intel Mac
#                    输出： arm64 表示 Apple Silicon Mac
# 解决Intel(x86_64)方法：
# 避免你耽误时间精力！理由：网络指导会产生 很多误导！会把你是Intel(x86_64) 实际是指导(arm64)的方法；
# 你使用Intel Mac（x86_64）在编译 iOS 插件时，目标架构应为 arm64 或 arm64e ；

# 一、下载 OpenSSL 官方源代码
# 终端执行下载文件：git clone https://github.com/openssl/openssl.git
# 终端执行cd OpenSSL，这是默认路径：cd openssl

# 终端执行：export PLATFORM="iPhoneOS"
# 终端执行：export SDK=$(xcrun --sdk iphoneos --show-sdk-path)
# 终端执行：export CC="$(xcrun --sdk iphoneos -f clang)"

# 设置支持多个架构，arm64 和 arm64e
# 终端执行：export ARCHS="arm64 arm64e"
# 终端执行：export CFLAGS="-arch arm64 -arch arm64e -isysroot $SDK -miphoneos-version-min=14.0"
# 终端执行：export LDFLAGS="-arch arm64 -arch arm64e -isysroot $SDK"

# 配置 OpenSSL 编译
# 终端执行：./Configure ios64-cross no-shared no-dso no-hw no-engine --prefix=$(PWD)/../openssl-ios


# 二、编译 OpenSSL：注意——> 时间 可能有点长！基于 你的电脑配置区别！
# 配置参数
# 终端执行： ./Configure ios64-cross no-shared no-dso no-hw no-engine --prefix=$(PWD)/../openssl-ios

# 清理缓存，避免旧文件干扰   
# 终端执行：make clean

# 编译OpenSSL   
# 终端执行：make

# 安装 OpenSSL 到指定目录   
# 终端执行：make install


# 三、验证你的编译是否是 arm64 架构：
# 终端执行：lipo -info ../openssl-ios/lib/libcrypto.a
# 终端执行：lipo -info ../openssl-ios/lib/libssl.a
# 成功的输出：libcrypto.a are: arm64 arm64e