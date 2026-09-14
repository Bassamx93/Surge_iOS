// 模块链:
//   读: -[SGModuleManager _officialModuleSectionsWithSystemEnvironment:moduleMap:] @0x100199BEC
//       → [SGCoreDefaults sharedDefaults] officialModulesData
//       → storageProvider objectForKey: → base64 解码 → KD_JSONObject
//       → sections[].items[].s → [SGModule initWithString:systemEnvironment:error:]
//       → setPath:"%%INTERNAL%%/<p>.sgmodule", setIsOfficial:1   (全程无签名校验)
//   写: 持久化块 sub_10028F13C @0x10028F13C → setOfficialModulesData: 原样存储
//   拉取: POST https://www.surge-activation.com/ios/v3/resource/module?v=<版本>
//       (备用 https://13.248.139.174/);响应包 {"code":0,"data":"<base64>","message":...}
//       实测服务器对未授权设备返回 403 → 拉取链不可用,所以我是数据必须本地注入。
//
// 注入面(三层互为兜底):
//   1) NSUserDefaults objectForKey: 读拦截
//   2) SGRequestHelper 模块端点拦截 —— 合成 {"code":0,"data":<注入>},
//      surge iOS App 官方原生链(setOfficialModulesData: → _enableNewOfficialModules)完成持久化与自动启用,顺带消灭 403 弹窗
//   3) 文件补齐(plist + SGJSVMInject) —— 重点，NE 进程不加载 dylib,靠 CloudKit.dylib 的 suite 重定向读文件
//

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>




// MSHookMessageEx 不依赖 CydiaSubstrate;
void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old) {
    if (!_class || !message || !hook) return;
    Method method = class_getInstanceMethod(_class, message);
    if (!method) return;
    IMP orig = method_getImplementation(method);
    if (old) *old = orig;
    if (!class_addMethod(_class, message, hook, method_getTypeEncoding(method))) {
        method_setImplementation(method, hook);
    }
}

