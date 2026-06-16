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
                    a.modified_at.unwrap_or(0).cmp(&b.modified_at.unwrap_or(0))
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
