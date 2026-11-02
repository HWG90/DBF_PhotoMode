#ifndef WJL_STEAM_SCREENSHOT_JOBS_H
#define WJL_STEAM_SCREENSHOT_JOBS_H
#include "steam_screenshot.h"
#define WJL_SCREENSHOT_PENDING 1u
#define WJL_SCREENSHOT_SUCCEEDED 2u
#define WJL_SCREENSHOT_FAILED 3u
#define WJL_SCREENSHOT_JOB_CANCELLED 4u
typedef struct WJLScreenshotJobStatus {
    uint32_t state,error,width,height,elapsed_ms;
    char id[33];
    wchar_t output_path[32768];
} WJLScreenshotJobStatus;
/* Serialized by the service exchange thread. No function waits for a worker,
 * except shutdown, called only after both client pipes have been closed. */
DWORD wjl_screenshot_job_request(DWORD client_pid,const wchar_t *expected_executable,
                                 const wchar_t *output_path,WJLScreenshotJobStatus *status);
DWORD wjl_screenshot_job_status(const wchar_t *id,WJLScreenshotJobStatus *status);
DWORD wjl_screenshot_job_cancel(const wchar_t *id,WJLScreenshotJobStatus *status);
void wjl_screenshot_jobs_cancel_all(void);
void wjl_screenshot_jobs_shutdown(void);
#endif
