use std::os::fd::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use ash::vk;

use super::super::proto::{recv_msg, send_msg, TestMsg, PROTOCOL_VERSION};
use super::super::report::Fanout;
use super::super::spawn::{bind_listener, make_socket_path, spawn, ChildSpec, SocketCleanup};
use super::super::vk::cmd;
use super::super::vk::device::VkDevice;
use super::super::vk::image::{create_with_modifiers, export_dmabuf};
use super::super::vk::sync::{create_timeline_exportable, export_opaque_fd, wait_timeline};

const FORMAT: vk::Format = vk::Format::R8G8B8A8_UNORM;
const FOURCC_AB24: u32 = 0x34324241;
const WIDTH: u32 = 256;
const HEIGHT: u32 = 256;
const FRAMES: u32 = 60;
const PER_FRAME_TIMEOUT_NS: u64 = 1_000_000_000;
const NUM_DISPLAYS: u32 = 2;

struct DisplayConn {
    pub stream: UnixStream,
    pub _child: std::process::Child,
    pub _cleanup: SocketCleanup,
    pub display_id: u32,
}

pub fn run_orchestrator(
    instance: &ash::Instance,
    phys: vk::PhysicalDevice,
    vkd: &VkDevice,
    dev_meta: &super::super::vk::instance::DeviceMeta,
) -> Result<Fanout> {
    log::info!("fanout: spawning {NUM_DISPLAYS} display children");
    let mut conns: Vec<DisplayConn> = Vec::with_capacity(NUM_DISPLAYS as usize);
    for id in 0..NUM_DISPLAYS {
        let conn = spawn_and_handshake(dev_meta, id)?;
        conns.push(conn);
    }

    let modifier = pick_modifier(vkd, instance, phys)?;
    log::info!(
        "fanout: using modifier {:#x} ({})",
        modifier,
        super::super::vk::modifier::format_modifier(modifier)
    );

    let img0 = create_with_modifiers(
        vkd,
        WIDTH,
        HEIGHT,
        FORMAT,
        vk::ImageUsageFlags::COLOR_ATTACHMENT | vk::ImageUsageFlags::TRANSFER_SRC,
        &[modifier],
        false,
    )
    .context("alloc slot 0")?;
    let img1 = create_with_modifiers(
        vkd,
        WIDTH,
        HEIGHT,
        FORMAT,
        vk::ImageUsageFlags::COLOR_ATTACHMENT | vk::ImageUsageFlags::TRANSFER_SRC,
        &[modifier],
        false,
    )
    .context("alloc slot 1")?;

    let cmdbuf = cmd::create(vkd)?;
    cmd::transition_to_general(vkd, &cmdbuf, &[img0.image, img1.image])?;

    // Single shared acquire timeline (all displays wait the same value),
    // per-display release so the orchestrator can detect a single
    // straggler (refcount-style bug) instead of waiting for all.
    let acquire = create_timeline_exportable(vkd)?;
    let mut releases: Vec<super::super::vk::sync::TimelineSemaphore> = Vec::with_capacity(conns.len());
    for _ in 0..conns.len() {
        releases.push(create_timeline_exportable(vkd)?);
    }

    for (i, conn) in conns.iter().enumerate() {
        let fd0 = export_dmabuf(vkd, &img0)?;
        let fd1 = export_dmabuf(vkd, &img1)?;
        send_msg(
            &conn.stream,
            &TestMsg::BindPair {
                fourcc: FOURCC_AB24,
                modifier: img0.modifier,
                width: WIDTH,
                height: HEIGHT,
                slot_strides: [
                    u32::try_from(img0.plane0_stride).unwrap_or(u32::MAX),
                    u32::try_from(img1.plane0_stride).unwrap_or(u32::MAX),
                ],
                slot_offsets: [
                    u32::try_from(img0.plane0_offset).unwrap_or(0),
                    u32::try_from(img1.plane0_offset).unwrap_or(0),
                ],
                slot_sizes: [img0.plane0_size, img1.plane0_size],
                color_seed: 0,
                frame_count: FRAMES,
            },
            &[fd0.as_raw_fd(), fd1.as_raw_fd()],
        )
        .map_err(|e| anyhow!("send BindPair to display {}: {e}", conn.display_id))?;
        drop((fd0, fd1));

        let acq_fd = export_opaque_fd(vkd, &acquire)?;
        let rel_fd = export_opaque_fd(vkd, &releases[i])?;
        send_msg(
            &conn.stream,
            &TestMsg::BindTimelines,
            &[acq_fd.as_raw_fd(), rel_fd.as_raw_fd()],
        )
        .map_err(|e| anyhow!("send BindTimelines to display {}: {e}", conn.display_id))?;
        drop((acq_fd, rel_fd));
    }

    let mut report = Fanout {
        frames: FRAMES,
        ok: 0,
        display_kill_at: None,
        kill_recovered_ms: None,
        refcount_leaks: 0,
    };

    let imgs = [img0.image, img1.image];
    for n in 0..FRAMES {
        let slot = (n & 1) as usize;
        let acq_val = (n + 1) as u64;
        let rel_val = (n + 1) as u64;
        let (color_f, _) = super::render_loop::color_for(n);

        unsafe {
            vkd.device
                .reset_command_buffer(cmdbuf.buf, vk::CommandBufferResetFlags::empty())?;
            vkd.device.begin_command_buffer(
                cmdbuf.buf,
                &vk::CommandBufferBeginInfo::default()
                    .flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT),
            )?;
            vkd.device.cmd_clear_color_image(
                cmdbuf.buf,
                imgs[slot],
                vk::ImageLayout::GENERAL,
                &vk::ClearColorValue { float32: color_f },
                &[vk::ImageSubresourceRange::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .level_count(1)
                    .layer_count(1)],
            );
            vkd.device.end_command_buffer(cmdbuf.buf)?;
            let signal_sems = [acquire.sem];
            let signal_vals = [acq_val];
            let mut tl = vk::TimelineSemaphoreSubmitInfo::default()
                .signal_semaphore_values(&signal_vals);
            let bufs = [cmdbuf.buf];
            vkd.device.queue_submit(
                vkd.queue,
                &[vk::SubmitInfo::default()
                    .command_buffers(&bufs)
                    .signal_semaphores(&signal_sems)
                    .push_next(&mut tl)],
                vk::Fence::null(),
            )?;
        }

        for conn in &conns {
            send_msg(
                &conn.stream,
                &TestMsg::Frame {
                    n,
                    slot: slot as u32,
                    acquire_value: acq_val,
                    release_value: rel_val,
                },
                &[],
            )
            .map_err(|e| anyhow!("send Frame to display {}: {e}", conn.display_id))?;
        }

        let mut frame_ok = true;
        for (i, rel) in releases.iter().enumerate() {
            if let Err(e) = wait_timeline(vkd, rel, rel_val, PER_FRAME_TIMEOUT_NS) {
                log::warn!(
                    "fanout: release timeout display {} frame {}: {e}",
                    conns[i].display_id,
                    n,
                );
                frame_ok = false;
            }
        }
        if !frame_ok {
            break;
        }

        let mut got_reports = vec![false; conns.len()];
        for _ in 0..conns.len() {
            let mut got_one = false;
            for (i, conn) in conns.iter().enumerate() {
                if got_reports[i] {
                    continue;
                }
                match recv_msg(&conn.stream) {
                    Ok((TestMsg::ColorReport { ok, .. }, _)) => {
                        got_reports[i] = true;
                        got_one = true;
                        if !ok {
                            log::warn!(
                                "fanout: display {} frame {}: color mismatch",
                                conn.display_id, n
                            );
                            frame_ok = false;
                        }
                        break;
                    }
                    Ok(other) => anyhow::bail!(
                        "expected ColorReport from {}, got {other:?}",
                        conn.display_id
                    ),
                    Err(e) => anyhow::bail!(
                        "recv ColorReport from {} failed: {e}",
                        conn.display_id
                    ),
                }
            }
            if !got_one {
                break;
            }
        }
        if frame_ok {
            report.ok += 1;
        }
    }

    for conn in &conns {
        let _ = send_msg(&conn.stream, &TestMsg::LoopDone, &[]);
    }
    drop(conns);

    unsafe {
        let _ = vkd.device.device_wait_idle();
        vkd.device.destroy_semaphore(acquire.sem, None);
        for r in &releases {
            vkd.device.destroy_semaphore(r.sem, None);
        }
        vkd.device.free_memory(img0.memory, None);
        vkd.device.free_memory(img1.memory, None);
        vkd.device.destroy_image(img0.image, None);
        vkd.device.destroy_image(img1.image, None);
    }
    cmd::destroy(vkd, cmdbuf);

    Ok(report)
}

