#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "fishhook.h"

static NSString *accessGroupId = nil;
static NSString *bundleId = nil;
static IMP o_CKSetup = NULL;
static IMP o_CKInit = NULL;
static OSStatus (*p_SecAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*p_SecCopy)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*p_SecUpdate)(CFDictionaryRef, CFDictionaryRef, CFTypeRef *);
static OSStatus (*p_SecDelete)(CFDictionaryRef);

static NSMutableDictionary *SecMutable(CFDictionaryRef q) {
    NSMutableDictionary *m = [(__bridge NSDictionary *)q mutableCopy];
    m[(__bridge NSString *)kSecAttrAccessGroup] = accessGroupId;
    return m;
}

static OSStatus hook_SecAdd(CFDictionaryRef attrs, CFTypeRef *result) {
    return p_SecAdd((__bridge CFDictionaryRef)SecMutable(attrs), result);
}

static OSStatus hook_SecCopy(CFDictionaryRef query, CFTypeRef *result) {
    return p_SecCopy((__bridge CFDictionaryRef)SecMutable(query), result);
}

static OSStatus hook_SecUpdate(CFDictionaryRef query, CFDictionaryRef attrsToUpdate, CFTypeRef *result) {
    return p_SecUpdate((__bridge CFDictionaryRef)SecMutable(query), attrsToUpdate, result);
}

static OSStatus hook_SecDelete(CFDictionaryRef query) {
    return p_SecDelete((__bridge CFDictionaryRef)SecMutable(query));
}

static void SGRebindSecFuncs(void) {
    struct rebinding r[4] = {
        {"SecItemAdd",         (void *)hook_SecAdd,   (void **)&p_SecAdd},
        {"SecItemCopyMatching",(void *)hook_SecCopy,  (void **)&p_SecCopy},
        {"SecItemUpdate",      (void *)hook_SecUpdate,(void **)&p_SecUpdate},
        {"SecItemDelete",      (void *)hook_SecDelete,(void **)&p_SecDelete},
    };
    rebind_symbols(r, 4);
}

static void SGBootstrapKeychain(void) {
    NSDictionary *q = [@{
        (__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrAccount: @"",
        (__bridge NSString *)kSecAttrService: @"surge_PluginsInjectGenericEntry",
        (__bridge NSString *)kSecReturnAttributes: @YES,
    } copy];
    CFTypeRef cf = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &cf);
    if (st == errSecItemNotFound) st = SecItemAdd((__bridge CFDictionaryRef)q, &cf);
    if (st == errSecSuccess && cf) {
        bundleId = [NSBundle mainBundle].bundleIdentifier;
        NSDictionary *attrs = CFBridgingRelease(cf);
        accessGroupId = attrs[(__bridge NSString *)kSecAttrAccessGroup];
    }
    SGRebindSecFuncs();
}

static NSURL *SGGetAppGroupURL(void) {
    static NSURL *u = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass("LSBundleProxy");
        id proxy = cls ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(bundleProxyForCurrentProcess)) : nil;
        if (!proxy) return;
        id ent = ((id (*)(id, SEL))objc_msgSend)(proxy, @selector(entitlements));
        if (![ent isKindOfClass:[NSDictionary class]]) return;
        NSArray *groups = ent[@"com.apple.security.application-groups"];
        if (!groups || groups.count == 0) return;
        NSString *name = groups.firstObject;
        id gurls = ((id (*)(id, SEL))objc_msgSend)(proxy, @selector(groupContainerURLs));
        if (![gurls isKindOfClass:[NSDictionary class]]) return;
        NSURL *gu = gurls[name];
        if (!gu) return;
        u = [gu copy];
    });
    return u;
}

static void SGCreateDir(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                               withIntermediateDirectories:YES attributes:nil error:nil];
}


static id h_CKSetupNil(id self, SEL _cmd, id a, id b) { return nil; }
static id h_CKInitNil(id self, SEL _cmd, id a) { return nil; }

