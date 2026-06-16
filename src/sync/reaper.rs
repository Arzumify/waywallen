use std::collections::HashMap;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use tokio::sync::mpsc;
use tokio::time::Instant;

use crate::sync::drm_syncobj::{DrmDevice, SyncobjHandle};

/// Maximum bucket age before force-flush when consumers lag.
/// Sized so a 60 fps producer has room for several frames.
const BUCKET_TIMEOUT: Duration = Duration::from_millis(500);

/// Per-handle wait deadline inside the bucket-flush ioctl.
/// Late consumers are force-signaled after this timeout.
const WAIT_TIMEOUT: Duration = Duration::from_millis(500);

/// Per-frame work item produced by `display::endpoint::forward_frame_ready`
/// and consumed by [`spawn_reaper`].
pub struct FrameRecord {
    pub release_point: u64,
    /// `None` means this frame had no enabled recipients.
    /// The reaper advances the producer release point directly.
    pub consumer_handle: Option<SyncobjHandle>,
    /// Total fan-out width for this `release_point`.
    /// `0` is only used with `consumer_handle = None`.
    pub expected_count: u32,
}

struct Bucket {
    handles: Vec<SyncobjHandle>,
    expected: u32,
    deadline: Instant,
}

pub fn spawn_reaper(
    drm: &'static DrmDevice,
    renderer_id: String,
    release_syncobj: Arc<StdMutex<Option<OwnedFd>>>,
    mut rx: mpsc::UnboundedReceiver<FrameRecord>,
) {
    tokio::spawn(async move {
        let mut producer_handle: Option<SyncobjHandle> = None;
        let mut buckets: HashMap<u64, Bucket> = HashMap::new();

        loop {
            // Earliest bucket deadline. None when there are no pending
            // buckets, in which case we just wait on the channel.
            let next_deadline = buckets.values().map(|b| b.deadline).min();

            tokio::select! {
                maybe_record = rx.recv() => {
                    let Some(record) = maybe_record else {
                        // Channel closed: every Sender clone is gone,
                        // so the renderer handle has been dropped.
                        if !buckets.is_empty() {
                            log::info!(
                                "reaper {renderer_id}: channel closed with {} pending bucket(s); dropping",
                                buckets.len(),
                            );
                        }
                        drop(buckets);
                        log::info!("reaper {renderer_id}: exiting");
                        return;
                    };
                    let Some(consumer_handle) = record.consumer_handle else {
                        // No real recipients (paused / no enabled outputs).
                        // Advance the producer's release timeline directly
                        advance_release_point(
                            drm, &renderer_id, &release_syncobj, &mut producer_handle,
                            record.release_point,
                        ).await;
                        continue;
                    };
                    let entry = buckets.entry(record.release_point).or_insert_with(|| {
                        Bucket {
                            handles: Vec::new(),
                            expected: record.expected_count,
                            deadline: Instant::now() + BUCKET_TIMEOUT,
                        }
                    });
                    // Defensive: if a later record reports a different
                    // expected_count, use the wider fan-out.
                    entry.expected = entry.expected.max(record.expected_count);
                    entry.handles.push(consumer_handle);
                    if entry.handles.len() as u32 >= entry.expected {
                        let bucket = buckets.remove(&record.release_point).unwrap();
                        flush_bucket(drm, &renderer_id, &release_syncobj, &mut producer_handle, record.release_point, bucket).await;
                    }
                }
                _ = sleep_until_or_pending(next_deadline) => {
                    // Snapshot expired keys first so the map can be
                    // mutated during flushing.
                    let now = Instant::now();
                    let expired: Vec<u64> = buckets
                        .iter()
                        .filter(|(_, b)| b.deadline <= now)
                        .map(|(p, _)| *p)
                        .collect();
                    for point in expired {
                        let bucket = buckets.remove(&point).unwrap();
                        log::warn!(
                            "reaper {renderer_id}: bucket point {point} timed out \
                             with {}/{} consumer signals — force-flushing",
                            bucket.handles.len(),
                            bucket.expected,
                        );
                        flush_bucket(drm, &renderer_id, &release_syncobj, &mut producer_handle, point, bucket).await;
                    }
                }
            }
        }
    });
}

