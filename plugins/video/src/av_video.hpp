#pragma once

// Streaming sw video decoder for the Iter 0 video-plugin scaffold.
// Decodes one video stream from a file, scales each frame to a fixed
// (width, height) RGBA8 surface via libswscale, and exposes them one at
// a time through next_frame(). Looping at EOF is opt-in via the ctor.
//
// Iter 2 replaces this with a Vulkan hwcontext-backed decoder living in
// libs/ffmpeg; for now we keep the helper plugin-local to avoid pulling
// rstd into the plugins build tree just for this scaffold.

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace ww_video {

// Tightly-packed RGBA8, stride == width*4.
struct RgbaFrame {
    std::vector<uint8_t> data;
    uint32_t             width  { 0 };
    uint32_t             height { 0 };
    uint32_t             stride { 0 };
    // Stream-time PTS for the frame, in seconds. -1.0 if unknown.
    // Iter 0 doesn't honour this; Iter 3's presenter will.
    double               pts_seconds { -1.0 };
};

struct DecodeError {
    std::string message;
};

// Status returned by next_frame:
//   ok      — frame populated, keep going.
//   eof     — clean stream end; only seen when loop=false.
//   error   — fatal; *err is populated, decoder is no longer usable.
enum class FrameStatus {
    ok,
    eof,
    error,
};

class VideoDecoder {
public:
    // Open `path`, find the first video stream, ready a sw decoder and a
    // sws_getContext sized for `target_w x target_h` RGBA8 output. When
    // `loop` is true, EOF triggers a seek-to-zero + decoder flush so
    // next_frame() keeps returning frames forever.
    static std::unique_ptr<VideoDecoder>
    open(const std::string& path,
         uint32_t            target_w,
         uint32_t            target_h,
         bool                loop,
         DecodeError*        err);

    ~VideoDecoder();
    VideoDecoder(const VideoDecoder&)            = delete;
    VideoDecoder& operator=(const VideoDecoder&) = delete;

    // Pulls and decodes packets until exactly one frame is produced, then
    // scales it into `out`. `out.data` is reused across calls (sized once
    // to width*height*4 on first hit). `out.pts_seconds` is filled when
    // available.
    FrameStatus next_frame(RgbaFrame& out, DecodeError* err);

    uint32_t width() const  { return target_w_; }
    uint32_t height() const { return target_h_; }

    // Hot-reload knob: matches mpv's `loop-file` setting semantics enough
    // for Iter 0 ("no" disables looping; anything else enables).
    void set_loop(bool loop) { loop_ = loop; }

    // Opaque libav* state lives in the impl unit so the plugin TU doesn't
    // need to include FFmpeg headers. Forward-declared as public so impl
    // helpers in av_video.cpp can take it by reference.
    struct State;

private:
    VideoDecoder() = default;

    std::unique_ptr<State> st_;

    uint32_t target_w_ { 0 };
    uint32_t target_h_ { 0 };
    bool     loop_     { false };
};

} // namespace ww_video