static NSString *const PLIST_CONTENT = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                      "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                                      "<plist version=\"1.0\">\n"
                                      "<dict>\n"
                                      "    <key>CoreRunning</key><false/>\n"
                                      "    <key>CoreStartTime</key><real>1739854465</real>\n"
                                      "    <key>CurrentSessionID</key><string>1739854465551</string>\n"
                                      "    <key>IcloudBackgroundSync</key><integer>0</integer>\n"
                                      "    <key>InternalControllerKey</key><string>D59AA798-FD8E-4EBC-9C50-C3B74E1C141B-74926-00000A9768D0C81E</string>\n"
                                      "    <key>InternalControllerPort</key><integer>60821</integer>\n"
                                      "    <key>JsvmInjectVersion</key><string>2024091201292561</string>\n"
                                      "    <key>LockedFeatures</key><array/>\n"
                                      "    <key>MemoryUsageAfterLaunching</key><integer>12518080</integer>\n"
                                      "    <key>MemoryWarningReceived</key><false/>\n"
                                      "    <key>Modules</key><array/>\n"
                                      "    <key>OfficialModulesData</key><string>eyJ2IjoiMjAyNDEwMjEyMjAxMjI4NzM5MDMiLCJzZWN0aW9ucyI6W3sidGl0bGUiOiJFbmhhbmNlbWVudHMiLCJpdGVtcyI6W3sicyI6IkNpTWhibUZ0WlQxeWIzVjBaWEl1WTI5dENpTWhaR1Z6WXoxQlpuUmxjaUJsYm1GaWJHbHVaeUIwYUdVZ2JXOWtkV3hsTENCNWIzVWdiV0Y1SUdGalkyVnpjeUIwYUdVZ2NtOTFkR1Z5SUdOdmJtWnBaM1YwWVhScGIyNGdkMlZpY0dGblpTQmllU0JoWTJObGMzTnBibWNnYUhSMGNEb3ZMM0p2ZFhSbGNpNWpiMjBnYVc0Z2VXOTFjaUJpY205M2MyVnlMaUJVYUdVZ1ZWSk1JSGRwYkd3Z1lXeDNZWGx6SUhKbFpHbHlaV04wSUhSdklIUm9aU0JuWVhSbGQyRjVJR0ZrWkhKbGMzTWdhVzRnZEdobElHTjFjbkpsYm5RZ2JtVjBkMjl5YXk0S0NsdEhaVzVsY21Gc1hRcG1iM0pqWlMxb2RIUndMV1Z1WjJsdVpTMW9iM04wY3owbFFWQlFSVTVFSlNCeWIzVjBaWEl1WTI5dExDQjNkM2N1Y205MWRHVnlMbU52YlFvS1cwMUpWRTFkQ21odmMzUnVZVzFsSUQwZ0pVbE9VMFZTVkNVZ2NtOTFkR1Z5TG1OdmJTd2dkM2QzTG5KdmRYUmxjaTVqYjIwS0NsdFZVa3dnVW1WM2NtbDBaVjBLWG1oMGRIQnpQem92THloOGQzZDNYQzRwY205MWRHVnlYQzVqYjIwZ2FIUjBjRG92TDN0N2UwZEJWRVZYUVZsZlFVUkVVa1ZUVTMxOWZTQXpNRElKIiwicCI6InJvdXRlci1jb20ifV19LHsidGl0bGUiOiJRdWlya3MiLCJpdGVtcyI6W3sicyI6Ikl5RnVZVzFsUFcxaFkwOVRJRlJ5WVc1emJHRjBaU0JDZFdjZ1JtbDRDaU1oWkdWell6MXRZV05QVXlCV1pXNTBkWEpoTDFOdmJtOXRZU0JvWVhNZ1lTQmlkV2NnZEdoaGRDQjNhR1Z1SUhSb1pTQndjbTk0ZVNCcGN5QmpiMjVtYVdkMWNtVmtMQ0IwYUdVZ2RISmhibk5zWVhSbElHWmxZWFIxY21VZ2JXbG5hSFFnWW1VZ2RXNWhkbUZwYkdGaWJHVXVJRlJvYVhNZ2JXOWtkV3hsSUdGd2NHeHBaWE1nWVNCMFpXMXdiM0poY25rZ2QyOXlhMkZ5YjNWdVpDQmllU0IwZDJWaGEybHVaeUIwYUdVZ2MydHBjQzF3Y205NGVTQndZWEpoYldWMFpYSWdkRzhnYzJ0cGNDQnpiMjFsSUhKbGJHRjBaV1FnY21WeGRXVnpkSE1nWm5KdmJTQlRkWEpuWlNCd2NtOTRlUzRLSXlGemVYTjBaVzA5YldGaklERXpMakF1TUMweE5TNHdMakFLSXlGa1pXWmhkV3gwUFdWdVlXSnNaV1FLQ2x0SFpXNWxjbUZzWFFwemEybHdMWEJ5YjNoNUlEMGdKVUZRVUVWT1JDVWdjMlZsWkMxelpYRjFiMmxoTG5OcGNta3VZWEJ3YkdVdVkyOXRMQ0J6WlhGMWIybGhMbk5wY21rdVlYQndiR1V1WTI5dExDQnpaWEYxYjJsaExtRndjR3hsTG1OdmJRbz0iLCJwIjoibWFjb3MtdHJhbnNsYXRlIn0seyJzIjoiSXlGdVlXMWxQVWR2YjJkc1pTQkliMjFsSUVSbGRtbGpaWE1LSXlGa1pYTmpQVXhsZENCVGRYSm5aU0JvWVc1a2JHVWdjbVZ4ZFdWemRITWdjMlZ1ZENCaWVTQkhiMjluYkdVZ1NHOXRaU0JrWlhacFkyVnpJR0o1SUdocGFtRmphMmx1WnlCMGFHVWdSRTVUSUhCaFkydGxkSE1nZEc4Z09DNDRMamd1T0M4NExqZ3VOQzQwTGlCUGJteDVJSFZ6WldaMWJDQjNhR1Z1SUZOMWNtZGxJRTFoWXlCaFkzUnpJSFJvWlNCeWIzVjBaWElnWm05eUlIUm9aWE5sSUdSbGRtbGpaWE11Q2lNaGMzbHpkR1Z0UFcxaFl3b0tXMGRsYm1WeVlXeGRDbWhwYW1GamF5MWtibk1nUFNBbFFWQlFSVTVFSlNBNExqZ3VPQzQ0T2pVekxDQTRMamd1TkM0ME9qVXpDZz09IiwicCI6Imdvb2dsZS1ob21lLWRldmljZSJ9LHsicyI6Ikl5RnVZVzFsUFVkaGJXVWdRMjl1YzI5c1pTQlRWRlZPQ2lNaFpHVnpZejFNWlhRZ1UzVnlaMlVnYUdGdVpHeGxJRk5VVlU0Z1kyOXVkbVZ5YzJGMGFXOXVJSEJ5YjNCbGNteDVJR1p2Y2lCUWJHRjVVM1JoZEdsdmJpd2dXR0p2ZUN3Z1lXNWtJRTVwYm5SbGJtUnZJRk4zYVhSamFDNGdUMjVzZVNCMWMyVm1kV3dnZDJobGJpQlRkWEpuWlNCTllXTWdZV04wY3lCMGFHVWdjbTkxZEdWeUlHWnZjaUIwYUdWelpTQmtaWFpwWTJWekxnb2pJWE41YzNSbGJUMXRZV01LSXlGa1pXWmhkV3gwUFdWdVlXSnNaV1FLQ2x0SFpXNWxjbUZzWFFwaGJIZGhlWE10Y21WaGJDMXBjQ0E5SUNWQlVGQkZUa1FsSUNvdWMzSjJMbTVwYm5SbGJtUnZMbTVsZEN3Z0tpNXpkSFZ1TG5Cc1lYbHpkR0YwYVc5dUxtNWxkQ3dnZUdKdmVDNHFMbTFwWTNKdmMyOW1kQzVqYjIwc0lDb3VlR0p2ZUd4cGRtVXVZMjl0Q2c9PSIsInAiOiJnYW1lLWNvbnNvbGUtbmF0In0seyJzIjoiSXlGdVlXMWxQVWh2YldWTGFYUWdRV05qWlhOemIzSnBaWE1nVVhWcGNtc0tJeUZrWlhOalBWTnZiV1VnU0c5dFpVdHBkQ0JrWlhacFkyVnpJR2hoZG1VZ2FYTnpkV1Z6SUhkcGRHZ2dkR2hsYVhJZ2NISnZkRzlqYjJ3Z2FXMXdiR1Z0Wlc1MFlYUnBiMjRzSUhObGJtUnBibWNnYm05dUxVaFVWRkFnYzNSaGJtUmhjbVFnWkdGMFlTQmhablJsY2lCMGFHVWdjM1JoYm1SaGNtUWdTRlJVVUNCeVpYRjFaWE4wY3l3Z2QyaHBZMmdnWTJGMWMyVnpJRk4xY21kbEozTWdTRlJVVUNCbGJtZHBibVVnZEc4Z1ltVWdkVzVoWW14bElIUnZJR1p2Y25kaGNtUWdZMjl5Y21WamRHeDVMaUJGYm1GaWJHbHVaeUIwYUdseklIZHBiR3dnWTJGMWMyVWdjbVZzWVhSbFpDQnlaWEYxWlhOMGN5QjBieUJpWlNCb1lXNWtiR1ZrSUhWemFXNW5JSEpoZHlCVVExQWdjSEp2WTJWemMybHVaeTRLSXlGa1pXWmhkV3gwUFdWdVlXSnNaV1FLQ2x0SFpXNWxjbUZzWFFwaGJIZGhlWE10Y21GM0xYUmpjQzFyWlhsM2IzSmtjeUE5SUNWSlRsTkZVbFFsSUNKRGIyNTBaVzUwTFZSNWNHVTZJR0Z3Y0d4cFkyRjBhVzl1TDNCaGFYSnBibWNyZEd4Mk9DST0iLCJwIjoiaG9tZS1raXQtcGFpcmluZyJ9LHsicyI6Ikl5RnVZVzFsUFVacGVDQlhhVzVrYjNkeklFNXZJRTVsZEhkdmNtc2dRV3hsY25RS0l5RmtaWE5qUFZkcGJtUnZkM01nYzNsemRHVnRJR1JsY0dWdVpITWdiMjRnZEdobElFUk9VeUJ5WlhOdmJIVjBhVzl1SUhKbGMzVnNkQ0J2WmlCa2JuTXViWE5tZEc1amMya3VZMjl0SUhSdklHUmxkR1Z5YldsdVpTQjBhR1VnYm1WMGQyOXlheUJoZG1GcGJHRmlhV3hwZEhrdUlGVnpaU0JUZFhKblpTQmhjeUIwYUdVZ1oyRjBaWGRoZVNCM2FXeHNJR0p5WldGcklIUm9aU0JpWldoaGRtbHZjaTRnVkhWeWJpQnZiaUIwYUdseklHMXZaSFZzWlNCMGJ5Qm1hWGdnYVhRdUNpTWhjM2x6ZEdWdFBXMWhZd29qSVdSbFptRjFiSFE5Wlc1aFlteGxaQW9LVzBkbGJtVnlZV3hkQ21Gc2QyRjVjeTF5WldGc0xXbHdJRDBnSlVGUVVFVk9SQ1VnWkc1ekxtMXpablJ1WTNOcExtTnZiUW89IiwicCI6IndpbmRvd3MtbmV0d29yay1jaGVjayJ9XX0seyJ0aXRsZSI6Ik9wdGltaXphdGlvbnMiLCJpdGVtcyI6W3sicyI6Ikl5RnVZVzFsUFVScGMyRmliR1VnU0ZSVVVDQkZibWRwYm1VS0l5RmtaWE5qUFVsbUlIbHZkU0JrYnlCdWIzUWdibVZsWkNCMGJ5QjFjMlVnWVdSMllXNWpaV1FnU0ZSVVVDMXlaV3hoZEdWa0lHWmxZWFIxY21WekxDQjViM1VnWTJGdUlHUnpjMkZpYkdVZ2RHaGxJRWhVVkZBZ2NISnZZMlZ6YzJsdVp5QmxibWRwYm1VZ2RHOGdhVzF3Y205MlpTQndaWEptYjNKdFlXNWpaUzRnVkdocGN5QnZjSFJwYjI0Z1pHOWxjeUJ1YjNRZ1lXWm1aV04wSUhKbGNYVmxjM1J6SUdoaGJtUnNaV1FnWW5rZ2RHaGxJRWhVVkZBZ2NISnZlSGtnYzJWeWRtbGpaU0J2Y2lCMGFHOXpaU0J3Y205alpYTnpaV1FnWW5rZ1RVbFVUUzRLSXlGemVYTjBaVzA5YldGakNncGJSMlZ1WlhKaGJGMEtZV3gzWVhsekxYSmhkeTEwWTNBdGEyVjVkMjl5WkhNZ1BTQXYiLCJwIjoibm8taHR0cC1wcm9jZXNzIn0seyJzIjoiSXlGdVlXMWxQVWhVVkZBZ1JHOTNibXh2WVdRZ1QzQjBhVzFwZW1GMGFXOXVDaU1oWkdWell6MVRiMjFsSUhOdlpuUjNZWEpsSUhWd1pHRjBaU0J6ZVhOMFpXMXpJR2hoZG1VZ1lXUnZjSFJsWkNCMGFHVWdiV1YwYUc5a0lHOW1JR1J2ZDI1c2IyRmthVzVuSUhacFlTQklWRlJRSUhOc2FXTnBibWN1SUZOcGJtTmxJRk4xY21kbElHNWxaV1J6SUhSdklIQmxjbVp2Y20wZ2NuVnNaU0JrWlhSbGNtMXBibUYwYVc5dUlHRnVaQ0J2ZEdobGNpQndjbTlqWlhOelpYTWdabTl5SUdWaFkyZ2dTRlJVVUNCeVpYRjFaWE4wTENCMGFHbHpJR05oYmlCc1pXRmtJSFJ2SUhOcFoyNXBabWxqWVc1MElIQmxjbVp2Y20xaGJtTmxJR2x0Y0dGamRDQjNhR1Z1SUhSb1pTQnVkVzFpWlhJZ2IyWWdTRlJVVUNCeVpYRjFaWE4wY3lCcGN5QjJaWEo1SUd4aGNtZGxMaUJDZVNCbGJtRmliR2x1WnlCMGFHbHpJRzl3ZEdsdmJpd2djbVZzWVhSbFpDQnlaWEYxWlhOMGN5QjNhV3hzSUdKbElIUnlaV0YwWldRZ1lYTWdjbUYzSUZSRFVDQjBieUJoZG05cFpDQjBhR1VnYjNabGNtaGxZV1FnYjJZZ2RHaGxJRWhVVkZBZ1pXNW5hVzVsTGx4dVJXWm1aV04wYVhabElHWnZjaUJUZEdWaGJTd2dWMmx1Wkc5M2N5QlZjR1JoZEdVc0lFMXBZM0p2YzI5bWRDQlRkRzl5WlN3Z1dHSnZlQ3dnVUd4aGVWTjBZWFJwYjI0Z05Rb2pJWE41YzNSbGJUMXRZV01LSXlGa1pXWmhkV3gwUFdWdVlXSnNaV1FLQ2x0SFpXNWxjbUZzWFFwaGJIZGhlWE10Y21GM0xYUmpjQzFvYjNOMGN5QTlJQ1ZKVGxORlVsUWxJQ291ZDJsdVpHOTNjM1Z3WkdGMFpTNWpiMjBLWVd4M1lYbHpMWEpoZHkxMFkzQXRhMlY1ZDI5eVpITWdQU0FsU1U1VFJWSlVKU0FpVm1Gc2RtVXZVM1JsWVcwZ1NGUlVVQ0JEYkdsbGJuUWlMQ0FpVlhObGNpMUJaMlZ1ZERvZ1RXbGpjbTl6YjJaMExVUmxiR2wyWlhKNUxVOXdkR2x0YVhwaGRHbHZiaUlzSUNKVmMyVnlMVUZuWlc1ME9pQnNhV0pvZEhSd0x6Z3VOREFnS0ZCc1lYbFRkR0YwYVc5dUlEVXBJZz09IiwicCI6Imh0dHAtZG93bmxvYWQtc2tpcCJ9XX1dLCJ1IjoiNDEwMDRkOTAtZTgzZS0xMWVmLWIxYzAtNmI3N2QwMTU4MjRkIn0=</string>\n"
                                      "    <key>ShouldReloadProfilesMainApp</key><false/>\n"
                                      "    <key>ShouldReloadProfilesNE</key><false/>\n"
                                      "    <key>Suspended</key><false/>\n"
                                      "    <key>WidgetUnlock</key><true/>\n"
                                      "    <key>iCloudDriveEnabled</key><false/>\n"
                                      "</dict>\n</plist>";




