use crate::error::{Error, Result};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

fn fail(msg: impl Into<String>) -> Error {
    Error::PluginInstallFailed(msg.into())
}

fn user_plugins_dir() -> Result<PathBuf> {
    crate::plugin::renderer_registry::standard_plugin_dirs("plugins")
        .into_iter()
        .next_back()
        .ok_or_else(|| fail("no user plugin directory"))
}

fn read_plugin_id(manifest: &Path) -> Result<String> {
    #[derive(serde::Deserialize)]
    struct Manifest {
        plugin: Plugin,
    }
    #[derive(serde::Deserialize)]
    struct Plugin {
        id: String,
    }
    let text = std::fs::read_to_string(manifest).map_err(|e| fail(e.to_string()))?;
    let m: Manifest = toml::from_str(&text).map_err(|e| fail(format!("parse plugin.toml: {e}")))?;
    Ok(m.plugin.id)
}

/// Extract a plugin `.zip` into the user plugin directory and return the
/// installed plugin id. The archive must contain a top-level directory
pub fn install_zip(zip_path: &str) -> Result<String> {
    let file = std::fs::File::open(zip_path).map_err(|e| fail(format!("open {zip_path}: {e}")))?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| fail(format!("read zip: {e}")))?;

    let dest_root = user_plugins_dir()?;
    std::fs::create_dir_all(&dest_root)
        .map_err(|e| fail(format!("mkdir {}: {e}", dest_root.display())))?;

    let mut top_dirs: BTreeSet<String> = BTreeSet::new();

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| fail(e.to_string()))?;
        // `enclosed_name` rejects absolute paths and `..` traversal.
        let rel = match entry.enclosed_name() {
            Some(p) => p.to_path_buf(),
            None => return Err(fail(format!("unsafe path in archive: {}", entry.name()))),
        };
        if let Some(std::path::Component::Normal(first)) = rel.components().next() {
            top_dirs.insert(first.to_string_lossy().into_owned());
        }
        let out = dest_root.join(&rel);
        if entry.is_dir() {
            std::fs::create_dir_all(&out).map_err(|e| fail(e.to_string()))?;
        } else {
            if let Some(parent) = out.parent() {
                std::fs::create_dir_all(parent).map_err(|e| fail(e.to_string()))?;
            }
            let mut f = std::fs::File::create(&out).map_err(|e| fail(e.to_string()))?;
            std::io::copy(&mut entry, &mut f).map_err(|e| fail(e.to_string()))?;
        }
    }

    for d in &top_dirs {
        let manifest = dest_root.join(d).join("plugin.toml");
        if manifest.is_file() {
            let id = read_plugin_id(&manifest)?;
            log::info!(
                "installed plugin '{id}' into {}",
                dest_root.join(d).display()
            );
            return Ok(id);
        }
    }

    Err(fail(
        "archive must contain a top-level directory with plugin.toml",
    ))
}
