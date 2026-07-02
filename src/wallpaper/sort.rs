use std::collections::HashSet;
use std::sync::Arc;

use anyhow::Result;

use crate::control_proto as pb;
use crate::model::repo;
use crate::wallpaper::types::WallpaperEntry;
use crate::AppState;

/// Apply composite sort rules in-place. Rules are applied in reverse
/// so the first rule ends up as the primary key (sort_by is stable).
pub fn apply_wallpaper_sorts(entries: &mut [&WallpaperEntry], sorts: &[pb::WallpaperSortRule]) {
    use std::cmp::Ordering;

    for rule in sorts.iter().rev() {
        let key = match pb::WallpaperSortKey::try_from(rule.key) {
            Ok(k) if k != pb::WallpaperSortKey::Unspecified => k,
            _ => continue,
        };
        let desc = pb::SortDirection::try_from(rule.direction) == Ok(pb::SortDirection::Desc);

        entries.sort_by(|a, b| {
            let ord = match key {
                pb::WallpaperSortKey::Name => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
                pb::WallpaperSortKey::WpType => a.wp_type.cmp(&b.wp_type),
                pb::WallpaperSortKey::Size => a.size.unwrap_or(0).cmp(&b.size.unwrap_or(0)),
                pb::WallpaperSortKey::LastModified => {
                    last_modified_key(a).cmp(&last_modified_key(b))
                }
                pb::WallpaperSortKey::Unspecified => Ordering::Equal,
            };
            if desc {
                ord.reverse()
            } else {
                ord
            }
        });
    }
}

fn last_modified_key(entry: &WallpaperEntry) -> i64 {
    entry.modified_at.unwrap_or(entry.create_at)
}

/// Resolve the user-visible ordered list of entry ids: DB entries →
/// filter → sort. Mirrors the WallpaperList pipeline so D-Bus
pub async fn ordered_entry_ids(
    app: &Arc<AppState>,
    filters: &[pb::WallpaperFilterRule],
    logics: &[pb::FilterLogic],
    sorts: &[pb::WallpaperSortRule],
) -> Result<Vec<String>> {
    let all = repo::load_entries(&app.db).await?;

    let matched_keys: Option<HashSet<(String, String)>> = if filters.is_empty() {
        None
    } else {
        Some(
            repo::list_item_keys_by_wallpaper_filters(&app.db, filters, logics)
                .await?
                .into_iter()
                .collect(),
        )
    };

    let mut filtered: Vec<&WallpaperEntry> = if let Some(keys) = matched_keys.as_ref() {
        all.iter()
            .filter(|e| {
                crate::model::sync::relative_under_root(&e.library_root, &e.resource)
                    .map(|rel| keys.contains(&(e.library_root.clone(), rel)))
                    .unwrap_or(false)
            })
            .collect()
    } else {
        all.iter().collect()
    };

    if !sorts.is_empty() {
        apply_wallpaper_sorts(&mut filtered, sorts);
    }

    Ok(filtered
        .into_iter()
        .map(|e| e.item_id.to_string())
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(name: &str, modified_at: Option<i64>, create_at: i64) -> WallpaperEntry {
        WallpaperEntry {
            item_id: 0,
            name: name.to_string(),
            wp_type: "image".to_string(),
            resource: name.to_string(),
            preview: None,
            description: None,
            tags: Vec::new(),
            external_id: None,
            size: None,
            width: None,
            height: None,
            content_rating: None,
            modified_at,
            create_at,
            plugin_name: String::new(),
            library_root: String::new(),
        }
    }

    #[test]
    fn last_modified_sort_falls_back_to_create_at() {
        let newer_created = entry("created-newer", None, 30);
        let older_modified = entry("modified-older", Some(20), 40);
        let older_created = entry("created-older", None, 10);
        let mut entries = vec![&newer_created, &older_modified, &older_created];

        apply_wallpaper_sorts(
            &mut entries,
            &[pb::WallpaperSortRule {
                key: pb::WallpaperSortKey::LastModified as i32,
                direction: pb::SortDirection::Asc as i32,
            }],
        );

        let names: Vec<_> = entries.iter().map(|entry| entry.name.as_str()).collect();
        assert_eq!(
            names,
            vec!["created-older", "modified-older", "created-newer"]
        );
    }
}