/// Sleep until `deadline`. If `deadline` is `None`, never resolve —
/// the surrounding `tokio::select!` falls through to the recv arm.
async fn sleep_until_or_pending(deadline: Option<Instant>) {
    match deadline {
        Some(d) => tokio::time::sleep_until(d).await,
        None => std::future::pending::<()>().await,
    }
}

/// Duplicate the producer release_syncobj fd out of the shared slot.
/// The returned fd is owned by the caller.
fn dup_release_syncobj_fd(slot: &StdMutex<Option<OwnedFd>>) -> Option<OwnedFd> {
    let guard = slot.lock().ok()?;
    let fd = guard.as_ref()?;
    let dup_raw = nix::unistd::dup(fd.as_raw_fd()).ok()?;
    // SAFETY: nix::unistd::dup returned a fresh fd we now own.
    Some(unsafe { OwnedFd::from_raw_fd(dup_raw) })
}

/// Lazy-import the producer's release_syncobj into our handle cache.
/// Returns true if `producer_handle` is `Some` after this call.
fn ensure_producer_handle(
    drm: &'static DrmDevice,
    renderer_id: &str,
    release_syncobj: &StdMutex<Option<OwnedFd>>,
    producer_handle: &mut Option<SyncobjHandle>,
    release_point: u64,
) -> bool {
    if producer_handle.is_some() {
        return true;
    }
    let Some(fd) = dup_release_syncobj_fd(release_syncobj) else {
        log::warn!(
            "reaper {renderer_id}: dropping point {release_point} — \
             producer hasn't sent ReleaseSyncobj yet"
        );
        return false;
    };
    match drm.fd_to_handle(&fd) {
        Ok(h) => {
            *producer_handle = Some(h);
            log::info!("reaper {renderer_id}: imported release_syncobj");
            true
        }
        Err(e) => {
            log::warn!("reaper {renderer_id}: DRM_IOCTL_SYNCOBJ_FD_TO_HANDLE failed: {e}");
            false
        }
    }
}

/// Used when a frame has zero recipients.
/// Signals a placeholder fence and transfers it to the producer timeline.
async fn advance_release_point(
    drm: &'static DrmDevice,
    renderer_id: &str,
    release_syncobj: &StdMutex<Option<OwnedFd>>,
    producer_handle: &mut Option<SyncobjHandle>,
    release_point: u64,
) {
    if !ensure_producer_handle(
        drm,
        renderer_id,
        release_syncobj,
        producer_handle,
        release_point,
    ) {
        return;
    }
    let producer = producer_handle.as_ref().expect("set above");

    let placeholder = match drm.create_binary_syncobj() {
        Ok(h) => h,
        Err(e) => {
            log::warn!(
                "reaper {renderer_id}: advance point {release_point}: create_binary_syncobj: {e}"
            );
            return;
        }
    };
    if let Err(e) = drm.signal(&placeholder) {
        log::warn!("reaper {renderer_id}: advance point {release_point}: SIGNAL: {e}");
        return;
    }
    if let Err(e) = drm.transfer(&placeholder, 0, producer, release_point) {
        log::warn!("reaper {renderer_id}: advance point {release_point}: TRANSFER: {e}");
    }
    // `placeholder` drops here → DESTROY ioctl. Producer timeline
    // already holds the signaled fence via TRANSFER, so this is safe.
}

