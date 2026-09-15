#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>
#include <winrt/base.h>

namespace CodexBar::Widgets {
inline constexpr std::size_t MaximumWidgetFramePayload = 256 * 1024;
inline std::string EncodeWidgetFrame(std::string_view payload) {
    if (payload.empty() || payload.size() > MaximumWidgetFramePayload) throw winrt::hresult_invalid_argument();
    std::string result = "CBW1";
    auto length = static_cast<std::uint32_t>(payload.size());
    for (unsigned shift = 0; shift < 32; shift += 8) result.push_back(static_cast<char>((length >> shift) & 0xff));
    result.append(payload);
    return result;
}
class WidgetFrameDecoder final {
public:
    std::vector<std::string> Consume(std::string_view chunk) {
        if (closed_) throw winrt::hresult_illegal_method_call();
        try {
            if (chunk.size() > MaximumWidgetFramePayload + 8) throw winrt::hresult_invalid_argument();
            std::vector<std::string> frames;
            for (auto byte : chunk) {
                if (expected_ == 0) {
                    header_[headerSize_++] = static_cast<unsigned char>(byte);
                    if (headerSize_ == 8) {
                        if (header_[0] != 'C' || header_[1] != 'B' || header_[2] != 'W' || header_[3] != '1') {
                            throw winrt::hresult_invalid_argument();
                        }
                        std::uint32_t length = 0;
                        for (unsigned i = 0; i < 4; ++i) length |= std::uint32_t(header_[4 + i]) << (8 * i);
                        if (length == 0 || length > MaximumWidgetFramePayload) throw winrt::hresult_invalid_argument();
                        expected_ = length;
                        payload_.reserve(length);
                        headerSize_ = 0;
                    }
                } else {
                    payload_.push_back(byte);
                    if (payload_.size() == expected_) {
                        if (frames.size() >= 128) throw winrt::hresult_invalid_argument();
                        frames.push_back(std::move(payload_));
                        payload_.clear(); expected_ = 0;
                    }
                }
            }
            return frames;
        } catch (...) {
            closed_ = true; payload_.clear(); expected_ = 0; headerSize_ = 0;
            throw;
        }
    }
    void Finish() {
        if (closed_) throw winrt::hresult_illegal_method_call();
        closed_ = true;
        bool partial = headerSize_ != 0 || expected_ != 0;
        payload_.clear(); expected_ = 0; headerSize_ = 0;
        if (partial) throw winrt::hresult_invalid_argument();
    }
private:
    std::array<unsigned char, 8> header_{};
    std::size_t headerSize_ = 0;
    std::size_t expected_ = 0;
    std::string payload_;
    bool closed_ = false;
};
}
