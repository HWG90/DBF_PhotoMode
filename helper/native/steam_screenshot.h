/* External WGC screenshot worker. No code is loaded into the game. */
#ifndef WJL_STEAM_SCREENSHOT_H
#define WJL_STEAM_SCREENSHOT_H
#include <windows.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Publication is linearized before the atomic, non-replacing handle rename.
 * Cancel may CAS OPEN -> CANCELLED without blocking the request thread.
 * Once PUBLISHING wins, a cancellation waits for worker retirement and may
 * observe success. No terminal reply is valid before the worker has exited. */
#define WJL_SCREENSHOT_OPEN 0
#define WJL_SCREENSHOT_CANCELLED 1
#define WJL_SCREENSHOT_PUBLISHING 2
#define WJL_SCREENSHOT_PUBLISHED 3

typedef struct WJLScreenshotRequest {
    DWORD pid;
    FILETIME created;
    const wchar_t *executable;
    const wchar_t *output_path;
    HANDLE cancel_event;
    volatile LONG *publication;
} WJLScreenshotRequest;

typedef struct WJLScreenshotResult {
    uint32_t error;
    uint32_t width;
    uint32_t height;
    uint32_t elapsed_ms;
} WJLScreenshotResult;

/* Called only on one owned job thread; releases WGC/WIC/COM resources before
 * returning. Returns a Windows error/HRESULT (zero on published success). */
DWORD wjl_steam_screenshot_capture(const WJLScreenshotRequest *request,
                                 WJLScreenshotResult *result);

#ifdef __cplusplus
}
#endif
#endif
