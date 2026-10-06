/*
 * glespass: a libGL.so.1 for Westonpack's crusty_glx without gl4es.
 *
 * The GLES-patched Night in the Woods only issues OpenGL ES calls, so nothing is translated.
 * This library provides what gl4es's libGL would, as pass-throughs:
 *   - initialize_gl4es() / gl4es_GetProcAddress(), which crusty's GLX layer calls;
 *   - every gl* entry point gl4es exports (trampolines.S), bound to the system GLES/EGL
 *     driver, or to a no-op returning 0 for desktop-only functions GLES lacks;
 *   - every glX* entry point, bound to crusty's implementation, so box64's libGL wrapper
 *     finds them all (crusty has no plain glXGetProcAddress; it maps to ...ARB).
 * Set GLESPASS_DEBUG=1 to log resolution, GLESPASS_NOOPLOG=1 to log calls to unimplemented functions,
 * GLESPASS_PROBE=N to log how frame N is drawn (see the frame probe), GLESPASS_VENDOR and
 * GLESPASS_RENDERER to replace the GL_VENDOR / GL_RENDERER strings the game sees, GLESPASS_FOCUS=1
 * to give the game window X input focus.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include "build/symbols.h"

typedef void *(*getproc_fn)(const char *);

__attribute__((visibility("hidden"))) void *glespass_ptrs[GLESPASS_NUM_ALL];

static void *gles_lib, *crusty_lib;
static getproc_fn egl_getproc;
static int verbose;

static long glespass_noop(void) { return 0; }

/* GLESPASS_NOOPLOG=1: functions without an implementation get a stub each, which reports the
   first call to that function by name (the shared no-op cannot tell them apart). */
extern void *const glespass_noop_stubs[];
static int nooplog;
__attribute__((visibility("hidden"))) long glespass_noop_log(long i)
{
    static unsigned char seen[4096];
    if (i >= 0 && i < (long)sizeof seen && !seen[i]) {
        seen[i] = 1;
        fprintf(stderr, "[glespass] called unimplemented %s (no-op)\n", glespass_names[i]);
    }
    return 0;
}

static void *lookup(const char *name)
{
    void *p = gles_lib ? dlsym(gles_lib, name) : NULL;
    if (!p && egl_getproc)
        p = egl_getproc(name);
    return p;
}

static void *lookup_gl(const char *name)
{
    void *p = lookup(name);
    if (!p) {
        /* desktop-style suffixed names (glFooARB/EXT/OES) -> core ES name */
        size_t n = strlen(name);
        if (n > 3 && n - 3 < 256 && (!strcmp(name + n - 3, "ARB") || !strcmp(name + n - 3, "EXT") ||
                                     !strcmp(name + n - 3, "OES"))) {
            char base[256];
            memcpy(base, name, n - 3);
            base[n - 3] = 0;
            p = lookup(base);
        }
    }
    return p;
}

__attribute__((constructor(101))) static void glespass_init(void)
{
    const char *e = getenv("GLESPASS_DEBUG");
    verbose = e && *e && strcmp(e, "0") != 0;
    e = getenv("GLESPASS_NOOPLOG");
    nooplog = e && *e && strcmp(e, "0") != 0;
    gles_lib = dlopen("libGLESv2.so.2", RTLD_NOW | RTLD_GLOBAL);
    void *egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (egl)
        egl_getproc = (getproc_fn)dlsym(egl, "eglGetProcAddress");
    crusty_lib = dlopen("libcrusty.so", RTLD_NOW | RTLD_NOLOAD);
    int gl_ok = 0, glx_ok = 0, missing = 0, crusty_gl = 0;
    for (int i = 0; i < GLESPASS_NUM_ALL; i++) {
        const char *name = glespass_names[i];
        void *p;
        if (i < GLESPASS_NUM_GL) {
            /* When this library is preloaded ahead of crusty, our symbols shadow crusty's in the
               global scope, so honour crusty's own GL hooks (framebuffer redirection etc.). */
            /* dlsym on crusty also searches its dependencies (this library, the GLES driver),
               so only take the result if it really is defined inside libcrusty itself */
            p = crusty_lib ? dlsym(crusty_lib, name) : NULL;
            Dl_info found;
            if (p && dladdr(p, &found) && found.dli_fname && strstr(found.dli_fname, "crusty"))
                crusty_gl++;
            else
                p = lookup_gl(name);
            gl_ok += p != NULL;
        } else {
            const char *real = strcmp(name, "glXGetProcAddress") ? name : "glXGetProcAddressARB";
            p = crusty_lib ? dlsym(crusty_lib, real) : NULL;
            /* dlsym on crusty also searches its dependencies, which include this library;
               never bind a trampoline to itself */
            Dl_info self, found;
            if (p && dladdr((void *)glespass_init, &self) && dladdr(p, &found) &&
                self.dli_fbase == found.dli_fbase)
                p = NULL;
            glx_ok += p != NULL;
        }
        if (!p) {
            missing++;
            if (verbose)
                fprintf(stderr, "[glespass] no implementation for %s (no-op)\n", name);
            p = nooplog ? glespass_noop_stubs[i] : (void *)glespass_noop;
        }
        glespass_ptrs[i] = p;
    }
    fprintf(stderr, "[glespass] GLESv2=%p crusty=%p: %d/%d gl (%d via crusty hooks), %d/%d glX bound, %d no-op\n",
            gles_lib, crusty_lib, gl_ok, GLESPASS_NUM_GL, crusty_gl, glx_ok, GLESPASS_NUM_ALL - GLESPASS_NUM_GL,
            missing);
}

/* ---- shader diagnostics (GLESPASS_SHADERLOG=N logs the first N failures, default 12) ---- */

typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef char GLchar;
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_SHADER_TYPE 0x8B4F
#define GL_SHADER_SOURCE_LENGTH 0x8B88

static void (*real_compile)(GLuint);
static void (*real_link)(GLuint);
static void (*p_getShaderiv)(GLuint, unsigned, GLint *);
static void (*p_getShaderInfoLog)(GLuint, GLsizei, GLsizei *, GLchar *);
static void (*p_getShaderSource)(GLuint, GLsizei, GLsizei *, GLchar *);
static void (*p_getProgramiv)(GLuint, unsigned, GLint *);
static void (*p_getProgramInfoLog)(GLuint, GLsizei, GLsizei *, GLchar *);
static int shaderlog_left = -1, compile_fail_total, link_fail_total;

static void shaderlog_init(void)
{
    if (shaderlog_left >= 0)
        return;
    const char *e = getenv("GLESPASS_SHADERLOG");
    shaderlog_left = e ? atoi(e) : 12;
    p_getShaderiv = lookup("glGetShaderiv");
    p_getShaderInfoLog = lookup("glGetShaderInfoLog");
    p_getShaderSource = lookup("glGetShaderSource");
    p_getProgramiv = lookup("glGetProgramiv");
    p_getProgramInfoLog = lookup("glGetProgramInfoLog");
}