static NSString *const SGJSVM_INJECT_BASE64 = @"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";


// 模块注入数据:从 PLIST_CONTENT 提取 OfficialModulesData
// (base64(JSON{"v":...,"sections":[{"title":...,"items":[{"s":...,"p":...}]}],"u":...}))
static NSString *SGInjectedOfficialModulesData(void) {
    static NSString *data;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        id plist = [PLIST_CONTENT propertyList];
        if ([plist isKindOfClass:[NSDictionary class]]) {
            id v = plist[@"OfficialModulesData"];
            if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length > 0) data = v;
        }
    });
    return data;
}

// 共享容器文件补齐:只创建不覆盖(目录/文件缺失才写,永不抹掉已有数据)。
// containerURLForSecurityApplicationGroupIdentifier: 在 CloudKit.dylib
static void SGSeedSharedContainerFiles(void) {
    NSString *appGroupIdentifier = @"group.com.nssurge.inc.surge-ios";
    NSURL *containerURL = [[NSFileManager defaultManager]
        containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier];
    if (!containerURL) return;

    NSString *targetFolderPath = [containerURL.path stringByAppendingPathComponent:@"Library/Preferences"];
    NSString *plistFilePath = [targetFolderPath stringByAppendingPathComponent:@"group.com.nssurge.inc.surge-ios.plist"];
    NSString *sgjsvmInjectPath = [containerURL.path stringByAppendingPathComponent:@"SGJSVMInject"];

    // 只做缺失补齐:目录仅创建不删除,文件仅缺失时写入,不覆盖。
    [[NSFileManager defaultManager] createDirectoryAtPath:targetFolderPath
                              withIntermediateDirectories:YES attributes:nil error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:plistFilePath]) {
        NSData *xmlData = [PLIST_CONTENT dataUsingEncoding:NSUTF8StringEncoding];
        [[NSFileManager defaultManager] createFileAtPath:plistFilePath contents:xmlData attributes:nil];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:sgjsvmInjectPath]) {
        NSData *fileData = [[NSData alloc] initWithBase64EncodedString:SGJSVM_INJECT_BASE64 options:0];
        [[NSFileManager defaultManager] createFileAtPath:sgjsvmInjectPath contents:fileData attributes:nil];
    }
}

