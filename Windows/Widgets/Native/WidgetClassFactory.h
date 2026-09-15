#pragma once
#include <utility>
#include "WidgetProvider.h"
#include <objbase.h>
#include <limits>
#include <mutex>

namespace CodexBar::Widgets {
// Stable identity; the MSIX COM declaration must use the same value.
inline constexpr GUID WidgetProviderClsid{
    0x87b453c1, 0xe69f, 0x4cf4, {0xa5, 0x29, 0x9e, 0x68, 0x0e, 0xe6, 0x94, 0x83}};

struct WidgetClassFactory final : winrt::implements<WidgetClassFactory, IClassFactory> {
    explicit WidgetClassFactory(std::function<void(WidgetHostEvent)> sink) : sink_(std::move(sink)) {
        if (!sink_) throw winrt::hresult_invalid_argument();
    }
    HRESULT __stdcall CreateInstance(IUnknown* outer, REFIID iid, void** result) noexcept final {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        try {
            std::scoped_lock lock(mutex_);
            if (stopping_) return CO_E_SERVER_STOPPING;
            if (!instance_) instance_ = winrt::make<WidgetProvider>(sink_);
            return instance_.as(iid, result);
        } catch (...) { return winrt::to_hresult(); }
    }
    HRESULT __stdcall LockServer(BOOL acquire) noexcept final {
        try {
            std::scoped_lock lock(mutex_);
            if (acquire) {
                if (stopping_) return CO_E_SERVER_STOPPING;
                if (locks_ == (std::numeric_limits<ULONG>::max)()) return E_UNEXPECTED;
                ++locks_;
            } else {
                if (locks_ == 0) return E_UNEXPECTED;
                --locks_;
            }
            return S_OK;
        } catch (...) { return winrt::to_hresult(); }
    }
    // Prevent new activations before the host drains its dispatcher and withdraws published content.
    void BeginStop() {
        std::scoped_lock lock(mutex_);
        if (locks_ != 0) throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_BUSY));
        stopping_ = true;
    }
private:
    std::mutex mutex_;
    std::function<void(WidgetHostEvent)> sink_;
    winrt::Microsoft::Windows::Widgets::Providers::IWidgetProvider instance_{nullptr};
    ULONG locks_ = 0;
    bool stopping_ = false;
};

// Construct on the COM-initialized server thread only after caller security and the event consumer are ready.
// Revoke on that same thread before COM uninitialization. No registry keys are written by this class.
class WidgetClassRegistration final {
public:
    explicit WidgetClassRegistration(winrt::com_ptr<WidgetClassFactory> factory) : factory_(std::move(factory)) {
        if (!factory_) throw winrt::hresult_invalid_argument();
        DWORD cookie = 0;
        winrt::check_hresult(CoRegisterClassObject(WidgetProviderClsid,
            factory_.as<IClassFactory>().get(), CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &cookie));
        cookie_ = cookie;
        registered_ = true;
    }
    WidgetClassRegistration(WidgetClassRegistration const&) = delete;
    WidgetClassRegistration& operator=(WidgetClassRegistration const&) = delete;
    ~WidgetClassRegistration() noexcept {
        if (registered_) CoRevokeClassObject(cookie_);
    }
    void Revoke() {
        if (!registered_) return;
        factory_->BeginStop();
        winrt::check_hresult(CoRevokeClassObject(cookie_));
        registered_ = false;
    }
private:
    winrt::com_ptr<WidgetClassFactory> factory_;
    DWORD cookie_ = 0;
    bool registered_ = false;
};
}
