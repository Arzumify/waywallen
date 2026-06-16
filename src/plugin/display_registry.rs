use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Manifest (TOML on disk)

#[derive(Debug, Clone, Deserialize)]
pub struct DisplayManifest {
    pub display: DisplayDef,
}

/// How the daemon handles the backend's lifecycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SpawnMode {
    /// Daemon starts the `bin` as a subprocess (e.g. wlr-layer-shell bin).
    Daemon,
    /// DE starts it on its own (e.g. Plasma kpackage loaded by plasmashell).
    External,
}

impl Default for SpawnMode {
    fn default() -> Self {
        SpawnMode::Daemon
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct DisplayDef {
    pub name: String,
    /// Executable path. Only meaningful when `spawn == Daemon`.
    #[serde(default)]
    pub bin: PathBuf,
    /// DE tokens (lower-case) this backend targets. `"*"` = any DE.
    /// Matched against the first token of `XDG_CURRENT_DESKTOP` (split on `:`).
    #[serde(default)]
    pub de: Vec<String>,
    #[serde(default = "default_priority")]
    pub priority: i32,
    /// Optional capability tokens this backend needs.
    /// `display::spawner` intersects them with probed Wayland globals.
    #[serde(default)]
    pub requires: Vec<String>,
    #[serde(default)]
    pub extra_args: Vec<String>,
    #[serde(default)]
    pub spawn: SpawnMode,
}

fn default_priority() -> i32 {
    100
}

// ---------------------------------------------------------------------------
// Registry

#[derive(Default)]
pub struct DisplayRegistry {
    /// Sorted descending by priority; ties broken by registration order.
    defs: Vec<DisplayDef>,
}

impl DisplayRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Scan a directory for `*.toml` display manifests and collect them.
    /// Non-parseable files are logged and skipped. Relative `bin` paths
    pub fn scan(dir: &Path) -> Result<Self> {
        let mut reg = Self::new();
        let pattern = dir.join("*.toml");
        let pattern_str = pattern
            .to_str()
            .context("manifest dir path not valid UTF-8")?;
        for entry in glob::glob(pattern_str).context("glob pattern")? {
            let path = match entry {
                Ok(p) => p,
                Err(e) => {
                    log::warn!("display manifest glob error: {e}");
                    continue;
                }
            };
            match std::fs::read_to_string(&path) {
                Ok(contents) => match toml::from_str::<DisplayManifest>(&contents) {
                    Ok(mut manifest) => {
                        if manifest.display.bin.is_relative()
                            && !manifest.display.bin.as_os_str().is_empty()
                        {
                            if let Some(manifest_dir) = path.parent() {
                                manifest.display.bin = manifest_dir.join(&manifest.display.bin);
                            }
                        }
                        log::info!(
                            "loaded display manifest: {} (de={:?} spawn={:?} priority={})",
                            manifest.display.name,
                            manifest.display.de,
                            manifest.display.spawn,
                            manifest.display.priority
                        );
                        reg.register(manifest.display);
                    }
                    Err(e) => log::warn!("skip {}: {e}", path.display()),
                },
                Err(e) => log::warn!("skip {}: {e}", path.display()),
            }
        }
        Ok(reg)
    }

    pub fn register(&mut self, def: DisplayDef) {
        // Replace any existing entry with the same name (XDG overrides bundled).
        self.defs.retain(|d| d.name != def.name);
        self.defs.push(def);
        self.defs.sort_by(|a, b| b.priority.cmp(&a.priority));
    }

    pub fn all(&self) -> &[DisplayDef] {
        &self.defs
    }

    pub fn find(&self, name: &str) -> Option<&DisplayDef> {
        self.defs.iter().find(|d| d.name == name)
    }
}

/// Build a registry by scanning the two canonical plugin paths:
/// 1. `<exec>/../share/waywallen/displays/`   (bundled)
pub fn build_default_registry() -> Result<DisplayRegistry> {
    let mut registry = DisplayRegistry::new();
    for dir in crate::plugin::renderer_registry::standard_plugin_dirs("displays") {
        if dir.is_dir() {
            match DisplayRegistry::scan(&dir) {
                Ok(scanned) => {
                    for def in scanned.all() {
                        registry.register(def.clone());
                    }
                }
                Err(e) => log::warn!("scan {}: {e}", dir.display()),
            }
        }
    }
    Ok(registry)
}