// 模块端点成功响应:{"code":0,"data":<注入base64>}
static void SGCompleteWithModuleResponse(NSString *urlString,
                                         void (^completionHandler)(NSData *data, NSURLResponse *response, NSError *error)) {
    NSString *injected = SGInjectedOfficialModulesData();
    NSDictionary *fakeResponseDict;
    if (injected.length > 0) {
        fakeResponseDict = @{
            @"code": @0,
            @"data": injected,
            @"status": @"success",
            @"serverTime": @((long)[[NSDate date] timeIntervalSince1970])
        };
    } else {
        fakeResponseDict = @{
            @"code": @0,
            @"status": @"success",
            @"serverTime": @((long)[[NSDate date] timeIntervalSince1970])
        };
    }
    NSError *err = nil;
    NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakeResponseDict options:0 error:&err];
    if (!fakeData) { return; }
    NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:urlString]
                                                                  statusCode:200
                                                                 HTTPVersion:@"1.1"
                                                                headerFields:@{@"Content-Type": @"application/json; charset=utf-8"}];
    completionHandler(fakeData, fakeResponse, nil);
}


// 授权页显示字段(orderID/email 等)由 UI.x 自定义覆盖, 不依赖此响应。
static NSDictionary *SGMiniActivationResponse(NSURLRequest *request, NSString *urlString) {
    NSDictionary *base = @{@"code": @0, @"status": @"success"};
    BOOL licEndpoint = [urlString containsString:@"/ios/v3/refresh"]
                    || [urlString containsString:@"/ios/v3/activate"];
    if (!licEndpoint) return base;

    // deviceID 优先取请求体, 兜底使用钥匙串
    NSString *deviceID = nil;
    NSDictionary *body = nil;
    if ([request isKindOfClass:[NSURLRequest class]] && request.HTTPBody) {
        body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:kNilOptions error:nil];
    }
    if ([body[@"deviceID"] isKindOfClass:[NSString class]]) deviceID = body[@"deviceID"];
    if (!deviceID.length) {
        Class kc = objc_getClass("KDKeychain");
        if (kc) {
            NSData *d = ((NSData *(*)(id, SEL, id))objc_msgSend)
                (kc, NSSelectorFromString(@"keychainItemDataWithIdentifier:"), @"DeviceID");
            deviceID = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
        }
    }
    if (!deviceID.length) deviceID = @"SURGELOCALDEVICE";

    double expiry = [[NSDate date] timeIntervalSince1970] + 366.0 * 86400.0;
    NSDictionary *policy = @{
        @"deviceID":       deviceID,
        @"expirationDate": @(expiry),
        @"expiresOnDate":  @((long long)expiry),
        @"type":           @"licensed",
        @"p":              @"surge",
    };
    NSData *pd = [NSJSONSerialization dataWithJSONObject:policy options:0 error:nil];
    if (!pd) return base;
    NSDictionary *license = @{
        @"policy": [pd base64EncodedStringWithOptions:0],
        @"sign":   @"cnQuc3VyZ2U=",   // 验签由 0x267a44 补丁
    };
    return @{@"code": @0, @"license": license, @"status": @"success"};
}


