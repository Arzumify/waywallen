#include "av_video.hpp"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>
}

#include <cstdio>
#include <cstring>

namespace ww_video {

namespace {

struct FmtCtxDeleter {
    void operator()(AVFormatContext* p) const noexcept {
        if (p) avformat_close_input(&p);
    }
};
struct CodecCtxDeleter {
    void operator()(AVCodecContext* p) const noexcept {
        if (p) avcodec_free_context(&p);
    }
};
struct FrameDeleter {
    void operator()(AVFrame* p) const noexcept {
        if (p) av_frame_free(&p);
    }
};
struct PacketDeleter {
    void operator()(AVPacket* p) const noexcept {
        if (p) av_packet_free(&p);
    }
};
struct SwsDeleter {
    void operator()(SwsContext* p) const noexcept {
        if (p) sws_freeContext(p);
    }
};

using FmtCtxPtr   = std::unique_ptr<AVFormatContext, FmtCtxDeleter>;
using CodecCtxPtr = std::unique_ptr<AVCodecContext, CodecCtxDeleter>;
using FramePtr    = std::unique_ptr<AVFrame, FrameDeleter>;
using PacketPtr   = std::unique_ptr<AVPacket, PacketDeleter>;
using SwsPtr      = std::unique_ptr<SwsContext, SwsDeleter>;

bool fail(DecodeError* err, std::string m) {
    if (err) err->message = std::move(m);
    return false;
}

std::string av_err_str(int rc) {
    char buf[AV_ERROR_MAX_STRING_SIZE] = {};
    av_strerror(rc, buf, sizeof(buf));
    return std::string(buf);
}

} // namespace

struct VideoDecoder::State {
    FmtCtxPtr   fmt;
    CodecCtxPtr cctx;
    PacketPtr   pkt;
    FramePtr    src_frame;
    SwsPtr      sws;
    AVPixelFormat sws_src_fmt { AV_PIX_FMT_NONE };
    int         sws_src_w     { 0 };
    int         sws_src_h     { 0 };
    int         video_idx     { -1 };
    AVRational  stream_tb     { 0, 1 };
    // Decoder is in flush-mode: we sent a NULL packet and are draining
    // remaining frames. Once `avcodec_receive_frame` returns AVERROR_EOF,
    // either loop (seek + flush_buffers) or report eof.
    bool        flushing      { false };
};

namespace {

bool ensure_sws(VideoDecoder::State& st, int src_w, int src_h, AVPixelFormat src_fmt,
                uint32_t target_w, uint32_t target_h) {
    if (st.sws && st.sws_src_w == src_w && st.sws_src_h == src_h
        && st.sws_src_fmt == src_fmt) {
        return true;
    }
    st.sws.reset(sws_getContext(src_w, src_h, src_fmt,
                                static_cast<int>(target_w),
                                static_cast<int>(target_h),
                                AV_PIX_FMT_RGBA,
                                SWS_BICUBIC, nullptr, nullptr, nullptr));
    if (!st.sws) return false;
    st.sws_src_w = src_w;
    st.sws_src_h = src_h;
    st.sws_src_fmt = src_fmt;
    return true;
}

bool seek_to_start(VideoDecoder::State& st) {
    int rc = av_seek_frame(st.fmt.get(), -1, 0, AVSEEK_FLAG_BACKWARD);
    if (rc < 0) return false;
    avcodec_flush_buffers(st.cctx.get());
    st.flushing = false;
    return true;
}

} // namespace

VideoDecoder::~VideoDecoder() = default;

std::unique_ptr<VideoDecoder>
VideoDecoder::open(const std::string& path,
                   uint32_t            target_w,
                   uint32_t            target_h,
                   bool                loop,
                   DecodeError*        err) {
    if (target_w == 0 || target_h == 0) {
        fail(err, "target dimensions must be non-zero");
        return nullptr;
    }
    auto self = std::unique_ptr<VideoDecoder>(new VideoDecoder());
    self->target_w_ = target_w;
    self->target_h_ = target_h;
    self->loop_     = loop;
    self->st_       = std::make_unique<State>();

    AVFormatContext* raw_fmt = nullptr;
    if (int rc = avformat_open_input(&raw_fmt, path.c_str(), nullptr, nullptr);
        rc < 0) {
        fail(err, "avformat_open_input: " + av_err_str(rc));
        return nullptr;
    }
    self->st_->fmt.reset(raw_fmt);

    if (int rc = avformat_find_stream_info(self->st_->fmt.get(), nullptr); rc < 0) {
        fail(err, "avformat_find_stream_info: " + av_err_str(rc));
        return nullptr;
    }

    int idx = av_find_best_stream(self->st_->fmt.get(),
                                  AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (idx < 0) {
        fail(err, "no video stream in file");
        return nullptr;
    }
    self->st_->video_idx = idx;
    AVStream*           st  = self->st_->fmt->streams[idx];
    AVCodecParameters*  par = st->codecpar;
    self->st_->stream_tb = st->time_base;

    const AVCodec* dec = avcodec_find_decoder(par->codec_id);
    if (!dec) {
        fail(err, std::string("no decoder for codec ") +
                  avcodec_get_name(par->codec_id));
        return nullptr;
    }
    self->st_->cctx.reset(avcodec_alloc_context3(dec));
    if (!self->st_->cctx) {
        fail(err, "avcodec_alloc_context3 failed");
        return nullptr;
    }
    if (int rc = avcodec_parameters_to_context(self->st_->cctx.get(), par); rc < 0) {
        fail(err, "avcodec_parameters_to_context: " + av_err_str(rc));
        return nullptr;
    }
    if (int rc = avcodec_open2(self->st_->cctx.get(), dec, nullptr); rc < 0) {
        fail(err, "avcodec_open2: " + av_err_str(rc));
        return nullptr;
    }

    self->st_->pkt.reset(av_packet_alloc());
    self->st_->src_frame.reset(av_frame_alloc());
    if (!self->st_->pkt || !self->st_->src_frame) {
        fail(err, "av_packet_alloc / av_frame_alloc failed");
        return nullptr;
    }

    return self;
}

FrameStatus VideoDecoder::next_frame(RgbaFrame& out, DecodeError* err) {
    State& st = *st_;

    // Resize the output buffer once per (target_w, target_h) lifetime.
    const uint32_t stride = target_w_ * 4u;
    if (out.width != target_w_ || out.height != target_h_
        || out.data.size() != static_cast<size_t>(stride) * target_h_) {
        out.width  = target_w_;
        out.height = target_h_;
        out.stride = stride;
        out.data.assign(static_cast<size_t>(stride) * target_h_, 0u);
    }

    // Pull packets until the decoder yields one frame. On EOF, either
    // seek to start and continue (loop) or return eof to the caller.
    while (true) {
        // Try to drain the decoder first — it may have a frame queued
        // from the last submission.
        int rc = avcodec_receive_frame(st.cctx.get(), st.src_frame.get());
        if (rc == 0) {
            const auto src_fmt = static_cast<AVPixelFormat>(st.src_frame->format);
            const int  src_w   = st.src_frame->width;
            const int  src_h   = st.src_frame->height;
            if (src_w <= 0 || src_h <= 0 || src_fmt == AV_PIX_FMT_NONE) {
                fail(err, "decoded frame has invalid dimensions/format");
                return FrameStatus::error;
            }
            if (!ensure_sws(st, src_w, src_h, src_fmt, target_w_, target_h_)) {
                fail(err, std::string("sws_getContext failed (src=") +
                          av_get_pix_fmt_name(src_fmt) + ")");
                return FrameStatus::error;
            }
            uint8_t* dst_planes[4]  = { out.data.data(), nullptr, nullptr, nullptr };
            int      dst_strides[4] = { static_cast<int>(stride), 0, 0, 0 };
            int scaled = sws_scale(st.sws.get(),
                                   st.src_frame->data, st.src_frame->linesize,
                                   0, src_h, dst_planes, dst_strides);
            if (scaled <= 0) {
                fail(err, "sws_scale produced no rows");
                return FrameStatus::error;
            }
            const int64_t pts = (st.src_frame->best_effort_timestamp != AV_NOPTS_VALUE)
                ? st.src_frame->best_effort_timestamp
                : st.src_frame->pts;
            out.pts_seconds = (pts == AV_NOPTS_VALUE)
                ? -1.0
                : static_cast<double>(pts) * av_q2d(st.stream_tb);
            av_frame_unref(st.src_frame.get());
            return FrameStatus::ok;
        }
        if (rc == AVERROR_EOF) {
            // Decoder fully drained.
            if (loop_) {
                if (!seek_to_start(st)) {
                    fail(err, "loop seek-to-zero failed");
                    return FrameStatus::error;
                }
                continue;
            }
            return FrameStatus::eof;
        }
        if (rc != AVERROR(EAGAIN)) {
            fail(err, "avcodec_receive_frame: " + av_err_str(rc));
            return FrameStatus::error;
        }

        // EAGAIN — feed another packet.
        if (st.flushing) {
            // We've already sent the NULL packet; just keep draining until
            // EOF arrives on the next receive call.
            continue;
        }

        rc = av_read_frame(st.fmt.get(), st.pkt.get());
        if (rc == AVERROR_EOF) {
            avcodec_send_packet(st.cctx.get(), nullptr);
            st.flushing = true;
            continue;
        }
        if (rc < 0) {
            fail(err, "av_read_frame: " + av_err_str(rc));
            return FrameStatus::error;
        }
        if (st.pkt->stream_index != st.video_idx) {
            av_packet_unref(st.pkt.get());
            continue;
        }
        rc = avcodec_send_packet(st.cctx.get(), st.pkt.get());
        av_packet_unref(st.pkt.get());
        if (rc < 0 && rc != AVERROR(EAGAIN)) {
            fail(err, "avcodec_send_packet: " + av_err_str(rc));
            return FrameStatus::error;
        }
        // Loop back to receive_frame.
    }
}

} // namespace ww_video
