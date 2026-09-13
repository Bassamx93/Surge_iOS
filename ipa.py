#!/usr/bin/env python3
# IPA 构建脚本
#   1. 解压 com.nssurge.inc.surge-ios_5.22.0_und3fined.ipa(干净解密包)
#   2. 按 36 处偏移写入授权补丁字节(主程序 20 + NE 16)
#   3. CloudKit.dylib 放入 Frameworks,以 weak LC_LOAD_DYLIB 文件级注入全部 6 个
#      Mach-O(主程序 + 5 个 appex,含 NE);surge++.dylib 仅注入主 App
#   4. codesign ad-hoc 伪签名(dylib → 扩展 → 主程序最后密封),压缩为 patched IPA
import os, struct, shutil, subprocess, sys, tempfile, zipfile

RUNTIME_ONLY = os.environ.get("RUNTIME_ONLY") == "1"

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_IPA = os.path.join(ROOT, "com.nssurge.inc.surge-ios_5.22.0_und3fined.ipa")
# CloudKit.dylib = CloudKit.m  → 注入进程
# surge++.dylib  = Tweak.x + UI.x(模块注入/弹窗/License 自定义) → 仅注入主 App
CK_DYLIB = os.path.join(ROOT, ".theos/obj/debug/CloudKit.dylib")
SURGE_DYLIB = os.path.join(ROOT, "tweaklib/.theos/obj/debug/surge++.dylib")
EMBED_SURGE = True
OUT_IPA = os.path.join(ROOT, "com.nssurge.inc.surge-ios_5.22.0_patched.ipa")
if RUNTIME_ONLY:
    OUT_IPA = os.path.join(ROOT, "com.nssurge.inc.surge-ios_5.22.0_runtime-only.ipa")

MAIN_BIN = "Payload/Surge-iOS.app/Surge-iOS"
NE_BIN = "Payload/Surge-iOS.app/PlugIns/Surge-iOS-NE.appex/Surge-iOS-NE"
ALL_BINS = [
    MAIN_BIN,
    NE_BIN,
    "Payload/Surge-iOS.app/PlugIns/Surge-WE.appex/Surge-WE",
    "Payload/Surge-iOS.app/PlugIns/Surge-iOS-Safari-Extension.appex/Surge-iOS-Safari-Extension",
    "Payload/Surge-iOS.app/PlugIns/Surge-iOS-Widget.appex/Surge-iOS-Widget",
    "Payload/Surge-iOS.app/PlugIns/Surge-Extension.appex/Surge-Extension",
]

# ---- 36 处补丁(文件偏移, 长度, 已验证字节): 主程序 20 + NE 16 ----
MAIN_PATCHES = [
    (0x81a50, 36, "00c08ed240cfb2f20000629ee00314aac0591494fd031daafa311494e00f00f91f2003d5"),
    (0x81b14, 4, "0f000014"),
    (0x9f124, 8, "20008052c0035fd6"),
    (0x9f3e4, 4, "280080d2"),
    (0x1c5068, 4, "0b000014"),
    (0x1c514d, 3, "0080d2"),
    # 到期钳制: sub_1002672F4 授权到期
    (0x2672e8, 20, "40008052c0035fd6c0035fd6002089d2e08eadf2"),
    (0x2672f4,  8, "00c08ed240cfb2f2"),
    (0x267a44, 20, "20008052e830009008613691000100b9c0035fd6"),

    # SGRequestHelper TLS 锁定拒绝分支 NOP(激活 API 三 host 锁定 2016 自签证书,已过期;NOP 后服务器将来换证书不再切断激活 API。仅影响激活 host。)
    (0x19ce00, 4, "1f2003d5"),

    # 防断节点: setProFeatureState 内两处 setEnvironmentWithKey → NOP,
    (0x10009f484 - 0x100000000, 4, "1f2003d5"),
    (0x10009f4ac - 0x100000000, 4, "1f2003d5"),

    # 防断节点终极执行点: SGUAppDelegate proStatusDidUpdate: 内 stopWithCompletionHandler→ NOP
    (0x1198e4, 4, "1f2003d5"),
    (0x71f44, 8, "20008052c0035fd6"),    # MITM 开关isContextEditableAndShowAlert 恒 YES
    (0x3c4bc, 8, "20008052c0035fd6"),    # canEditProfile 恒 YES
    (0x38e54, 4, "3b000014"),            # updateCurrentProfileSettings 保存分支 编辑路径
    (0x261c1c, 4, "74000014"),           # 编辑页保存按钮恒走保存路径
    (0x43d00, 4, "3d000014"),            # 文本编辑器写盘块1恒走写盘
    (0xf720c, 4, "3c000014"),            # 文本编辑器写盘块2恒走写盘
    (0x342b8, 8, "20008052c0035fd6"),    # isICloudDriveAvailable 恒 YES (解除 iCloud 同步 UI 禁用)
]
NE_PATCHES = [
    (0x2f8e4, 8, "20008052c0035fd6"),
    (0x460d8, 4, "43008052"),
    (0x4e26c, 4, "43008052"),
    (0x4fbe8, 4, "43008052"),
    (0x5ee08, 4, "43008052"),
    (0x680cc, 4, "43008052"),
    (0x83948, 4, "43008052"),
    (0x89c4c, 4, "43008052"),
    (0xd6a2c, 4, "28008052"),
    (0xd6ee8, 4, "35008052"),
    (0xdadd4, 4, "36008052"),
    (0xdc380, 4, "35008052"),
    (0xdc424, 4, "28008052"),
    (0xdd944, 4, "33008052"),
    (0x20b920, 20, "20008052283100f008c11b91000100b9c0035fd6"),
    (0x28c2c8, 4, "1f2003d5"),
]