static IMP h_CKEntImp = NULL;
static id h_CKEntitlementsInit(id self, SEL _cmd, NSDictionary *dict) {
    NSMutableDictionary *dd = [dict isKindOfClass:[NSDictionary class]]
        ? [dict mutableCopy] : [NSMutableDictionary dictionary];
    [dd removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
    [dd removeObjectForKey:@"com.apple.developer.icloud-services"];
    return ((id (*)(id, SEL, id))h_CKEntImp)(self, _cmd, [dd copy]);
}

static IMP h_ContainerURLImp = NULL;
static NSURL *h_ContainerURLFn(id self, SEL _cmd, NSString *groupID) {
    NSURL *base = SGGetAppGroupURL();
    if (base) {
        NSURL *u = [base URLByAppendingPathComponent:groupID];
        SGCreateDir(u.path);
        return u;
    }
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = [docs.lastObject stringByAppendingPathComponent:groupID];
    SGCreateDir(dir);
    return [NSURL fileURLWithPath:dir];
}

static IMP h_SuiteInitImp = NULL;
static id h_SuiteInitFn(id self, SEL _cmd, NSString *suiteName, NSURL *container) {
    NSURL *base = SGGetAppGroupURL();
    if (!base) return ((id (*)(id, SEL, id, id))h_SuiteInitImp)(self, _cmd, suiteName, container);
    if (![suiteName hasPrefix:@"group"]) return ((id (*)(id, SEL, id, id))h_SuiteInitImp)(self, _cmd, suiteName, container);
    NSURL *custom = [base URLByAppendingPathComponent:suiteName];
    return ((id (*)(id, SEL, id, NSURL *))h_SuiteInitImp)(self, _cmd, suiteName, custom);
}

static void SGHookMethod(Class cls, SEL sel, IMP newImp, IMP *oldOut) {
    if (!cls) return;
    Class c = cls;
    while (c) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(methods[i]) == sel) {
                if (c == cls) {
                    if (oldOut) *oldOut = method_setImplementation(methods[i], newImp);
                } else {
                    if (oldOut) *oldOut = method_getImplementation(methods[i]);
                    class_addMethod(cls, sel, newImp, method_getTypeEncoding(methods[i]));
                }
                free(methods);
                return;
            }
        }
        free(methods);
        c = class_getSuperclass(c);
    }
}

static id h_TVSyncerNilFn(id self, SEL _cmd) { return nil; }

static void SGInstallSwizzles(void) {
    Class ckC = objc_getClass("CKContainer");
    SGHookMethod(ckC, NSSelectorFromString(@"_setupWithContainerID:options:"), (IMP)h_CKSetupNil, &o_CKSetup);
    SGHookMethod(ckC, NSSelectorFromString(@"_initWithContainerIdentifier:"), (IMP)h_CKInitNil, &o_CKInit);

    Class ckE = objc_getClass("CKEntitlements");
    SGHookMethod(ckE, NSSelectorFromString(@"initWithEntitlementsDict:"), (IMP)h_CKEntitlementsInit, &h_CKEntImp);

    Class fm = objc_getClass("NSFileManager");
    SGHookMethod(fm, NSSelectorFromString(@"containerURLForSecurityApplicationGroupIdentifier:"), (IMP)h_ContainerURLFn, &h_ContainerURLImp);

    Class ud = objc_getClass("NSUserDefaults");
    SGHookMethod(ud, NSSelectorFromString(@"_initWithSuiteName:container:"), (IMP)h_SuiteInitFn, &h_SuiteInitImp);

    // TVProfileSyncer 禁用(防 CloudKit 异常崩溃)
    Class tvSync = objc_getClass("SGUTVProfileSyncer");
    if (tvSync) {
        SGHookMethod(tvSync, NSSelectorFromString(@"init"), (IMP)h_TVSyncerNilFn, NULL);
    }
}

__attribute__((constructor)) static void SGCloudKitInit(void) {
    SGBootstrapKeychain();
    SGInstallSwizzles();
}