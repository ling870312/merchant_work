// ATT 屏蔽（仅编译进 App，不修改 SDK 二进制）。
//
// 背景：HBuilder/DCloud SDK 启动时会调用 ATTrackingManager 请求跟踪授权。
// 本 App 不做跨 App 追踪，因此从 Info.plist 移除 NSUserTrackingUsageDescription，
// 否则 App Store Connect 会要求声明「数据用于追踪」而无法提交审核。
//
// 但直接删键会让 SDK 的请求被系统以隐私违规终止（SIGABRT），
// 所以在 App 启动前把该请求的返回值固定为「拒绝」：既不弹窗，也不崩溃。
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

__attribute__((constructor))
static void DMAttGuardInstall(void)
{
    Class cls = NSClassFromString(@"ATTrackingManager");
    if (cls == Nil) {
        // 兜底：SDK 未静态链接该框架时手动加载，确保类已注册
        void *handle = dlopen("/System/Library/Frameworks/AppTrackingTransparency.framework/AppTrackingTransparency", RTLD_LAZY);
        if (handle != NULL) {
            cls = NSClassFromString(@"ATTrackingManager");
        }
    }
    if (cls == Nil) {
        return;
    }
    SEL sel = NSSelectorFromString(@"requestTrackingAuthorizationWithCompletionHandler:");
    Method method = class_getClassMethod(cls, sel);
    if (method == NULL) {
        return;
    }
    IMP replacement = imp_implementationWithBlock(^(__unsafe_unretained id _self, void (^handler)(NSInteger)) {
        if (handler == nil) {
            return;
        }
        // 2 = ATTrackingManagerAuthorizationStatusDenied
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(2);
        });
    });
    method_setImplementation(method, replacement);
}
