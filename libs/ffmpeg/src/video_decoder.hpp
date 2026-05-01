#pragma once

// Streaming video decoder for the waywallen video plugin.
//
// Produces NV12 frames (Y plane followed by interleaved UV plane,
// tightly packed) sized to a fixed target extent — that's what the
// `YuvToRgba` GPU pass consumes. NV12 is also what every common hw
// video decoder natively produces, which makes Iter 4's vulkan-decode
// path a drop-in: the AVVkFrame's images already match this layout, so
// `next_frame()` just changes its data-source.
//
// The decoder is sw-only as of Iter 2 — we ALWAYS swscale to NV12 at
// the target extent to keep callers oblivious to the source codec /
// pixel format. Iter 4 plugs in `hw_device_ctx = AVHWDeviceContext`
// (vulkan) and skips the swscale step when the frame is already
// vulkan-typed at our target size.

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace waywallen::ffvk {

struct Nv12Frame {
    // Layout: Y plane (`width * height` bytes) directly followed by
    // interleaved UV plane (`width * height / 2` bytes). Total size is
    // therefore `width * height * 3 / 2`.
    std::vector<uint8_t> data;
    uint32_t             width  { 0 };
    uint32_t             height { 0 };
    // Stream-time PTS in seconds; -1.0 if unavailable. Iter 2 ignores
    // this; Iter 3's presenter clock honors it.
    double               pts_seconds { -1.0 };
};

struct DecodeError {
    std::string message;
};

enum class FrameStatus {
    ok,
    eof,    // clean end of stream; only seen with loop=false
    error,
};

class VideoDecoder {
public:
    // `target_w`/`target_h` are the wallpaper extent. Both are rounded
    // up to even pixel boundaries (NV12 chroma is 4:2:0). Setting
    // `loop=true` causes EOF to seek back to the start automatically.
    static std::unique_ptr<VideoDecoder>
    open(const std::string& path,
         uint32_t            target_w,
         uint32_t            target_h,
         bool                loop,
         DecodeError*        err);

    ~VideoDecoder();
    VideoDecoder(const VideoDecoder&)            = delete;
    VideoDecoder& operator=(const VideoDecoder&) = delete;

    // Pull packets until exactly one frame is decoded, scaled to
    // (`target_w x target_h`) NV12, and emitted in `out`. `out.data` is
    // resized once to the NV12 size on first call and reused after.
    FrameStatus next_frame(Nv12Frame& out, DecodeError* err);

    uint32_t width() const  { return target_w_; }
    uint32_t height() const { return target_h_; }
    void     set_loop(bool loop) { loop_ = loop; }

    // Forward declaration; impl details (libav* handles) live in the
    // .cpp so this header doesn't drag FFmpeg includes into plugins.
    struct State;

private:
    VideoDecoder() = default;

    std::unique_ptr<State> st_;
    uint32_t target_w_ { 0 };
    uint32_t target_h_ { 0 };
    bool     loop_     { false };
};

} // namespace waywallen::ffvk