/* GLESPASS_KHRDEBUG=N: log up to N messages (each distinct one at most 3 times) the GLES driver reports through KHR_debug (errors,
   performance and portability warnings), installed on the render thread at the first shader
   compile, where the context is current. */
static void khr_debug_cb(unsigned src, unsigned type, GLuint id, unsigned sev, GLsizei len, const char *msg,
                         const void *user)
{
    static int left = -1;
    (void)len; (void)user;
    if (left < 0) {
        const char *e = getenv("GLESPASS_KHRDEBUG");
        left = e ? atoi(e) : 0;
    }
    if (left <= 0) return;
    /* each distinct message (driver id plus the text's first 48 bytes) is logged 3 times at most */
    static struct { unsigned id; char head[48]; int n; } seen[128];
    static int nseen;
    int k;
    for (k = 0; k < nseen; k++)
        if (seen[k].id == id && !strncmp(seen[k].head, msg, sizeof seen[k].head - 1)) break;
    if (k == nseen) {
        if (nseen == 128) return;
        seen[k].id = id;
        strncpy(seen[k].head, msg, sizeof seen[k].head - 1);
        nseen++;
    }
    if (++seen[k].n > 3) return;
    left--;
    fprintf(stderr, "[glespass] KHR_debug src 0x%x type 0x%x id %u sev 0x%x: %s\n", src, type, id, sev, msg);
}

static void khr_debug_install(void)
{
    const char *e = getenv("GLESPASS_KHRDEBUG");
    if (!e || atoi(e) <= 0) return;
    void (*enable)(unsigned) = lookup("glEnable");
    void (*cb)(void *, const void *) = lookup("glDebugMessageCallback");
    if (!cb) cb = lookup("glDebugMessageCallbackKHR");
    if (!enable || !cb) {
        fprintf(stderr, "[glespass] KHR_debug unavailable\n");
        return;
    }
    enable(0x92E0 /* GL_DEBUG_OUTPUT */);
    enable(0x8242 /* GL_DEBUG_OUTPUT_SYNCHRONOUS */);
    cb((void *)khr_debug_cb, NULL);
    fprintf(stderr, "[glespass] KHR_debug callback installed\n");
}

static void glespass_CompileShader(GLuint s)
{
    static int first = 1;
    if (first) {
        first = 0;
        khr_debug_install();
        fprintf(stderr, "[glespass] first glCompileShader call reached the wrapper (shader %u)\n", s);
    }
    real_compile(s);
    shaderlog_init();
    GLint ok = 1;
    if (p_getShaderiv)
        p_getShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (ok)
        return;
    compile_fail_total++;
    if (shaderlog_left <= 0)
        return;
    shaderlog_left--;
    static char buf[8192];
    GLint type = 0;
    p_getShaderiv(s, GL_SHADER_TYPE, &type);
    buf[0] = 0;
    if (p_getShaderInfoLog)
        p_getShaderInfoLog(s, sizeof buf, NULL, buf);
    fprintf(stderr, "[glespass] COMPILE FAILED (#%d, %s shader %u):\n%s\n", compile_fail_total,
            type == 0x8B31 ? "vertex" : "fragment", s, buf);
    buf[0] = 0;
    if (p_getShaderSource)
        p_getShaderSource(s, sizeof buf, NULL, buf);
    fprintf(stderr, "[glespass] ---- source ----\n%s\n[glespass] ---- end source ----\n", buf);
}

static void glespass_LinkProgram(GLuint p)
{
    static int first = 1;
    if (first) {
        first = 0;
        fprintf(stderr, "[glespass] first glLinkProgram call reached the wrapper (program %u)\n", p);
    }
    real_link(p);
    shaderlog_init();
    GLint ok = 1;
    if (p_getProgramiv)
        p_getProgramiv(p, GL_LINK_STATUS, &ok);
    if (ok)
        return;
    link_fail_total++;
    if (shaderlog_left <= 0 && link_fail_total > 3)
        return;
    static char buf[4096];
    buf[0] = 0;
    if (p_getProgramInfoLog)
        p_getProgramInfoLog(p, sizeof buf, NULL, buf);
    fprintf(stderr, "[glespass] LINK FAILED (#%d, program %u, %d compile failures so far): %s\n", link_fail_total,
            p, compile_fail_total, buf[0] ? buf : "<empty log>");
}

/* ---- GLX / context tracing (GLESPASS_GLXTRACE=1) ----
   Logs which thread creates / binds / swaps GL contexts and what EGL reports as current on that
   thread afterwards, plus the first few GL calls per thread. Used to find out why Unity's render
   thread (threaded rendering) gets no working context through crusty's GLX layer. */
typedef unsigned long XID;
static int glxtrace = -1;
static void *(*p_eglGetCurrentContext)(void);
static void *(*p_eglGetCurrentSurface)(int);
static void *(*p_eglGetCurrentDisplay)(void);
static int (*p_eglGetError)(void);

static long thread_id(void) { return syscall(SYS_gettid); }

static int (*p_eglMakeCurrent)(void *, void *, void *, void *);

static void egl_load(void)
{
    static int done;
    if (done) return;
    done = 1;
    void *egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (egl) {
        p_eglGetCurrentContext = dlsym(egl, "eglGetCurrentContext");
        p_eglGetCurrentSurface = dlsym(egl, "eglGetCurrentSurface");
        p_eglGetCurrentDisplay = dlsym(egl, "eglGetCurrentDisplay");
        p_eglGetError = dlsym(egl, "eglGetError");
        p_eglMakeCurrent = dlsym(egl, "eglMakeCurrent");
    }
}

static int trace_on(void)
{
    if (glxtrace < 0) {
        const char *e = getenv("GLESPASS_GLXTRACE");
        glxtrace = e && *e && strcmp(e, "0") != 0;
        if (glxtrace) egl_load();
    }
    return glxtrace;
}

static const char *egl_state(void)
{
    static __thread char buf[160];
    snprintf(buf, sizeof buf, "egl ctx=%p draw=%p dpy=%p err=0x%x",
             p_eglGetCurrentContext ? p_eglGetCurrentContext() : NULL,
             p_eglGetCurrentSurface ? p_eglGetCurrentSurface(0x3059 /* EGL_DRAW */) : NULL,
             p_eglGetCurrentDisplay ? p_eglGetCurrentDisplay() : NULL,
             p_eglGetError ? p_eglGetError() : 0);
    return buf;
}

/* Unity redirects stderr into its -logFile and overwrites our lines there, so the trace goes to its
   own append-only file (GLESPASS_TRACEFILE) with one write() per line. */
static int trace_fd = -1;
static void trace_write(const char *fmt, ...)
{
    if (trace_fd < 0) {
        const char *f = getenv("GLESPASS_TRACEFILE");
        trace_fd = f && *f ? open(f, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644) : -1;
        if (trace_fd < 0) trace_fd = 2;
    }
    char line[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof line - 1) n = sizeof line - 1;
    if (n > 0 && write(trace_fd, line, n) < 0) {}
}
#define TRACE(...) trace_write("[glxtrace] tid %ld " __VA_ARGS__)