/// Wait for every handle in `bucket`, force-signaling stragglers.
/// Then transfer the merged fence to the producer timeline.
async fn flush_bucket(
    drm: &'static DrmDevice,
    renderer_id: &str,
    release_syncobj: &StdMutex<Option<OwnedFd>>,
    producer_handle: &mut Option<SyncobjHandle>,
    release_point: u64,
    mut bucket: Bucket,
) {
    if bucket.handles.is_empty() {
        return;
    }

    if !ensure_producer_handle(
        drm,
        renderer_id,
        release_syncobj,
        producer_handle,
        release_point,
    ) {
        return;
    }
    let producer = producer_handle.as_ref().expect("set above");

    // 1+2. Wait for all consumer signals; force-signal stragglers.
    // wait_handles_signaled wants ABSOLUTE CLOCK_MONOTONIC.
    let timeout_nsec = {
        let mut ts: libc::timespec = unsafe { std::mem::zeroed() };
        let ok = unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut ts) } == 0;
        if !ok {
            i64::MAX
        } else {
            (ts.tv_sec as i64)
                .checked_mul(1_000_000_000)
                .and_then(|s| s.checked_add(ts.tv_nsec as i64))
                .and_then(|now| now.checked_add(WAIT_TIMEOUT.as_nanos() as i64))
                .unwrap_or(i64::MAX)
        }
    };

    // Move ownership across spawn_blocking boundary to keep handles
    // alive on the blocking thread; ioctl needs &SyncobjHandle so we
    let handles_for_blocking = std::mem::take(&mut bucket.handles);
    let join = tokio::task::spawn_blocking(move || {
        let refs: Vec<&SyncobjHandle> = handles_for_blocking.iter().collect();
        let res = drm.wait_handles_signaled(&refs, timeout_nsec);
        (res, handles_for_blocking)
    })
    .await;
    let (wait_result, handles) = match join {
        Ok(pair) => pair,
        Err(e) => {
            log::warn!("reaper {renderer_id}: wait task panicked: {e}");
            return;
        }
    };

    if let Err(e) = wait_result {
        log::warn!(
            "reaper {renderer_id}: wait point {release_point} timed out / errored ({e}); \
             force-signaling stragglers"
        );
        for h in &handles {
            // SIGNAL is a CPU-side mark; cheap and cannot fail in any
            // meaningful way for our handles.
            if let Err(se) = drm.signal(h) {
                log::warn!("reaper {renderer_id}: force SIGNAL failed: {se}");
            }
        }
    }

    // 3. TRANSFER. Single-consumer fast path: skip the merge dance.
    let n = handles.len();
    if n == 1 {
        if let Err(e) = drm.transfer(&handles[0], 0, producer, release_point) {
            log::warn!("reaper {renderer_id}: TRANSFER to point {release_point} failed: {e}");
        } else {
            log::trace!("reaper {renderer_id}: flushed point {release_point} (1 consumer)");
        }
        drop(handles);
        return;
    }

    // Fan-out merge:
    //   3a. EXPORT_SYNC_FILE on each consumer handle.
    let mut sync_files: Vec<std::os::fd::OwnedFd> = Vec::with_capacity(n);
    let mut export_failed = false;
    for h in &handles {
        match drm.export_sync_file(h) {
            Ok(fd) => sync_files.push(fd),
            Err(e) => {
                log::warn!(
                    "reaper {renderer_id}: EXPORT_SYNC_FILE on point {release_point} failed: {e}"
                );
                export_failed = true;
                break;
            }
        }
    }
    if export_failed || sync_files.is_empty() {
        // Fall back to a single TRANSFER so the producer's wait at
        // this release_point still completes; we lose accurate fan-out
        if let Err(e) = drm.transfer(&handles[0], 0, producer, release_point) {
            log::warn!(
                "reaper {renderer_id}: fallback TRANSFER to point {release_point} failed: {e}"
            );
        }
        drop(handles);
        return;
    }

    let merged = sync_files
        .into_iter()
        .reduce(|a, b| match crate::sync::merge_sync_files(&a, &b) {
            Ok(m) => m,
            Err(e) => {
                log::warn!(
                    "reaper {renderer_id}: SYNC_IOC_MERGE on point {release_point} failed: {e}; \
                     dropping later fences"
                );
                a
            }
        })
        .expect("non-empty after empty-check above");

    let temp_handle = match drm.create_binary_syncobj() {
        Ok(h) => h,
        Err(e) => {
            log::warn!(
                "reaper {renderer_id}: create temp syncobj for point {release_point} failed: {e}"
            );
            drop(handles);
            return;
        }
    };
    if let Err(e) = drm.import_sync_file(&temp_handle, &merged) {
        log::warn!("reaper {renderer_id}: IMPORT_SYNC_FILE for point {release_point} failed: {e}");
        drop(handles);
        return;
    }
    if let Err(e) = drm.transfer(&temp_handle, 0, producer, release_point) {
        log::warn!("reaper {renderer_id}: TRANSFER (merged) to point {release_point} failed: {e}");
        return;
    }
    log::trace!("reaper {renderer_id}: flushed point {release_point} ({n} consumer fences merged)");
    // Local handles drop here for kernel cleanup. The producer timeline
    // already holds the merged fence after TRANSFER.
    drop(handles);
}
