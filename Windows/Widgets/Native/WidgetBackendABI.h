#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Status 0: response written; 1: invalid buffers; 2: closed/busy; 3: processing failure.
// The native worker supplies a 256 KiB output buffer. No allocation crosses this ABI.
// The context remains retained until cancellation, callback completion, and worker join are complete.
typedef int32_t (*CBWidgetRequestHandler)(void* context, const uint8_t* request, uint32_t requestSize,
    uint8_t* response, uint32_t responseCapacity, uint32_t* responseSize);
// All functions return HRESULT as int32_t. Calls that own the server are externally serialized.
// Cancel the Swift request bridge before Join/Destroy; join must not run on the callback/Swift executor thread.
#ifdef _WIN32
#define CB_WIDGET_API __declspec(dllexport)
#else
#define CB_WIDGET_API
#endif
CB_WIDGET_API uint32_t CBWidgetBackendABIVersion(void);
CB_WIDGET_API int32_t CBWidgetServerCreate(void* context, CBWidgetRequestHandler handler, void** server);
CB_WIDGET_API int32_t CBWidgetServerName(void* server, uint16_t* buffer, uint32_t capacity, uint32_t* required);
CB_WIDGET_API int32_t CBWidgetServerStart(void* server, void* trustedClientProcess);
CB_WIDGET_API int32_t CBWidgetServerCancel(void* server);
CB_WIDGET_API int32_t CBWidgetServerJoin(void* server);
CB_WIDGET_API int32_t CBWidgetServerStatus(void* server, uint32_t* phase, int32_t* result);
CB_WIDGET_API int32_t CBWidgetServerDestroy(void* server);
#ifdef __cplusplus
}
#endif