static int (*r_MakeCurrent)(void *, XID, void *);
static int t_MakeCurrent(void *d, XID dr, void *c)
{
    int r = r_MakeCurrent(d, dr, c);
    TRACE("glXMakeCurrent(dpy=%p, drawable=0x%lx, ctx=%p) = %d | %s\n", thread_id(), d, dr, c, r, egl_state());
    return r;
}
static int (*r_MakeContextCurrent)(void *, XID, XID, void *);
static int t_MakeContextCurrent(void *d, XID dr, XID rd, void *c)
{
    int r = r_MakeContextCurrent(d, dr, rd, c);
    TRACE("glXMakeContextCurrent(dpy=%p, draw=0x%lx, read=0x%lx, ctx=%p) = %d | %s\n", thread_id(), d, dr, rd, c, r,
          egl_state());
    return r;
}
static void *(*r_CreateContextAttribsARB)(void *, void *, void *, int, const int *);
static void *t_CreateContextAttribsARB(void *d, void *cfg, void *share, int direct, const int *attr)
{
    void *c = r_CreateContextAttribsARB(d, cfg, share, direct, attr);
    char a[200] = "";
    for (int i = 0, n = 0; attr && attr[i] && i < 20; i += 2)
        n += snprintf(a + n, sizeof a - n, "0x%x=0x%x ", attr[i], attr[i + 1]);
    TRACE("glXCreateContextAttribsARB(cfg=%p, share=%p, direct=%d, attribs: %s) = %p | %s\n", thread_id(), cfg, share,
          direct, a, c, egl_state());
    return c;
}
static void *(*r_CreateContext)(void *, void *, void *, int);
static void *t_CreateContext(void *d, void *vis, void *share, int direct)
{
    void *c = r_CreateContext(d, vis, share, direct);
    TRACE("glXCreateContext(vis=%p, share=%p, direct=%d) = %p | %s\n", thread_id(), vis, share, direct, c, egl_state());
    return c;
}
static void *(*r_CreateNewContext)(void *, void *, int, void *, int);
static void *t_CreateNewContext(void *d, void *cfg, int type, void *share, int direct)
{
    void *c = r_CreateNewContext(d, cfg, type, share, direct);
    TRACE("glXCreateNewContext(cfg=%p, type=0x%x, share=%p, direct=%d) = %p | %s\n", thread_id(), cfg, type, share,
          direct, c, egl_state());
    return c;
}
static void (*r_DestroyContext)(void *, void *);
static void t_DestroyContext(void *d, void *c)
{
    TRACE("glXDestroyContext(ctx=%p) | before: %s\n", thread_id(), c, egl_state());
    r_DestroyContext(d, c);
}
static void (*r_SwapBuffers)(void *, XID);
static void t_SwapBuffers(void *d, XID dr)
{
    static __thread int n;
    r_SwapBuffers(d, dr);
    if (++n <= 3 || n == 100 || n == 1000)
        TRACE("glXSwapBuffers #%d (drawable=0x%lx) | %s\n", thread_id(), n, dr, egl_state());
}

/* first calls of a few GL functions on each thread */
static void (*r_Clear)(unsigned);
static void t_Clear(unsigned m)
{
    static __thread int n;
    if (++n <= 2) TRACE("glClear(0x%x) call %d | %s\n", thread_id(), m, n, egl_state());
    r_Clear(m);
}
static void (*r_UseProgram)(unsigned);
static void t_UseProgram(unsigned p)
{
    static __thread int n;
    if (++n <= 2) TRACE("glUseProgram(%u) call %d | %s\n", thread_id(), p, n, egl_state());
    r_UseProgram(p);
}
static void (*r_DrawElements)(unsigned, int, unsigned, const void *);
static void t_DrawElements(unsigned mode, int count, unsigned type, const void *idx)
{
    static __thread int n;
    if (++n <= 2) TRACE("glDrawElements(count=%d) call %d | %s\n", thread_id(), count, n, egl_state());
    r_DrawElements(mode, count, type, idx);
}
static unsigned (*r_CreateShader)(unsigned);
static unsigned t_CreateShader(unsigned type)
{
    static __thread int n;
    unsigned s = r_CreateShader(type);
    if (++n <= 3) TRACE("glCreateShader(0x%x) = %u | %s\n", thread_id(), type, s, egl_state());
    return s;
}
static void (*r_Viewport)(int, int, int, int);
static void t_Viewport(int x, int y, int w, int h)
{
    static __thread int n;
    if (++n <= 2) TRACE("glViewport(%d,%d,%d,%d) call %d | %s\n", thread_id(), x, y, w, h, n, egl_state());
    r_Viewport(x, y, w, h);
}

static const struct { const char *name; void **real; void *wrapper; } trace_table[] = {
    {"glXMakeCurrent", (void **)&r_MakeCurrent, (void *)t_MakeCurrent},
    {"glXMakeContextCurrent", (void **)&r_MakeContextCurrent, (void *)t_MakeContextCurrent},
    {"glXCreateContextAttribsARB", (void **)&r_CreateContextAttribsARB, (void *)t_CreateContextAttribsARB},
    {"glXCreateContext", (void **)&r_CreateContext, (void *)t_CreateContext},
    {"glXCreateNewContext", (void **)&r_CreateNewContext, (void *)t_CreateNewContext},
    {"glXDestroyContext", (void **)&r_DestroyContext, (void *)t_DestroyContext},
    {"glXSwapBuffers", (void **)&r_SwapBuffers, (void *)t_SwapBuffers},
    {"glClear", (void **)&r_Clear, (void *)t_Clear},
    {"glUseProgram", (void **)&r_UseProgram, (void *)t_UseProgram},
    {"glDrawElements", (void **)&r_DrawElements, (void *)t_DrawElements},
    {"glCreateShader", (void **)&r_CreateShader, (void *)t_CreateShader},
    {"glViewport", (void **)&r_Viewport, (void *)t_Viewport},
};
#define TRACE_COUNT (sizeof trace_table / sizeof trace_table[0])


/* ---- context handoff (GLESPASS_CTXFIX=1) ----
   crusty's glXMakeCurrent only does bookkeeping: its single EGL context stays current on the thread
   that created it (the main thread) forever. With Unity's threaded renderer the main thread releases
   the context and the render thread binds it, so the render thread ends up with no EGL context and
   every GL call it makes is dropped. Here the release / bind is done for real on crusty's EGL
   context, display and surface (captured from the thread that has them current). */
static int ctxfix = -1;
static void *g_dpy, *g_draw, *g_read, *g_ctx;

/* crusty presents through SDL2, and SDL_GL_SwapWindow refuses a window that SDL has not made
   current on the calling thread (SDL keeps that per thread). So when crusty's SDL is found, the
   handoff goes through SDL_GL_MakeCurrent with crusty's own window and SDL context; raw EGL is the
   fallback. */
static void *g_win, *g_sdlctx;
static void *(*p_SDL_GL_GetCurrentWindow)(void);
static void *(*p_SDL_GL_GetCurrentContext)(void);
static int (*p_SDL_GL_MakeCurrent)(void *, void *);
static const char *(*p_SDL_GetError)(void);

