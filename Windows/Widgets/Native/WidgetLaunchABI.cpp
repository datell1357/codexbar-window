#include "WidgetBackendABI.h"
#include "WidgetHostLaunch.h"
using CodexBar::Widgets::WidgetHostLaunch;

extern "C" int32_t CBWidgetLaunchCreate(uint16_t const* image, uint32_t units, void** launch) {
    if (!launch) return E_POINTER;
    *launch = nullptr;
    if (!image || !units || units > 32767) return E_INVALIDARG;
    try {
        *launch = new WidgetHostLaunch(std::wstring(reinterpret_cast<wchar_t const*>(image), units));
        return S_OK;
    } catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetLaunchProcess(void* launch, void** process) {
    if (!launch || !process) return E_POINTER;
    *process = static_cast<WidgetHostLaunch*>(launch)->Process();
    return *process ? S_OK : E_HANDLE;
}
extern "C" int32_t CBWidgetLaunchDeliver(void* launch, uint8_t const* bytes, uint32_t count) {
    if (!launch) return E_POINTER;
    try { static_cast<WidgetHostLaunch*>(launch)->Deliver(bytes, count); return S_OK; }
    catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetLaunchStop(void* launch) {
    if (!launch) return E_POINTER;
    try { static_cast<WidgetHostLaunch*>(launch)->Stop(); return S_OK; }
    catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetLaunchStatus(void* launch, uint32_t* phase, uint32_t* exitCode, uint32_t* forced) {
    if (!launch || !phase || !exitCode || !forced) return E_POINTER;
    try { static_cast<WidgetHostLaunch*>(launch)->Status(phase, exitCode, forced); return S_OK; }
    catch (...) { return winrt::to_hresult(); }
}
extern "C" int32_t CBWidgetLaunchDestroy(void* launch) {
    if (!launch) return S_OK;
    try {
        auto owner = static_cast<WidgetHostLaunch*>(launch);
        owner->Stop();
        delete owner;
        return S_OK;
    } catch (...) { return winrt::to_hresult(); }
}