__attribute__((unused)) static BOOL SGIsSurgeActivationURL(NSString *urlString) {
    return [urlString containsString:@"surge-activation.com"]
        || [urlString containsString:@"13.248.139.174"];
}

%hook NSUserDefaults
// 官方surge读取路径:[SGCoreDefaults sharedDefaults] officialModulesData
// → KDDynamic forwardInvocation: → 底层 NSUserDefaults objectForKey:。
// 读:无有效数据时返回注入的 base64 JSON
- (id)objectForKey:(NSString *)key {
    if ([key isEqualToString:@"officialModulesData"]) {
        NSString *orig = %orig;
        if ([orig isKindOfClass:[NSString class]] && orig.length > 0) return orig;
        return SGInjectedOfficialModulesData();
    }
    // 无值时返回与注入数据一致的版本
    if ([key isEqualToString:@"officialModulesVersion"]) {
        NSString *v = %orig;
        if ([v isKindOfClass:[NSString class]] && v.length > 0) return v;
        return @"20241021220122873903";
    }
    return %orig;
}
// 写:拦截对 officialModulesData 的清空/无效覆盖,防止注入数据被抹掉
- (void)setObject:(id)value forKey:(NSString *)key {
    if ([key isEqualToString:@"officialModulesData"]) {
        if (![value isKindOfClass:[NSString class]] || ((NSString *)value).length == 0) return;
    }
    %orig;
}
%end