static void sdl_load(void)
{
    const char *names[] = {getenv("CRUSTY_LIBSDL"), "libSDL2-2.0.so.0", "libSDL2.so", NULL};
    void *h = NULL;
    for (int i = 0; !h && i < 3; i++)
        if (names[i] && *names[i]) h = dlopen(names[i], RTLD_NOW | RTLD_NOLOAD);
    if (!h) h = RTLD_DEFAULT;
    p_SDL_GL_GetCurrentWindow = dlsym(h, "SDL_GL_GetCurrentWindow");
    p_SDL_GL_GetCurrentContext = dlsym(h, "SDL_GL_GetCurrentContext");
    p_SDL_GL_MakeCurrent = dlsym(h, "SDL_GL_MakeCurrent");
    p_SDL_GetError = dlsym(h, "SDL_GetError");
}

static int ctxfix_on(void)
{
    if (ctxfix < 0) {
        const char *e = getenv("GLESPASS_CTXFIX");
        ctxfix = e && *e && strcmp(e, "0") != 0;
        if (ctxfix) egl_load();
        if (ctxfix && !p_eglMakeCurrent) ctxfix = 0;
        trace_write("[glespass] context handoff %s\n", ctxfix ? "on" : "off");
    }
    return ctxfix;
}

static void ctx_handoff(int bind)
{
    void *cur = p_eglGetCurrentContext();
    if (!g_ctx && cur) {
        g_ctx = cur;
        g_dpy = p_eglGetCurrentDisplay();
        g_draw = p_eglGetCurrentSurface(0x3059 /* EGL_DRAW */);
        g_read = p_eglGetCurrentSurface(0x305A /* EGL_READ */);
        sdl_load();
        if (p_SDL_GL_GetCurrentWindow && p_SDL_GL_GetCurrentContext && p_SDL_GL_MakeCurrent) {
            g_win = p_SDL_GL_GetCurrentWindow();
            g_sdlctx = p_SDL_GL_GetCurrentContext();
        }
        trace_write("[glespass] captured EGL ctx %p dpy %p surf %p/%p, SDL window %p ctx %p, on tid %ld\n", g_ctx,
                    g_dpy, g_draw, g_read, g_win, g_sdlctx, thread_id());
    }
    if (!g_ctx) return;
    if (g_win && g_sdlctx) {
        /* SDL skips the call itself when nothing changes on this thread */
        if (p_SDL_GL_MakeCurrent(g_win, bind ? g_sdlctx : NULL) < 0)
            trace_write("[glespass] SDL_GL_MakeCurrent(%s) failed: %s tid %ld\n", bind ? "bind" : "release",
                        p_SDL_GetError ? p_SDL_GetError() : "?", thread_id());
        return;
    }
    if (!bind) {
        if (cur == g_ctx && !p_eglMakeCurrent(g_dpy, NULL, NULL, NULL))
            trace_write("[glespass] eglMakeCurrent(release) failed 0x%x tid %ld\n", p_eglGetError(), thread_id());
    } else if (cur != g_ctx) {
        if (!p_eglMakeCurrent(g_dpy, g_draw, g_read, g_ctx))
            trace_write("[glespass] eglMakeCurrent(bind) failed 0x%x tid %ld\n", p_eglGetError(), thread_id());
    }
}

static int (*f_real_MakeCurrent)(void *, XID, void *);
static int f_MakeCurrent(void *d, XID dr, void *c)
{
    int r = f_real_MakeCurrent(d, dr, c);
    if (r) ctx_handoff(c != NULL);
    return r;
}
static int (*f_real_MakeContextCurrent)(void *, XID, XID, void *);
static int f_MakeContextCurrent(void *d, XID dr, XID rd, void *c)
{
    int r = f_real_MakeContextCurrent(d, dr, rd, c);
    if (r) ctx_handoff(c != NULL);
    return r;
}

/* ---- FPS log (GLESPASS_FPSFILE=path) ----
   crusty prints its FPS to stdout, which Unity's -logFile overwrites; count swaps here instead and
   append one "[CRUSTY] FPS: x" line per second (same format the launcher's bench parser reads). */
static int fpslog = -1, fps_fd = -1;
static int fpslog_on(void)
{
    if (fpslog < 0) {
        const char *f = getenv("GLESPASS_FPSFILE");
        fps_fd = f && *f ? open(f, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644) : -1;
        fpslog = fps_fd >= 0;
    }
    return fpslog;
}
/* ---- frame alpha (GLESPASS_OPAQUE=1) and frame sampling (with GLESPASS_GLXTRACE) ----
   Under a Wayland compositor (ROCKNIX's sway) the window's alpha channel is used for blending;
   Unity leaves it below 1, so the frame can show up transparent over a black background.
   OPAQUE sets alpha to 1 across the default framebuffer right before each swap (colour untouched).
   The trace samples a few pixels of the finished frame to show what is being presented. */
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_SCISSOR_TEST 0x0C11
#define GL_COLOR_CLEAR_VALUE 0x0C22
#define GL_COLOR_WRITEMASK 0x0C23
#define GL_VIEWPORT 0x0BA2
#define GL_FRAMEBUFFER 0x8D40
#define GL_DRAW_FRAMEBUFFER_BINDING 0x8CA6
#define GL_READ_FRAMEBUFFER_BINDING 0x8CAA
#define GL_READ_FRAMEBUFFER 0x8CA8
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#define GL_RGBA 0x1908
#define GL_UNSIGNED_BYTE 0x1401
static int opaque = -1;
static struct {
    void (*GetIntegerv)(unsigned, int *);
    void (*GetFloatv)(unsigned, float *);
    void (*GetBooleanv)(unsigned, unsigned char *);
    unsigned char (*IsEnabled)(unsigned);
    void (*Enable)(unsigned), (*Disable)(unsigned);
    void (*BindFramebuffer)(unsigned, unsigned);
    void (*ColorMask)(unsigned char, unsigned char, unsigned char, unsigned char);
    void (*ClearColor)(float, float, float, float);
    void (*Clear)(unsigned);
    void (*ReadPixels)(int, int, int, int, unsigned, unsigned, void *);
} G;

static int frame_gl_ready(void)
{
    if (!G.Clear) {
        G.GetIntegerv = lookup("glGetIntegerv"); G.GetFloatv = lookup("glGetFloatv");
        G.GetBooleanv = lookup("glGetBooleanv"); G.IsEnabled = lookup("glIsEnabled");
        G.Enable = lookup("glEnable"); G.Disable = lookup("glDisable");
        G.BindFramebuffer = lookup("glBindFramebuffer"); G.ColorMask = lookup("glColorMask");
        G.ClearColor = lookup("glClearColor"); G.ReadPixels = lookup("glReadPixels");
        G.Clear = lookup("glClear");
    }
    return G.GetIntegerv && G.GetFloatv && G.GetBooleanv && G.IsEnabled && G.Enable && G.Disable &&
           G.BindFramebuffer && G.ColorMask && G.ClearColor && G.ReadPixels && G.Clear;
}

