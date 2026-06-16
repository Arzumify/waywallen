pub mod dbusmenu;
mod sni;

use std::sync::Arc;

use anyhow::{anyhow, Result};
use zbus::Connection;

use crate::AppState;

const ITEM_PATH: &str = "/StatusNotifierItem";
pub const MENU_PATH: &str = "/MenuBar";
const WATCHER_SERVICE: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const WATCHER_IFACE: &str = "org.kde.StatusNotifierWatcher";

pub async fn spawn(conn: Arc<Connection>, app: Arc<AppState>) -> Result<()> {
    // Hosts resolve `IconName` against their own `XDG_DATA_DIRS`.
    // That may miss the AppImage squashfs mount, so expose a theme path.
    let icon_theme_path = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent()?.parent().map(|p| p.join("share/icons")))
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    let item = sni::StatusNotifierItem::new(app.clone(), icon_theme_path);
    let menu = dbusmenu::DBusMenu::new(app.clone());

    conn.object_server().at(ITEM_PATH, item).await?;
    conn.object_server().at(MENU_PATH, menu).await?;

    register_with_watcher(&conn).await?;

    // Re-register whenever the watcher (re)appears.
    let conn_bg = conn.clone();
    tokio::spawn(async move {
        if let Err(e) = watch_watcher(conn_bg).await {
            log::warn!("tray watcher monitor exited: {e}");
        }
    });

    log::info!("tray: registered {ITEM_PATH}");
    Ok(())
}

async fn register_with_watcher(conn: &Connection) -> Result<()> {
    let proxy = zbus::Proxy::new(conn, WATCHER_SERVICE, WATCHER_PATH, WATCHER_IFACE).await?;
    proxy
        .call_method("RegisterStatusNotifierItem", &ITEM_PATH)
        .await
        .map_err(|e| anyhow!("RegisterStatusNotifierItem: {e}"))?;
    Ok(())
}

async fn watch_watcher(conn: Arc<Connection>) -> Result<()> {
    use futures_util::StreamExt;
    let dbus = zbus::fdo::DBusProxy::new(&conn).await?;
    let mut stream = dbus.receive_name_owner_changed().await?;
    while let Some(sig) = stream.next().await {
        let args = match sig.args() {
            Ok(a) => a,
            Err(_) => continue,
        };
        if args.name.as_str() != WATCHER_SERVICE {
            continue;
        }
        let new_owner = args.new_owner.as_ref().map(|o| o.as_str()).unwrap_or("");
        if !new_owner.is_empty() {
            log::info!("tray: watcher reappeared, re-registering");
            if let Err(e) = register_with_watcher(&conn).await {
                log::warn!("tray: re-register failed: {e}");
            }
        }
    }
    Ok(())
}