// SGRequestHelper:只拦模块端点;其余激活端点放行(pro授权是用patch方法)。
%hook SGRequestHelper
- (id)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *urlString = request.URL.absoluteString;
    if ([urlString containsString:@"surge-activation.com"] || [urlString containsString:@"13.248.139.174"]) {
        if ([urlString containsString:@"/ios/v3/resource/module"]) {
            SGSeedSharedContainerFiles();
            SGCompleteWithModuleResponse(urlString, completionHandler);
            return nil;
        }
        NSDictionary *mini = SGMiniActivationResponse(request, urlString);
        NSData *miniBody = [NSJSONSerialization dataWithJSONObject:mini options:0 error:nil];
        NSHTTPURLResponse *miniResp = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        completionHandler(miniBody, miniResp, nil);
        return nil;
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *urlString = url.absoluteString;
    if ([urlString containsString:@"surge-activation.com"] || [urlString containsString:@"13.248.139.174"]) {
        if ([urlString containsString:@"/ios/v3/resource/module"]) {
            SGSeedSharedContainerFiles();
            SGCompleteWithModuleResponse(urlString, completionHandler);
            return nil;
        }
        NSDictionary *mini2 = SGMiniActivationResponse(nil, url.absoluteString);
        NSData *miniBody2 = [NSJSONSerialization dataWithJSONObject:mini2 options:0 error:nil];
        NSHTTPURLResponse *miniResp2 = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        completionHandler(miniBody2, miniResp2, nil);
        return nil;
    }
    return %orig;
}

%end