static void sample_frame(int n)
{
    int drawfb = 0, readfb = 0, vp[4] = {0};
    G.GetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawfb);
    G.GetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readfb);
    G.GetIntegerv(GL_VIEWPORT, vp);
    G.BindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    int w = vp[2] > 0 ? vp[0] + vp[2] : 1, h = vp[3] > 0 ? vp[1] + vp[3] : 1;
    int pts[5][2] = {{w / 2, h / 2}, {w / 4, h / 4}, {3 * w / 4, h / 4}, {w / 4, 3 * h / 4}, {3 * w / 4, 3 * h / 4}};
    char buf[256]; int len = 0;
    for (int i = 0; i < 5; i++) {
        unsigned char px[4] = {0};
        G.ReadPixels(pts[i][0], pts[i][1], 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
        len += snprintf(buf + len, sizeof buf - len, " (%d,%d)=%d,%d,%d,a%d", pts[i][0], pts[i][1], px[0], px[1], px[2], px[3]);
    }
    static unsigned (*get_error)(void);
    if (!get_error) get_error = lookup("glGetError");
    unsigned err = get_error ? get_error() : 0;
    trace_write("[glespass] frame %d before swap: draw fb %d, viewport %dx%d, glGetError 0x%x, pixels%s\n", n, drawfb,
                vp[2], vp[3], err, buf);
    /* whole frame as a PPM next to the trace file (GLESPASS_TRACEFILE dir/frame_<n>.ppm) */
    const char *tf = getenv("GLESPASS_TRACEFILE");
    if (tf && *tf && w > 1 && h > 1 && w <= 4096 && h <= 4096) {
        unsigned char *px = malloc((size_t)w * h * 4);
        char path[512];
        const char *slash = strrchr(tf, '/');
        int dirlen = slash ? (int)(slash - tf) : 0;
        snprintf(path, sizeof path, "%.*s%sframe_%05d.ppm", dirlen, tf, dirlen ? "/" : "", n);
        int fd = px ? open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644) : -1;
        if (fd >= 0) {
            G.ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px);
            char hdr[32];
            int hl = snprintf(hdr, sizeof hdr, "P6\n%d %d\n255\n", w, h);
            if (write(fd, hdr, hl) < 0) {}
            unsigned char *row = malloc((size_t)w * 3);
            for (int y = h - 1; row && y >= 0; y--) {           /* GL rows are bottom-up */
                for (int x = 0; x < w; x++)
                    memcpy(row + 3 * x, px + 4 * ((size_t)y * w + x), 3);
                if (write(fd, row, (size_t)w * 3) < 0) {}
            }
            free(row);
            close(fd);
        }
        free(px);
    }
    G.BindFramebuffer(GL_READ_FRAMEBUFFER, readfb);
}

/* GLESPASS_TESTCOLOR=1: paint every frame solid magenta just before presenting it, to check that
   whatever is drawn through this path actually reaches the screen */
static void paint_test_color(void)
{
    int drawfb = 0;
    float cc[4];
    unsigned char mask[4];
    G.GetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawfb);
    G.GetFloatv(GL_COLOR_CLEAR_VALUE, cc);
    G.GetBooleanv(GL_COLOR_WRITEMASK, mask);
    unsigned char scissor = G.IsEnabled(GL_SCISSOR_TEST);
    if (drawfb) G.BindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    if (scissor) G.Disable(GL_SCISSOR_TEST);
    G.ColorMask(1, 1, 1, 1);
    G.ClearColor(1, 0, 1, 1);
    G.Clear(GL_COLOR_BUFFER_BIT);
    G.ColorMask(mask[0], mask[1], mask[2], mask[3]);
    G.ClearColor(cc[0], cc[1], cc[2], cc[3]);
    if (scissor) G.Enable(GL_SCISSOR_TEST);
    if (drawfb) G.BindFramebuffer(GL_DRAW_FRAMEBUFFER, drawfb);
}

static void make_opaque(void)
{
    int drawfb = 0;
    float cc[4];
    unsigned char mask[4];
    G.GetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawfb);
    G.GetFloatv(GL_COLOR_CLEAR_VALUE, cc);
    G.GetBooleanv(GL_COLOR_WRITEMASK, mask);
    unsigned char scissor = G.IsEnabled(GL_SCISSOR_TEST);
    if (drawfb) G.BindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    if (scissor) G.Disable(GL_SCISSOR_TEST);
    G.ColorMask(0, 0, 0, 1);
    G.ClearColor(0, 0, 0, 1);
    G.Clear(GL_COLOR_BUFFER_BIT);
    G.ColorMask(mask[0], mask[1], mask[2], mask[3]);
    G.ClearColor(cc[0], cc[1], cc[2], cc[3]);
    if (scissor) G.Enable(GL_SCISSOR_TEST);
    if (drawfb) G.BindFramebuffer(GL_DRAW_FRAMEBUFFER, drawfb);
}

/* ---- frame probe (GLESPASS_PROBE=N) ----
   During frame N (counted in swaps) logs the framebuffer, texture, draw, clear, blit and
   invalidate calls, the formats of the textures attached to each framebuffer, and the centre
   pixel of a framebuffer whenever the frame switches away from it (and of the default framebuffer
   at the swap). Shows at which step a frame's content goes missing. */
static int probe_n = -1;
static volatile int g_swaps;
static int probe_on(void)
{
    if (probe_n < 0) {
        const char *e = getenv("GLESPASS_PROBE");
        probe_n = e ? atoi(e) : 0;
    }
    return probe_n > 0;
}
static int probing(void) { return probe_n > 0 && g_swaps == probe_n - 1; }

static struct { unsigned id; unsigned fmt; int w, h, levels; } ptex[512];
static int nptex;
static void ptex_set(unsigned id, unsigned fmt, int w, int h, int levels)
{
    int k;
    for (k = 0; k < nptex; k++) if (ptex[k].id == id) break;
    if (k == nptex) { if (nptex == 512) return; nptex++; }
    ptex[k].id = id; ptex[k].fmt = fmt; ptex[k].w = w; ptex[k].h = h; ptex[k].levels = levels;
}
static const char *ptex_desc(unsigned id)
{
    static char b[4][64]; static int r;
    char *s = b[r++ & 3];
    for (int k = 0; k < nptex; k++)
        if (ptex[k].id == id) {
            snprintf(s, 64, "tex %u fmt 0x%x %dx%d lv %d", id, ptex[k].fmt, ptex[k].w, ptex[k].h, ptex[k].levels);
            return s;
        }
    snprintf(s, 64, "tex %u (unknown fmt)", id);
    return s;
}

static void (*pr_GetIntegerv)(unsigned, int *);
static void (*pr_ReadPixels)(int, int, int, int, unsigned, unsigned, void *);
static void (*pr_BindFramebufferReal)(unsigned, unsigned);
static unsigned (*pr_GetError)(void);
static unsigned (*pr_CheckFramebufferStatus)(unsigned);