# RUNTIME_ONLY 保留的到期 补丁偏移
RUNTIME_KEEP_OFFSETS = (0x2672e8, 0x2672f4)

LIB_PATH = b"@rpath/CloudKit.dylib\x00"
SURGE_LIB_PATH = b"@rpath/surge++.dylib\x00"
LC_LOAD_WEAK_DYLIB = 0x18 | 0x80000000


def apply_patches(path, patches):
    data = bytearray(open(path, "rb").read())
    for off, size, hexstr in patches:
        new = bytes.fromhex(hexstr)
        assert len(new) == size, f"{path} 0x{off:x} 长度不符"
        old = bytes(data[off:off + size])
        if old == new:
            print(f"  0x{off:x} 已是补丁字节,跳过")
            continue
        data[off:off + size] = new
        print(f"  补丁 0x{off:x} ({size}B)")
    open(path, "wb").write(data)


def has_load_dylib(data, lib_path=LIB_PATH):
    ncmds, = struct.unpack_from("<I", data, 16)
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd & 0x7FFFFFFF in (0x0C, 0x18):
            name_off, = struct.unpack_from("<I", data, off + 8)
            end = data.find(b"\x00", off + name_off)
            if data[off + name_off:end] == lib_path[:-1]:
                return True
        off += size
    return False


def first_section_fileoff(data):
    ncmds, = struct.unpack_from("<I", data, 16)
    off = 32
    best = None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects, = struct.unpack_from("<I", data, off + 64)
            for i in range(nsects):
                s = off + 72 + i * 80
                _f, = struct.unpack_from("<I", data, s + 48)
                if _f and (best is None or _f < best):
                    best = _f
        off += size
    return best


def insert_weak_load(path, lib_path=LIB_PATH):
    data = bytearray(open(path, "rb").read())
    if has_load_dylib(data, lib_path):
        print(f"  已有 weak 引用,跳过: {os.path.basename(path)}")
        return
    ncmds, = struct.unpack_from("<I", data, 16)
    sizeofcmds, = struct.unpack_from("<I", data, 20)
    cmd_size = (24 + len(lib_path) + 7) & ~7
    cmd = struct.pack("<IIIIII", LC_LOAD_WEAK_DYLIB, cmd_size, 24, 0, 0, 0) + lib_path
    cmd += b"\x00" * (cmd_size - len(cmd))

    insert_at = 32 + sizeofcmds
    limit = first_section_fileoff(data) or (insert_at + cmd_size)
    if insert_at + cmd_size > limit:
        sys.exit(f"  无空闲空间插入 load 命令: {path}")
    if data[insert_at:insert_at + cmd_size].strip(b"\x00"):
        sys.exit(f"  插入位非零填充: {path}")

    data[insert_at:insert_at + cmd_size] = cmd
    struct.pack_into("<II", data, 16, ncmds + 1, sizeofcmds + cmd_size)
    open(path, "wb").write(data)
    print(f"  注入 weak LC_LOAD_DYLIB: {os.path.basename(path)} (ncmds {ncmds}->{ncmds + 1})")