fn pick_modifier(
    vkd: &VkDevice,
    instance: &ash::Instance,
    phys: vk::PhysicalDevice,
) -> Result<u64> {
    let entries = super::super::vk::modifier::query_supported(instance, phys, FORMAT)?;
    let _ = vkd;
    if let Some(e) = entries
        .iter()
        .find(|e| e.modifier != 0 && super::super::vk::modifier::supports_clear_and_export(e))
    {
        return Ok(e.modifier);
    }
    Ok(0)
}

fn spawn_and_handshake(
    dev_meta: &super::super::vk::instance::DeviceMeta,
    display_id: u32,
) -> Result<DisplayConn> {
    let socket = make_socket_path(&format!("display{display_id}"))?;
    let (listener, cleanup) = bind_listener(&socket)?;
    let child = spawn(&ChildSpec {
        role: "display",
        socket: socket.clone(),
        vk_uuid: dev_meta.uuid,
        slot: display_id,
    })?;
    let stream = accept_with_timeout(&listener, Duration::from_secs(5))?;
    handshake_orch_side(&stream, dev_meta)?;
    Ok(DisplayConn {
        stream,
        _child: child,
        _cleanup: cleanup,
        display_id,
    })
}

fn accept_with_timeout(l: &UnixListener, timeout: Duration) -> Result<UnixStream> {
    l.set_nonblocking(true)?;
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match l.accept() {
            Ok((s, _)) => {
                s.set_nonblocking(false)?;
                return Ok(s);
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                if std::time::Instant::now() >= deadline {
                    anyhow::bail!("accept timeout after {:?}", timeout);
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(e) => return Err(e.into()),
        }
    }
}

fn handshake_orch_side(
    stream: &UnixStream,
    dev_meta: &super::super::vk::instance::DeviceMeta,
) -> Result<()> {
    let (msg, _) = recv_msg(stream).map_err(|e| anyhow!("handshake recv: {e}"))?;
    let TestMsg::Hello {
        version,
        device_uuid_hex,
        ..
    } = msg
    else {
        anyhow::bail!("expected Hello, got {msg:?}");
    };
    if version != PROTOCOL_VERSION {
        anyhow::bail!("version mismatch");
    }
    let want = super::super::format_uuid_hex(&dev_meta.uuid);
    if device_uuid_hex != want {
        anyhow::bail!("uuid mismatch");
    }
    send_msg(
        stream,
        &TestMsg::Welcome {
            ok: true,
            message: "fanout".into(),
        },
        &[],
    )
    .map_err(|e| anyhow!("send Welcome: {e}"))?;
    Ok(())
}

pub fn run_display_child(args: super::super::TestArgs) -> Result<()> {
    let socket = args.socket.clone().ok_or_else(|| anyhow!("--socket required"))?;
    let want_uuid = args
        .vk_uuid
        .ok_or_else(|| anyhow!("--vk-uuid required"))?;
    let display_id = args.slot;

    let vk = super::super::vk::instance::create_instance().context("vkCreateInstance")?;
    let devices = super::super::vk::instance::enumerate(&vk).context("enumerate")?;
    let dev_meta = super::super::vk::instance::find_by_uuid(&devices, &want_uuid)
        .ok_or_else(|| anyhow!("display child: vk uuid not found"))?
        .clone();
    let vkd = super::super::vk::device::create(&vk.instance, &dev_meta)?;

    let stream = connect_with_retry(&socket, Duration::from_secs(5))?;
    log::info!("display#{display_id}: connected, device={}", dev_meta.name);

    send_msg(
        &stream,
        &TestMsg::Hello {
            version: PROTOCOL_VERSION,
            device_uuid_hex: super::super::format_uuid_hex(&dev_meta.uuid),
            driver_uuid_hex: super::super::format_uuid_hex(&dev_meta.driver_uuid),
            device_name: dev_meta.name.clone(),
        },
        &[],
    )
    .map_err(|e| anyhow!("send Hello: {e}"))?;
    let (welcome, _) = recv_msg(&stream).map_err(|e| anyhow!("recv Welcome: {e}"))?;
    let TestMsg::Welcome { ok, message } = welcome else {
        anyhow::bail!("expected Welcome got {welcome:?}");
    };
    if !ok {
        anyhow::bail!("rejected: {message}");
    }

    super::render_loop::run_peer(&vkd, &stream).context("display")?;
    Ok(())
}

fn connect_with_retry(path: &std::path::Path, timeout: Duration) -> Result<UnixStream> {
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match UnixStream::connect(path) {
            Ok(s) => return Ok(s),
            Err(_) if std::time::Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(e) => return Err(anyhow!("connect {}: {e}", path.display())),
        }
    }
}