static void probe_pixel(const char *why)
{
    if (!pr_ReadPixels) {
        pr_GetIntegerv = lookup("glGetIntegerv"); pr_ReadPixels = lookup("glReadPixels");
        pr_GetError = lookup("glGetError"); pr_CheckFramebufferStatus = lookup("glCheckFramebufferStatus");
        if (!pr_BindFramebufferReal) pr_BindFramebufferReal = lookup("glBindFramebuffer");
    }
    int draw = 0, read = 0, vp[4] = {0};
    pr_GetIntegerv(0x8CA6, &draw); pr_GetIntegerv(0x8CAA, &read); pr_GetIntegerv(0x0BA2, vp);
    pr_BindFramebufferReal(0x8CA8, draw);
    unsigned st = pr_CheckFramebufferStatus(0x8CA8);
    int fmt = 0, type = 0;
    pr_GetIntegerv(0x8B9B, &fmt); pr_GetIntegerv(0x8B9A, &type);
    int pack = 0;
    pr_GetIntegerv(0x88ED /* GL_PIXEL_PACK_BUFFER_BINDING */, &pack);
    void (*bindbuf)(unsigned, unsigned) = lookup("glBindBuffer");
    if (pack) bindbuf(0x88EB, 0);
    unsigned char px[16] = {0};
    while (pr_GetError()) {}
    pr_ReadPixels(vp[0] + vp[2] / 2, vp[1] + vp[3] / 2, 1, 1, fmt, type, px);
    unsigned err = pr_GetError();
    unsigned char px8[4] = {0};
    pr_ReadPixels(vp[0] + vp[2] / 2, vp[1] + vp[3] / 2, 1, 1, 0x1908, 0x1401, px8);
    unsigned err8 = pr_GetError();
    if (pack) bindbuf(0x88EB, pack);
    pr_BindFramebufferReal(0x8CA8, read);
    fprintf(stderr, "[probe]   pixel (%s) fbo %d vp %d,%d %dx%d status 0x%x readfmt 0x%x/0x%x raw "
            "%02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x %02x%02x%02x%02x err 0x%x rgba8 %u,%u,%u,%u err 0x%x\n",
            why, draw, vp[0], vp[1], vp[2], vp[3], st, fmt, type, px[0], px[1], px[2], px[3], px[4], px[5], px[6],
            px[7], px[8], px[9], px[10], px[11], px[12], px[13], px[14], px[15], err, px8[0], px8[1], px8[2], px8[3],
            err8);
}

static int pr_draws;
static void pr_flush_draws(void)
{
    if (pr_draws) fprintf(stderr, "[probe]   %d draws\n", pr_draws);
    pr_draws = 0;
}

static void (*r_BindFramebuffer)(unsigned, unsigned);
static void w_BindFramebuffer(unsigned t, unsigned fb)
{
    if (probing() && t != 0x8CA8) {
        int cur = 0;
        if (!pr_ReadPixels) probe_pixel("first");
        pr_GetIntegerv(0x8CA6, &cur);
        if ((unsigned)cur != fb) {
            pr_flush_draws();
            probe_pixel("leaving");
            fprintf(stderr, "[probe] bind fbo %u (target 0x%x)\n", fb, t);
        }
    }
    r_BindFramebuffer(t, fb);
}
static void (*r_FramebufferTexture2D)(unsigned, unsigned, unsigned, unsigned, int);
static void w_FramebufferTexture2D(unsigned t, unsigned att, unsigned tt, unsigned tex, int lv)
{
    if (probing()) fprintf(stderr, "[probe]   attach 0x%x %s level %d\n", att, ptex_desc(tex), lv);
    r_FramebufferTexture2D(t, att, tt, tex, lv);
}
static void (*r_FramebufferRenderbuffer)(unsigned, unsigned, unsigned, unsigned);
static void w_FramebufferRenderbuffer(unsigned t, unsigned att, unsigned rt, unsigned rb)
{
    if (probing()) fprintf(stderr, "[probe]   attach 0x%x renderbuffer %u\n", att, rb);
    r_FramebufferRenderbuffer(t, att, rt, rb);
}
static void (*r_TexStorage2D)(unsigned, int, unsigned, int, int);
static void w_TexStorage2D(unsigned t, int lv, unsigned fmt, int w, int h)
{
    int id = 0;
    if (!pr_GetIntegerv) pr_GetIntegerv = lookup("glGetIntegerv");
    pr_GetIntegerv(t == 0x0DE1 ? 0x8069 : 0x8069, &id);
    ptex_set(id, fmt, w, h, lv);
    r_TexStorage2D(t, lv, fmt, w, h);
}
static void (*r_TexImage2D)(unsigned, int, int, int, int, int, unsigned, unsigned, const void *);
static void w_TexImage2D(unsigned t, int lv, int fmt, int w, int h, int b, unsigned f, unsigned ty, const void *p)
{
    if (lv == 0 && t == 0x0DE1) {
        int id = 0;
        if (!pr_GetIntegerv) pr_GetIntegerv = lookup("glGetIntegerv");
        pr_GetIntegerv(0x8069, &id);
        ptex_set(id, fmt, w, h, 1);
    }
    r_TexImage2D(t, lv, fmt, w, h, b, f, ty, p);
}
static void (*r_Clear)(unsigned);
static void w_Clear(unsigned m)
{
    if (probing()) { pr_flush_draws(); fprintf(stderr, "[probe]   clear 0x%x\n", m); }
    r_Clear(m);
}
static void (*r_ClearBufferfv)(unsigned, int, const float *);
static void w_ClearBufferfv(unsigned b, int i, const float *v)
{
    if (probing()) { pr_flush_draws(); fprintf(stderr, "[probe]   clearbufferfv 0x%x %d (%g %g %g %g)\n", b, i, v[0], b == 0x1800 ? v[1] : 0, b == 0x1800 ? v[2] : 0, b == 0x1800 ? v[3] : 0); }
    r_ClearBufferfv(b, i, v);
}
static void (*r_BlitFramebuffer)(int, int, int, int, int, int, int, int, unsigned, unsigned);
static void w_BlitFramebuffer(int a, int b, int c, int d, int e, int f, int g, int h, unsigned m, unsigned flt)
{
    if (probing()) {
        int rd = 0, dr = 0;
        pr_flush_draws();
        pr_GetIntegerv(0x8CAA, &rd); pr_GetIntegerv(0x8CA6, &dr);
        fprintf(stderr, "[probe]   blit fbo %d -> %d (%d,%d,%d,%d -> %d,%d,%d,%d) mask 0x%x filter 0x%x\n", rd, dr, a, b, c, d, e, f, g, h, m, flt);
    }
    r_BlitFramebuffer(a, b, c, d, e, f, g, h, m, flt);
    if (probing()) { unsigned er = pr_GetError(); if (er) fprintf(stderr, "[probe]   blit error 0x%x\n", er); }
}
static void (*r_InvalidateFramebuffer)(unsigned, int, const unsigned *);
static void w_InvalidateFramebuffer(unsigned t, int n, const unsigned *att)
{
    if (probing()) {
        int dr = 0;
        pr_flush_draws();
        pr_GetIntegerv(0x8CA6, &dr);
        fprintf(stderr, "[probe]   invalidate target 0x%x (draw fbo %d):", t, dr);
        for (int i = 0; i < n; i++) fprintf(stderr, " 0x%x", att[i]);
        fprintf(stderr, "\n");
    }
    r_InvalidateFramebuffer(t, n, att);
}
static void (*r_UseProgram)(unsigned);
static unsigned pr_lastprog;
static void w_UseProgram(unsigned p)
{
    if (probing() && p != pr_lastprog) { pr_flush_draws(); fprintf(stderr, "[probe]   program %u\n", p); }
    pr_lastprog = p;
    r_UseProgram(p);
}
static void (*r_DrawElements)(unsigned, int, unsigned, const void *);
static void w_DrawElements(unsigned m, int c, unsigned t, const void *i) { if (probing()) pr_draws++; r_DrawElements(m, c, t, i); }
static void (*r_DrawArrays)(unsigned, int, int);
static void w_DrawArrays(unsigned m, int f, int c) { if (probing()) pr_draws++; r_DrawArrays(m, f, c); }
static void (*r_DrawElementsBaseVertex)(unsigned, int, unsigned, const void *, int);
static void w_DrawElementsBaseVertex(unsigned m, int c, unsigned t, const void *i, int bv) { if (probing()) pr_draws++; r_DrawElementsBaseVertex(m, c, t, i, bv); }
static void (*r_DrawElementsInstanced)(unsigned, int, unsigned, const void *, int);
static void w_DrawElementsInstanced(unsigned m, int c, unsigned t, const void *i, int n) { if (probing()) pr_draws++; r_DrawElementsInstanced(m, c, t, i, n); }
static void (*r_DrawArraysInstanced)(unsigned, int, int, int);
static void w_DrawArraysInstanced(unsigned m, int f, int c, int n) { if (probing()) pr_draws++; r_DrawArraysInstanced(m, f, c, n); }
static void (*r_DrawRangeElements)(unsigned, unsigned, unsigned, int, unsigned, const void *);
static void w_DrawRangeElements(unsigned m, unsigned s, unsigned e, int c, unsigned t, const void *i) { if (probing()) pr_draws++; r_DrawRangeElements(m, s, e, c, t, i); }
static void (*r_DrawElementsInstancedBaseVertex)(unsigned, int, unsigned, const void *, int, int);
static void w_DrawElementsInstancedBaseVertex(unsigned m, int c, unsigned t, const void *i, int n, int bv) { if (probing()) pr_draws++; r_DrawElementsInstancedBaseVertex(m, c, t, i, n, bv); }