def main():
    if RUNTIME_ONLY:
        main_patches = [p for p in MAIN_PATCHES if p[0] in RUNTIME_KEEP_OFFSETS]
        ne_patches = []
        print(f"RUNTIME_ONLY 实验形态: 主程序仅保留到期钳制 {len(main_patches)} 处, NE 0 处")
    else:
        main_patches, ne_patches = MAIN_PATCHES, NE_PATCHES
        print(f"应用 {len(main_patches) + len(ne_patches)} 处授权补丁(主 {len(main_patches)} + NE {len(ne_patches)})")
    if not os.path.exists(CK_DYLIB):
        sys.exit("缺少 CloudKit.dylib(先在根目录执行: make 编译 CloudKit.m)")
    work = tempfile.mkdtemp(prefix="sgipa_")
    payload = os.path.join(work, "Payload")
    print("解压 und3fined 干净包…")
    with zipfile.ZipFile(SRC_IPA) as z:
        z.extractall(work)

    apply_patches(os.path.join(work, MAIN_BIN), main_patches)
    if ne_patches:
        apply_patches(os.path.join(work, NE_BIN), ne_patches)

    print("剥离残留签名…")
    for rel in ALL_BINS:
        subprocess.run(["codesign", "--remove-signature", os.path.join(work, rel)],
                       capture_output=True)

    print("嵌入 CloudKit.dylib → 6 进程…")
    fw = os.path.join(payload, "Surge-iOS.app/Frameworks")
    os.makedirs(fw, exist_ok=True)
    embedded = os.path.join(fw, "CloudKit.dylib")
    shutil.copy2(CK_DYLIB, embedded)
    subprocess.run(["install_name_tool", "-id", "@rpath/CloudKit.dylib", embedded],
                   check=True, capture_output=True)
    for rel in ALL_BINS:
        insert_weak_load(os.path.join(work, rel))

    if EMBED_SURGE:
        if not os.path.exists(SURGE_DYLIB):
            sys.exit("缺少 tweaklib/.theos/obj/debug/surge++.dylib,请先在 tweaklib/ 下 make")
        print("嵌入 surge++.dylib(Tweak.x + UI.x)→ 仅主 App…")
        surge = os.path.join(fw, "surge++.dylib")
        shutil.copy2(SURGE_DYLIB, surge)
        subprocess.run(["install_name_tool", "-id", "@rpath/surge++.dylib", surge],
                       check=True, capture_output=True)
        insert_weak_load(os.path.join(work, MAIN_BIN), SURGE_LIB_PATH)

    print("ad-hoc 伪签名…")
    # 顺序是:dylib → 5 个扩展 → 主程序最后签
    subprocess.run(["codesign", "-f", "-s", "-", embedded], check=True, capture_output=True)
    if EMBED_SURGE:
        subprocess.run(["codesign", "-f", "-s", "-", surge], check=True, capture_output=True)
    for rel in ALL_BINS[1:]:
        subprocess.run(["codesign", "-f", "-s", "-", os.path.join(work, rel)],
                       check=True, capture_output=True)
    subprocess.run(["codesign", "-f", "-s", "-", os.path.join(work, MAIN_BIN)],
                   check=True, capture_output=True)

    print("压缩新 IPA…")
    if os.path.exists(OUT_IPA):
        os.remove(OUT_IPA)
    with zipfile.ZipFile(OUT_IPA, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, _, files in os.walk(work):
            for f in sorted(files):
                full = os.path.join(dirpath, f)
                z.write(full, os.path.relpath(full, work))
    shutil.rmtree(work)
    print(f"完成: {OUT_IPA} ({os.path.getsize(OUT_IPA)/1e6:.1f} MB)")


if __name__ == "__main__":
    main()
