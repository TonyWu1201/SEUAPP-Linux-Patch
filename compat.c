/*
 * libwwlocal_compat.so
 *
 * 企业微信 (wwlocal) Linux 兼容性修复 preload 库。两部分:
 *
 * (1) 退出保护 (修 "关闭应用时崩溃" / "关闭应用时报错"):
 *     glibc 的 __libc_start_call_main 直接调用内部别名 __GI_exit, 无法用
 *     LD_PRELOAD 覆盖 exit()。这里拦截 __libc_start_main, 把 main 包一层,
 *     main 返回后 fflush + _Exit, 不再进入 glibc 退出处理链
 *     (该链里的第三方静态析构会把 wwlocal 自带老 tcmalloc 的 free list 搞崩)。
 *
 * (2) wtrdup / wtrndup (修 "输入组织机构域后闪退 / free(): invalid size"):
 *     libwework_sdk / libcurl 等以 RTLD_DEEPBIND 方式加载, 其 malloc/free
 *     在自身作用域内解析到 glibc; 但 libc 内部函数 (如 strdup) 的 malloc
 *     经全局作用域落到 wwlocal 自带的 tcmalloc。libcurl 用 strdup 生成的
 *     字符串后来用 glibc free 释放 -> 同一指针跨分配器 -> 新版 glibc 直接
 *     abort ("free(): invalid size")。
 *
 *     打包时把 libcurl 的 strdup/strndup 导入符号改名为 wtrdup/wtrndup,
 *     由本库用 glibc 的 malloc 实现 (解析到的 free 也是 glibc), 两边一致。
 *
 * 环境变量: WWLOCAL_NO_EXIT_FIX=1 跳过 (1); WWLOCAL_DEBUG=1 打印调试信息。
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ---------- (2) wtrdup / wtrndup: 用 glibc 的 malloc 分配 ---------- */

static void *(*next_malloc_fn)(size_t);
static void *(*next_realloc_fn)(void *, size_t);

__attribute__((constructor(101)))
static void compat_ctor(void)
{
    /* 从本库出发的"下一个" malloc 即 glibc 的实现
       (可执行文件在作用域链中位于 preload 库之前, 会被 RTLD_NEXT 跳过) */
    if (!next_malloc_fn)
        next_malloc_fn = (void *(*)(size_t))dlsym(RTLD_NEXT, "malloc");
    if (!next_realloc_fn)
        next_realloc_fn = (void *(*)(void *, size_t))dlsym(RTLD_NEXT, "realloc");
}

static void *glibc_alloc(size_t n)
{
    if (!next_malloc_fn)
        next_malloc_fn = (void *(*)(size_t))dlsym(RTLD_NEXT, "malloc");
    return next_malloc_fn(n);
}

char *wtrdup(const char *s)
{
    size_t n;
    char *p;

    if (!s)
        return NULL;
    n = strlen(s) + 1;
    p = glibc_alloc(n);
    if (p)
        memcpy(p, s, n);
    return p;
}

char *wtrndup(const char *s, size_t n)
{
    size_t len;
    char *p;

    if (!s)
        return NULL;
    len = strnlen(s, n);
    p = glibc_alloc(len + 1);
    if (p) {
        memcpy(p, s, len);
        p[len] = '\0';
    }
    return p;
}

/* ---------- (1) 退出保护 ---------- */

static int (*app_main)(int, char **, char **);

static int guard_main(int argc, char **argv, char **envp)
{
    int rc = app_main(argc, argv, envp);
    fflush(NULL);
    _Exit(rc);
}

typedef int (*start_fn)(int (*)(int, char **, char **), int, char **,
                        void (*)(void), void (*)(void), void (*)(void), void *);

int __libc_start_main(int (*main)(int, char **, char **), int argc,
                      char **ubp_av, void (*init)(void), void (*fini)(void),
                      void (*rtld_fini)(void), void *stack_end)
{
    static start_fn real;
    const char *no_exit_fix = getenv("WWLOCAL_NO_EXIT_FIX");

    if (!real)
        real = (start_fn)dlsym(RTLD_NEXT, "__libc_start_main");
    app_main = main;
    if (no_exit_fix)
        return real(main, argc, ubp_av, init, fini, rtld_fini, stack_end);
    return real(guard_main, argc, ubp_av, init, fini, rtld_fini, stack_end);
}
