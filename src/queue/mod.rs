pub mod rotator;
pub mod state;

pub use rotator::{RotationConfig, RotationHandle};
pub use state::{Mode, QueueState};

/// Strip `library_root` from `resource` and return the path remainder.
/// Returns `None` when `resource` is outside `library_root`.
pub fn relative_under_root(library_root: &str, resource: &str) -> Option<String> {
    let root = library_root.trim_end_matches('/');
    let rest = resource.strip_prefix(root)?;
    Some(rest.trim_start_matches('/').to_owned())
}