static const struct { const char *name; void **real; void *wrapper; } probe_table[] = {
#define P(n) {"gl" #n, (void **)&r_##n, (void *)w_##n}
    P(BindFramebuffer), P(FramebufferTexture2D), P(FramebufferRenderbuffer), P(TexStorage2D), P(TexImage2D),
    P(Clear), P(ClearBufferfv), P(BlitFramebuffer), P(InvalidateFramebuffer), P(UseProgram), P(DrawElements),
    P(DrawArrays), P(DrawElementsBaseVertex), P(DrawElementsInstanced), P(DrawArraysInstanced),
    P(DrawRangeElements), P(DrawElementsInstancedBaseVertex),
#undef P
};
#define PROBE_COUNT (sizeof probe_table / sizeof probe_table[0])

static void probe_swap(void)
{
    if (probing()) {
        pr_flush_draws();
        probe_pixel("before swap");
        fprintf(stderr, "[probe] ---- end of frame %d ----\n", probe_n);
    }
    g_swaps++;
    if (probing()) {
        fprintf(stderr, "[probe] ---- frame %d ----\n", probe_n);
        probe_pixel("frame start");
    }
}

/* ---- GL_VENDOR / GL_RENDERER override (GLESPASS_VENDOR, GLESPASS_RENDERER) ----
   Unity picks GPU specific behaviour from these strings: for a tile based GPU (Mali, Adreno,
   PowerVR) it turns a "don't care" load action into a clear, which wipes a camera target that
   a later camera is meant to draw over. */
static const unsigned char *(*r_GetString)(unsigned);
static const unsigned char *w_GetString(unsigned name)
{
    const char *e = name == 0x1F00 ? getenv("GLESPASS_VENDOR") : name == 0x1F01 ? getenv("GLESPASS_RENDERER") : NULL;
    if (e && *e) return (const unsigned char *)e;
    return r_GetString(name);
}

/* ---- X input focus (GLESPASS_FOCUS=1) ----
   Under Westonpack's headless Weston the Xwayland window may never receive input focus, and
   Unity's Input System ignores keyboard and gamepad input while the player is unfocused. This
   gives the window the game presents to X input focus (through the game's own, natively wrapped
   Xlib connection) whenever it does not have it, checked every 120 frames. */
static int focus_on = -1;
static void focus_check(void *dpy, XID win)
{
    static int (*p_SetInputFocus)(void *, XID, int, unsigned long);
    static int (*p_GetInputFocus)(void *, XID *, int *);
    static int (*p_Flush)(void *);
    static int frames;
    if (focus_on < 0) {
        const char *e = getenv("GLESPASS_FOCUS");
        focus_on = e && *e && strcmp(e, "0") != 0;
        if (focus_on) {
            void *x = dlopen("libX11.so.6", RTLD_NOW | RTLD_NOLOAD);
            if (!x) x = RTLD_DEFAULT;
            p_SetInputFocus = dlsym(x, "XSetInputFocus");
            p_GetInputFocus = dlsym(x, "XGetInputFocus");
            p_Flush = dlsym(x, "XFlush");
            if (!p_SetInputFocus || !p_GetInputFocus || !p_Flush) {
                fprintf(stderr, "[glespass] focus: Xlib not found\n");
                focus_on = 0;
            }
        }
    }
    if (!focus_on || !dpy || !win || frames++ % 120 != 30) return;
    XID cur = 0;
    int revert = 0;
    p_GetInputFocus(dpy, &cur, &revert);
    if (cur == win) return;
    p_SetInputFocus(dpy, win, 2 /* RevertToParent */, 0 /* CurrentTime */);
    p_Flush(dpy);
    fprintf(stderr, "[glespass] focus: gave window 0x%lx input focus (had 0x%lx)\n", (unsigned long)win, (unsigned long)cur);
}

