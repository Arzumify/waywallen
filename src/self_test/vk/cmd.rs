use anyhow::{anyhow, Result};
use ash::vk;

use super::device::VkDevice;

pub struct OneShotCmd {
    pub pool: vk::CommandPool,
    pub buf: vk::CommandBuffer,
}

pub fn create(vkd: &VkDevice) -> Result<OneShotCmd> {
    let pool = unsafe {
        vkd.device.create_command_pool(
            &vk::CommandPoolCreateInfo::default()
                .queue_family_index(vkd.queue_family)
                .flags(vk::CommandPoolCreateFlags::RESET_COMMAND_BUFFER),
            None,
        )
    }
    .map_err(|e| anyhow!("create_command_pool: {e}"))?;
    let buf = unsafe {
        vkd.device.allocate_command_buffers(
            &vk::CommandBufferAllocateInfo::default()
                .command_pool(pool)
                .level(vk::CommandBufferLevel::PRIMARY)
                .command_buffer_count(1),
        )
    }
    .map_err(|e| anyhow!("allocate_command_buffers: {e}"))?[0];
    Ok(OneShotCmd { pool, buf })
}

pub fn destroy(vkd: &VkDevice, c: OneShotCmd) {
    unsafe {
        vkd.device.destroy_command_pool(c.pool, None);
    }
}

pub fn transition_to_general(vkd: &VkDevice, cmd: &OneShotCmd, imgs: &[vk::Image]) -> Result<()> {
    unsafe {
        vkd.device
            .reset_command_buffer(cmd.buf, vk::CommandBufferResetFlags::empty())?;
        vkd.device.begin_command_buffer(
            cmd.buf,
            &vk::CommandBufferBeginInfo::default()
                .flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT),
        )?;
        let barriers: Vec<vk::ImageMemoryBarrier> = imgs
            .iter()
            .map(|&image| {
                vk::ImageMemoryBarrier::default()
                    .old_layout(vk::ImageLayout::UNDEFINED)
                    .new_layout(vk::ImageLayout::GENERAL)
                    .image(image)
                    .subresource_range(
                        vk::ImageSubresourceRange::default()
                            .aspect_mask(vk::ImageAspectFlags::COLOR)
                            .level_count(1)
                            .layer_count(1),
                    )
            })
            .collect();
        vkd.device.cmd_pipeline_barrier(
            cmd.buf,
            vk::PipelineStageFlags::TOP_OF_PIPE,
            vk::PipelineStageFlags::TRANSFER,
            vk::DependencyFlags::empty(),
            &[],
            &[],
            &barriers,
        );
        vkd.device.end_command_buffer(cmd.buf)?;
        vkd.device.queue_submit(
            vkd.queue,
            &[vk::SubmitInfo::default().command_buffers(&[cmd.buf])],
            vk::Fence::null(),
        )?;
        vkd.device.queue_wait_idle(vkd.queue)?;
    }
    Ok(())
}
