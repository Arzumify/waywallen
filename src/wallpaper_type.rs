use serde::{Deserialize, Serialize};

pub type WallpaperType = String;

/// A single wallpaper entry. Source plugins fill the scan-time subset
/// (name/wp_type/resource/preview/library_root/external_id/...); the
/// daemon reconstructs the full entry from the DB on every read
/// (`repo::load_entries` / `repo::get_entry`) — the DB is the source of
/// truth, not an in-memory cache.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WallpaperEntry {
    /// Canonical identity: the DB `item.id` for this entry's
    /// `(library_id, path)`. Filled by the daemon after the scan is
    /// synced to the DB (zero until then). Plugins do not assign it —
    /// they only carry the optional `external_id` (e.g. workshop id).
    #[serde(default)]
    pub item_id: i64,
    /// Human-readable display name.
    pub name: String,
    /// The wallpaper type string (e.g. "scene", "image", "video").
    pub wp_type: WallpaperType,
    /// Filesystem path or URI to the wallpaper resource.
    pub resource: String,
    /// Optional path to a preview/thumbnail image.
    pub preview: Option<String>,
    /// Free-form description (e.g. Wallpaper Engine `project.description`).
    #[serde(default)]
    pub description: Option<String>,
    /// Source-assigned tags. Case-insensitive deduped at the DB layer.
    #[serde(default)]
    pub tags: Vec<String>,
    /// Stable external identifier (e.g. Wallpaper Engine `workshopid`).
    #[serde(default)]
    pub external_id: Option<String>,
    /// File size in bytes.
    #[serde(default)]
    pub size: Option<i64>,
    /// Primary video stream width in pixels.
    #[serde(default)]
    pub width: Option<u32>,
    /// Primary video stream height in pixels.
    #[serde(default)]
    pub height: Option<u32>,
    /// Source-provided content rating (e.g. "Everyone", "Questionable",
    /// "Mature"). Free-form string; the daemon doesn't interpret it.
    #[serde(default)]
    pub content_rating: Option<String>,
    /// File mtime in ms since epoch (DB `item.modified_at`). Daemon-only
    /// (filled on read for sorting); plugins do not set it.
    #[serde(default)]
    pub modified_at: Option<i64>,
    /// Name of the source plugin that produced this entry. Written by
    /// `SourceManager::scan_plugin` — Lua plugins do not set it
    /// themselves. Defaults to empty so deserializing older snapshots
    /// stays backwards compatible.
    #[serde(default)]
    pub plugin_name: String,
    /// Absolute path of the directory the plugin was scanning when it
    /// produced this entry. Serves two purposes:
    ///   - `library.path` = this value (absolute folder).
    ///   - `item.relative_path` = `resource` minus this prefix.
    /// Empty means "unrooted" — the sync layer drops such entries
    /// because it cannot address them relatively.
    #[serde(default)]
    pub library_root: String,
}