static void (*f_real_SwapBuffers)(void *, XID);
static void f_SwapBuffers(void *d, XID dr)
{
    static int frames;
    static struct timespec t0;
    struct timespec t;
    static __thread int swaps;
    static long render_tid;
    if (opaque < 0) {
        const char *e = getenv("GLESPASS_OPAQUE");
        opaque = e && *e && strcmp(e, "0") != 0;
    }
    static int testcolor = -1;
    if (testcolor < 0) {
        const char *e = getenv("GLESPASS_TESTCOLOR");
        testcolor = e && *e && strcmp(e, "0") != 0;
    }
    int n = swaps + 1;
    int sample = trace_on() && (n == 100 || n == 300 || n == 600 || n == 900 || n == 1200 || n == 1800 ||
                                n == 2400 || n == 3600);
    if ((opaque || sample || testcolor) && frame_gl_ready()) {
        if (sample) sample_frame(n);
        if (testcolor) paint_test_color();
        else if (opaque) make_opaque();
    }
    if (probe_on()) probe_swap();
    focus_check(d, dr);
    f_real_SwapBuffers(d, dr);
    /* tell the launcher's THREAD_PIN loop which thread renders (GLESPASS_RENDERTID=path) */
    long tid = thread_id();
    if (tid != render_tid) {
        render_tid = tid;
        const char *f = getenv("GLESPASS_RENDERTID");
        int fd = f && *f ? open(f, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644) : -1;
        if (fd >= 0) {
            char b[32];
            int n = snprintf(b, sizeof b, "%ld\n", tid);
            if (write(fd, b, n) < 0) {}
            close(fd);
        }
    }
    if (++swaps <= 2 && p_SDL_GetError)
        trace_write("[glespass] tid %ld swap %d, SDL_GetError: '%s'\n", thread_id(), swaps, p_SDL_GetError());
    if (!fpslog_on())
        return;
    clock_gettime(CLOCK_MONOTONIC, &t);
    if (!t0.tv_sec) t0 = t;
    frames++;
    double dt = (t.tv_sec - t0.tv_sec) + (t.tv_nsec - t0.tv_nsec) / 1e9;
    if (dt >= 1.0) {
        char line[64];
        int n = snprintf(line, sizeof line, "[CRUSTY] FPS: %.1f\n", frames / dt);
        if (write(fps_fd, line, n) < 0) {}
        frames = 0;
        t0 = t;
    }
}

static int is_wrapper(void *p)
{
    if (p == (void *)w_GetString)
        return 1;
    if (p == (void *)glespass_CompileShader || p == (void *)glespass_LinkProgram)
        return 1;
    if (p == (void *)f_MakeCurrent || p == (void *)f_MakeContextCurrent || p == (void *)f_SwapBuffers)
        return 1;
    for (unsigned i = 0; i < TRACE_COUNT; i++)
        if (p == trace_table[i].wrapper)
            return 1;
    for (unsigned i = 0; i < PROBE_COUNT; i++)
        if (p == probe_table[i].wrapper)
            return 1;
    /* Anything inside this library (e.g. one of our trampolines, which crusty's getproc can find
       through the global scope because we are preloaded first) already routes through the wrapper
       table. Wrapping it again would make the wrapper call itself. */
    Dl_info self, found;
    if (dladdr((void *)is_wrapper, &self) && dladdr(p, &found) && self.dli_fbase == found.dli_fbase)
        return 1;
    return 0;
}

/* swap in the diagnostic wrappers for names Unity may resolve either way */
static void *hook(const char *name, void *real)
{
    /* already wrapped (e.g. crusty's getproc called back into gl4es_GetProcAddress) */
    if (!real || is_wrapper(real))
        return real;
    /* the handoff wrapper sits under the trace wrapper, so traced EGL state is after the handoff */
    if (ctxfix_on()) {
        if (!strcmp(name, "glXMakeCurrent")) {
            f_real_MakeCurrent = real;
            real = (void *)f_MakeCurrent;
        } else if (!strcmp(name, "glXMakeContextCurrent")) {
            f_real_MakeContextCurrent = real;
            real = (void *)f_MakeContextCurrent;
        }
    }
    /* always: it reports the render thread for THREAD_PIN, and handles FPS log / OPAQUE / sampling */
    if (!strcmp(name, "glXSwapBuffers")) {
        f_real_SwapBuffers = real;
        real = (void *)f_SwapBuffers;
    }
    if (trace_on())
        for (unsigned i = 0; i < TRACE_COUNT; i++)
            if (!strcmp(name, trace_table[i].name)) {
                *trace_table[i].real = real;
                return trace_table[i].wrapper;
            }
    if (!strcmp(name, "glGetString") && (getenv("GLESPASS_VENDOR") || getenv("GLESPASS_RENDERER"))) {
        r_GetString = real;
        return (void *)w_GetString;
    }
    if (probe_on())
        for (unsigned i = 0; i < PROBE_COUNT; i++)
            if (!strcmp(name, probe_table[i].name)) {
                *probe_table[i].real = real;
                if (!strcmp(name, "glBindFramebuffer")) pr_BindFramebufferReal = real;
                return probe_table[i].wrapper;
            }
    if (!strcmp(name, "glCompileShader")) {
        real_compile = real;
        fprintf(stderr, "[glespass] wrapping glCompileShader (real %p)\n", real);
        return (void *)glespass_CompileShader;
    }
    if (!strcmp(name, "glLinkProgram")) {
        real_link = real;
        fprintf(stderr, "[glespass] wrapping glLinkProgram (real %p)\n", real);
        return (void *)glespass_LinkProgram;
    }
    return real;
}

/* Unity resolves GL entry points through glXGetProcAddress, which crusty answers straight from
   the EGL driver. Wrap it so the diagnostic hooks apply to those lookups too. */
static void *(*crusty_getproc)(const char *);

static void *glespass_glXGetProcAddress(const char *name)
{
    static int calls;
    void *p = crusty_getproc ? crusty_getproc(name) : NULL;
    if (!p && crusty_lib && !strncmp(name, "glX", 3)) {
        /* fall back to crusty's exported GLX entry point */
        p = dlsym(crusty_lib, name);
        Dl_info self, found;
        if (p && dladdr((void *)glespass_init, &self) && dladdr(p, &found) && self.dli_fbase == found.dli_fbase)
            p = NULL;
    }
    void *r = hook(name, p);
    if (verbose || ++calls <= 3)
        fprintf(stderr, "[glespass] glXGetProcAddress(%s) -> %p%s\n", name, r, r != p ? " (wrapped)" : "");
    return r;
}

__attribute__((constructor(102))) static void glespass_hook_table(void)
{
    for (int i = 0; i < GLESPASS_NUM_GL; i++)
        glespass_ptrs[i] = hook(glespass_names[i], glespass_ptrs[i]);
    for (int i = GLESPASS_NUM_GL; i < GLESPASS_NUM_ALL; i++) {
        const char *n = glespass_names[i];
        if ((!strcmp(n, "glXGetProcAddress") || !strcmp(n, "glXGetProcAddressARB")) &&
            glespass_ptrs[i] != (void *)glespass_noop) {
            crusty_getproc = glespass_ptrs[i];
            glespass_ptrs[i] = (void *)glespass_glXGetProcAddress;
        } else if (glespass_ptrs[i] != (void *)glespass_noop) {
            glespass_ptrs[i] = hook(n, glespass_ptrs[i]);      /* GLX tracing, when enabled */
        }
    }
}

void initialize_gl4es(void) {}

void *gl4es_GetProcAddress(const char *name)
{
    void *p = hook(name, lookup_gl(name));
    if (verbose)
        fprintf(stderr, "[glespass] getproc %s -> %p\n", name, p);
    return p;
}
