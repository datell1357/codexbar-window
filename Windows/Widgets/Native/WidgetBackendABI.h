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
// Additive launcher exports. Calls on one launch owner must be serialized on a blocking worker.
// Process returns a borrowed LOCAL HANDLE; retain the launch owner across every use and never close it.
CB_WIDGET_API int32_t CBWidgetLaunchCreate(const uint16_t* image, uint32_t units, void** launch);
// Blocking admission, 1..1000 ms. S_FALSE means no peer; S_OK transfers one authenticated host owner.
// Do not call while another admitted host remains owned. Cancel is checked between bounded calls.
CB_WIDGET_API int32_t CBWidgetLaunchAccept(uint32_t timeoutMilliseconds, void** launch);
CB_WIDGET_API int32_t CBWidgetLaunchProcess(void* launch, void** process);
CB_WIDGET_API int32_t CBWidgetLaunchDeliver(void* launch, const uint8_t* bytes, uint32_t count);
CB_WIDGET_API int32_t CBWidgetLaunchStop(void* launch);
// phase: 0 awaiting bootstrap (a child is suspended), 1 delivery started, 2 exited.
// Exit status and forced termination remain separate from cleanup success.
CB_WIDGET_API int32_t CBWidgetLaunchStatus(void* launch, uint32_t* phase, uint32_t* exitCode, uint32_t* forced);
CB_WIDGET_API int32_t CBWidgetLaunchDestroy(void* launch);
#ifdef __cplusplus
}
#endif
