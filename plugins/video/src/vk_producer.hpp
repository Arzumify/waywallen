#pragma once

// Iter 0 video plugin's Vulkan helper. Mirrors plugins/image/src/vk_producer.hpp
// almost line-for-line, with one functional difference: a per-submit
// VkFence makes upload_into safe to call repeatedly (every video frame),
// whereas the image-plugin version assumes one upload per directive.
//
// Iter 1 hoists this code into libs/ffmpeg/vk_device and both plugins
// share it; for Iter 0 we duplicate to keep the smoke-test self-contained.

#include <cstdint>
#include <memory>
#include <string>

#include <vulkan/vulkan.h>

namespace ww_video {

class VkProducer {
public:
    ~VkProducer();
    VkProducer(const VkProducer&)            = delete;
    VkProducer& operator=(const VkProducer&) = delete;

    static std::unique_ptr<VkProducer>
    create(uint32_t width, uint32_t height, std::string* err);

    VkInstance       instance() const         { return instance_; }
    VkPhysicalDevice physical_device() const  { return phys_; }
    VkDevice         device() const           { return device_; }
    VkQueue          queue() const            { return queue_; }
    uint32_t         queue_family_index() const { return queue_family_; }
    uint32_t         drm_render_major() const { return drm_render_major_; }
    uint32_t         drm_render_minor() const { return drm_render_minor_; }
    const uint8_t*   device_uuid() const      { return have_uuid_ ? device_uuid_ : nullptr; }
    const uint8_t*   driver_uuid() const      { return have_uuid_ ? driver_uuid_ : nullptr; }
    int              drm_render_fd() const    { return drm_render_fd_; }
    uint32_t         width() const  { return width_; }
    uint32_t         height() const { return height_; }

    // Copy `data` (tightly packed RGBA8, `size` bytes) into `target`
    // VkImage and return an exported sync_fd that signals when the GPU
    // is done writing. Bridge takes ownership of the sync_fd. -1 on error.
    int upload_into(VkImage target, uint32_t target_width, uint32_t target_height,
                    const uint8_t* data, size_t size, std::string* err);

private:
    VkProducer() = default;

    VkInstance       instance_ { VK_NULL_HANDLE };
    VkPhysicalDevice phys_ { VK_NULL_HANDLE };
    VkDevice         device_ { VK_NULL_HANDLE };
    uint32_t         queue_family_ { 0 };
    VkQueue          queue_ { VK_NULL_HANDLE };

    VkCommandPool    cmd_pool_ { VK_NULL_HANDLE };
    VkCommandBuffer  cmd_ { VK_NULL_HANDLE };
    VkSemaphore      signal_sem_ { VK_NULL_HANDLE };
    /* Per-submit fence — caller waits on it before reusing cmd_ /
     * staging_mem_. `fence_pending_` tracks whether the fence has been
     * submitted at least once (skip the wait on the first call). */
    VkFence          done_fence_ { VK_NULL_HANDLE };
    bool             fence_pending_ { false };

    VkBuffer         staging_buf_ { VK_NULL_HANDLE };
    VkDeviceMemory   staging_mem_ { VK_NULL_HANDLE };
    void*            staging_map_ { nullptr };
    VkDeviceSize     staging_size_ { 0 };

    uint32_t         width_ { 0 };
    uint32_t         height_ { 0 };
    uint32_t         drm_render_major_ { 0 };
    uint32_t         drm_render_minor_ { 0 };
    int              drm_render_fd_ { -1 };

    bool             have_uuid_ { false };
    uint8_t          device_uuid_[16] { 0 };
    uint8_t          driver_uuid_[16] { 0 };

    PFN_vkGetSemaphoreFdKHR vkGetSemaphoreFdKHR_ { nullptr };
};

} // namespace ww_video
