pragma ComponentBehavior: Bound
pragma ValueTypeBehavior: Assertable
import QtQuick
import QtQml as Qml
import QtQuick.Layouts
import QtQuick.Templates as T
import Qcm.Material as MD
import waywallen.control as WC
import waywallen.ui as W

MD.Page {
    id: root

    W.WallpaperListQuery {
        id: wallpaperQuery
    }

    W.WallpaperSelectStorage {
        id: userWallpaperSelect
        model: wallpaperQuery.data
        property list<MD.Action> actions: [
            createPlaylistFromSelectionAction,
            addToPlaylistAction
        ]
    }

    W.WallpaperSelectStorage {
        id: playlistWallpaperSelect
        model: wallpaperQuery.data
        property list<MD.Action> actions: [
            applyPlaylistSelectionAction,
            createPlaylistFromSelectionAction,
            addToPlaylistAction
        ]
    }

    W.WallpaperScanQuery {
        id: scanQuery
    }

    W.PlaylistListQuery {
        id: playlistListQuery
    }

    property bool playlistListReady: false
    property string playlistMutationSuccessMessage: ""
    property string playlistMutationPendingMessage: ""
    readonly property bool playlistListLoading: playlistListQuery.querying && !root.playlistListReady

    Connections {
        target: playlistListQuery
        function onPlaylistsChanged() {
            root.playlistListReady = true;
        }
        function onStatusChanged(status) {
            if (status !== 1)
                root.playlistListReady = true;
        }
    }

    W.PlaylistMutationQuery {
        id: playlistMutation
        onDone: {
            if (playlistMutation.status === 3) {
                root.playlistMutationSuccessMessage = "";
                root.playlistMutationPendingMessage = "";
                playlistMutationCleanupTimer.stop();
                W.Action.toast(qsTr("Playlist update failed"));
                return;
            }
            root.playlistMutationPendingMessage = root.playlistMutationSuccessMessage.length > 0
                ? root.playlistMutationSuccessMessage
                : qsTr("Playlist updated");
            root.playlistMutationSuccessMessage = "";
            playlistMutationCleanupTimer.restart();
        }
    }

    W.PlaylistMutationQuery {
        id: playlistDetailMutation
        onDone: {
            playlistListQuery.reload();
        }
    }

    W.PlaylistMutationQuery {
        id: playlistPlaybackMutation
        onDone: {
            if (playlistPlaybackMutation.status === 3)
                W.Action.toast(qsTr("Playlist playback failed"));
        }
    }

    Qml.Timer {
        id: playlistMutationCleanupTimer
        interval: MD.Token.duration.short4 + 16
        repeat: false
        onTriggered: {
            const message = root.playlistMutationPendingMessage;
            root.playlistMutationPendingMessage = "";
            playlistListQuery.reload();
            root.clearWallpaperSelection();
            if (playlistListSheet.opened || playlistListSheet.entering)
                playlistListSheet.close();
            if (message.length > 0)
                W.Action.toast(message);
        }
    }

    QtObject {
        id: wallpaperSelectSheetRelay

        property var activeAction: null
        property Component activeComponent: null
        property Component defaultComponent: null
        readonly property Component currentComponent: activeComponent ? activeComponent : defaultComponent

        signal newPlaylistRequested()
        signal addToPlaylistRequested()

        function reset() {
            activeAction = null;
            activeComponent = null;
            defaultComponent = null;
        }

        function restoreDefault() {
            activeAction = null;
            activeComponent = null;
        }

        function toggle(action, component) {
            if (activeAction === action) {
                restoreDefault();
                return false;
            }
            activeAction = action;
            activeComponent = component;
            return true;
        }

        function requestNewPlaylist() {
            if (toggle(createPlaylistFromSelectionAction, newPlaylistSheetComponent))
                newPlaylistRequested();
        }

        function requestAddToPlaylist() {
            if (toggle(addToPlaylistAction, addToPlaylistSheetComponent)) {
                playlistListQuery.reload();
                addToPlaylistRequested();
            }
        }
    }

    // Daemon-driven syncs (manual click, LibraryAdd/Remove, startup)
    // all reach the UI through `Notify` (mirrors the daemon's
    // `GlobalEvent` broadcasts). Toast UX is handled here via
    // `Action.toast`; Notify itself is intentionally toast-free.
    Connections {
        target: W.Notify
        function onWallpaperSyncFinished(count, error) {
            if (error && error.length > 0) {
                W.Action.toast("Sync failed: " + error);
            } else {
                W.Action.toast("Scanned " + count + " wallpapers");
            }
            wallpaperQuery.reload();
        }
        function onDaemonReady() {
            root.reloadAll();
        }
        function onPlaylistChanged() {
            playlistListQuery.reload();
        }
    }

    function reloadAll() {
        pluginQuery.reload();
        playlistListQuery.reload();
        filterSettingsGet.reload();
    }

    Component.onCompleted: {
        applySort();
        if (W.Notify.daemonPhase === W.Notify.DaemonPhase.Ready)
            reloadAll();
    }

    W.WallpaperApplyQuery {
        id: applyQuery
    }

    // After a successful apply the renderer eventually emits
    // `ReportProperties`; re-fetch the detail entry so the
    // UserPropertyPanel picks up the freshly-published schema.
    Connections {
        target: applyQuery
        function onRendererIdChanged() {
            if (applyQuery.rendererId)
                wallpaperGetQuery.reload();
        }
    }

    // Independent of applyQuery: hands the image URI to the DE's
    // xdg-desktop-portal Wallpaper backend. Image-only; engaged only
    // when displays.length == 0 (no daemon display surface available).
    W.WallpaperApplyViaPortalQuery {
        id: portalApplyQuery
    }
    Connections {
        target: portalApplyQuery
        function onStatusChanged() {
            // QAsyncResult::Status — 2=Finished, 3=Error.
            if (portalApplyQuery.status === 3)
                W.Action.toast("Portal apply failed");
            else if (portalApplyQuery.status === 2)
                W.Action.toast("Wallpaper sent to desktop portal");
        }
    }

    MD.Action {
        id: applyAction
        text: "Apply"
        busy: applyQuery.querying
        enabled: (W.App.displayManager.displays || []).length > 0
        onTriggered: {
            if (busy) return;
            if (!root.selectedWallpaper) return;
            applyQuery.wallpaper = root.selectedWallpaper;
            applyQuery.displayIds = root.applyTargetIds;
            if (root.rendererCandidates.length >= 2) {
                const pick = root.rendererCandidates[root.rendererIndex];
                applyQuery.rendererName = pick ? (pick.name || "") : "";
            } else {
                applyQuery.rendererName = "";
            }
            applyQuery.reload();
        }
    }

    MD.Action {
        id: applyViaPortalAction
        text: "Apply via desktop portal"
        busy: portalApplyQuery.querying
        onTriggered: {
            if (busy) return;
            if (!root.selectedWallpaper) return;
            portalApplyQuery.wallpaperId = root.selectedWallpaper.id_proto;
            portalApplyQuery.reload();
        }
    }

    MD.Action {
        id: closeDetailAction
        text: "Close"
        icon.name: MD.Token.icon.close
        onTriggered: root.selectedWallpaper = null
    }

    MD.Action {
        id: infoDetailAction
        text: "Info"
        icon.name: MD.Token.icon.info
        enabled: root.selectedWallpaper !== null
        onTriggered: root.openInfo()
    }

    MD.Action {
        id: openContainerFolderDetailAction
        text: "Open container folder"
        icon.name: MD.Token.icon.folder_open
        enabled: root.containerFolderUrl(root.infoWallpaper()?.resource).length > 0
        onTriggered: root.openContainerFolder()
    }

    MD.Action {
        id: createPlaylistFromSelectionAction
        text: "New playlist"
        icon.name: MD.Token.icon.playlist_add
        busy: playlistMutation.querying
        checked: wallpaperSelectSheetRelay.activeAction === createPlaylistFromSelectionAction
        enabled: root.selectedWallpaperCount > 0
        onTriggered: wallpaperSelectSheetRelay.requestNewPlaylist()
    }

    MD.Action {
        id: addToPlaylistAction
        text: "Add to playlist"
        icon.name: MD.Token.icon.playlist_add
        checked: wallpaperSelectSheetRelay.activeAction === addToPlaylistAction
        enabled: root.selectedWallpaperCount > 0
              && (playlistListQuery.playlists || []).length > 0
              && !playlistMutation.querying
        onTriggered: wallpaperSelectSheetRelay.requestAddToPlaylist()
    }

    MD.Action {
        id: applyPlaylistSelectionAction
        text: "Apply"
        icon.name: MD.Token.icon.check
        busy: playlistMutation.querying
        enabled: playlistWallpaperSelect.playlistEditTargetId > 0
              && !playlistMutation.querying
        onTriggered: root.applyPlaylistSelection()
    }

    MD.Action {
        id: playlistListAction
        text: "Playlists"
        icon.name: MD.Token.icon.playlist_play
        checked: W.App.displayManager.hasActivePlaylistDisplays
        onTriggered: root.togglePlaylistListSheet()
    }

    MD.Action {
        id: tweakAction
        text: "Tweak"
        icon.name: MD.Token.icon.tune
        checked: wallpaperTweakSheet.opened || wallpaperTweakSheet.entering
        onTriggered: root.toggleWallpaperTweakSheet()
    }

    MD.Action {
        id: filterAction
        icon.name: MD.Token.icon.filter_list
        text: "Filters"
        checked: wallpaperQuery.hasActiveFilters
        onTriggered: filterDialog.open()
    }

    MD.Action {
        id: sourcesAction
        icon.name: MD.Token.icon.hard_drive
        text: "Sources"
        onTriggered: MD.Util.showPopup('waywallen.ui/PagePopup', {
            source: 'waywallen.ui/SourceManagePage'
        }, root)
    }

    MD.Action {
        id: refreshAction
        icon.name: MD.Token.icon.refresh
        text: "Refresh"
        enabled: !W.Notify.scanInProgress
        onTriggered: scanQuery.reload()
    }

    readonly property MD.Action activeApplyAction:
        ((root.selectedWallpaper?.wpType ?? "") === "image"
            && (W.App.displayManager.displays || []).length === 0)
        ? applyViaPortalAction : applyAction

    // Detail panel uses this to fetch the freshest view (tags + media
    // meta) for the currently-selected entry. Reload is auto-triggered
    // when wallpaperId changes.
    W.WallpaperGetQuery {
        id: wallpaperGetQuery
        // `id` is a QML keyword, so qtprotobuf renames `WallpaperEntry.id`
        // to `id_proto`. Using `.id` here would always read undefined.
        wallpaperId: root.selectedWallpaper?.id_proto ?? ""
    }

    W.RendererPluginListQuery {
        id: pluginQuery
    }

    W.LibraryAutoDetectQuery {
        id: autoDetectQuery
    }

    // Quick filters (skip-types, tag filter) are seeded from settings
    // once; after that the local selection is authoritative. Re-adopting
    // them on every settings echo would revert a just-applied toggle
    // whenever the round-trip lags.
    property bool _quickFiltersSeeded: false

    W.SettingsGetQuery {
        id: filterSettingsGet
        onGlobalChanged: {
            // Restore sort first so the filter pipeline below doesn't
            // dispatch a list reload with the stale sort: doQuery may
            // route through wallpaperQuery.reload() synchronously when
            // filter state already matches, and m_sorts must already
            // be the persisted value at that point.
            root.restoreSortFromSettings(global.wallpaperSorts || []);
            if (!root._quickFiltersSeeded) {
                wallpaperQuery.skipTypes = global.wallpaperSkipTypes || [];
                wallpaperQuery.filterTags = global.wallpaperFilterTags || [];
                wallpaperQuery.skipContentRatings = global.wallpaperSkipContentRatings || [];
                root._quickFiltersSeeded = true;
            }
            wallpaperFilterModel.replaceState(
                        global.wallpaperFilters || [],
                        global.wallpaperFilterLogics || []);
            wallpaperFilterModel.doQuery();
        }
    }

    W.SettingsSetQuery {
        id: filterSettingsSet
    }

    // QAbstractItemModel doesn't auto-expose `count` as a Q_PROPERTY —
    // mirror it here so visibility bindings re-evaluate on row changes.
    property int filterRuleCount: 0
    function _recomputeFilterRuleCount() {
        root.filterRuleCount = wallpaperFilterModel.rowCount();
    }

    Connections {
        target: wallpaperFilterModel
        function onRowsInserted()   { root._recomputeFilterRuleCount(); }
        function onRowsRemoved()    { root._recomputeFilterRuleCount(); }
        function onModelReset()     { root._recomputeFilterRuleCount(); }
        function onLayoutChanged()  { root._recomputeFilterRuleCount(); }
    }

    W.WallpaperFilterRuleModel {
        id: wallpaperFilterModel

        function doQuery() {
            if (!wallpaperQuery.replaceFilterState(items(), filterLogics))
                wallpaperQuery.reload();
        }

        onApply: {
            doQuery();
            root._persistGlobalChange(g => {
                g.wallpaperFilters = items();
                g.wallpaperFilterLogics = filterLogics;
            });
        }

        onReset: {
            replaceState(
                        filterSettingsGet.global.wallpaperFilters || [],
                        filterSettingsGet.global.wallpaperFilterLogics || []);
            doQuery();
        }
    }

    W.WallpaperFilterDialog {
        id: filterDialog
        parent: T.Overlay.overlay
        model: wallpaperFilterModel
        supportedTypes: pluginQuery.supportedTypes || []
        skipTypes: wallpaperQuery.skipTypes
        onToggleSkip: function (ty) {
            const next = (wallpaperQuery.skipTypes || []).slice();
            const i = next.indexOf(ty);
            if (i >= 0)
                next.splice(i, 1);
            else
                next.push(ty);
            wallpaperQuery.skipTypes = next;
            root._persistGlobalChange(g => { g.wallpaperSkipTypes = next; });
        }
        filterTags: wallpaperQuery.filterTags
        onApplyFilterTags: function (tags) {
            wallpaperQuery.filterTags = tags;
            root._persistGlobalChange(g => { g.wallpaperFilterTags = tags; });
        }
        skipContentRatings: wallpaperQuery.skipContentRatings
        onToggleSkipRating: function (rating) {
            const next = (wallpaperQuery.skipContentRatings || []).slice();
            const i = next.indexOf(rating);
            if (i >= 0)
                next.splice(i, 1);
            else
                next.push(rating);
            wallpaperQuery.skipContentRatings = next;
            root._persistGlobalChange(g => { g.wallpaperSkipContentRatings = next; });
        }
    }

    Connections {
        target: W.Notify
        function onSettingsChanged() {
            filterSettingsGet.reload();
        }
    }

    readonly property var sortOptions: [
        { name: qsTr("Name"),          key: WC.WallpaperSortKey.WALLPAPER_SORT_KEY_NAME },
        { name: qsTr("Size"),          key: WC.WallpaperSortKey.WALLPAPER_SORT_KEY_SIZE },
        { name: qsTr("Last modified"), key: WC.WallpaperSortKey.WALLPAPER_SORT_KEY_LAST_MODIFIED }
    ]
    property int sortIndex: 0
    property bool sortAsc: true
    property WC.wallpaperSortRule emptySortRule

    readonly property int wallpaperItemLayoutFillCell: 0
    readonly property int wallpaperItemLayoutFixed: 1
    property int wallpaperItemSize: 162
    property real wallpaperItemAspectRatio: 1
    property int wallpaperItemLayoutMode: wallpaperItemLayoutFillCell
    readonly property real wallpaperItemHeight: root.wallpaperItemSize
        / Math.max(root.wallpaperItemAspectRatio, 0.1)

    onWallpaperItemSizeChanged: if (m_grid_view) m_grid_view.forceLayout()
    onWallpaperItemAspectRatioChanged: if (m_grid_view) m_grid_view.forceLayout()
    onWallpaperItemLayoutModeChanged: if (m_grid_view) m_grid_view.forceLayout()

    function _buildSortRule() {
        const rule = emptySortRule;
        rule.key = sortOptions[sortIndex].key;
        rule.direction = sortAsc ? WC.SortDirection.SORT_DIRECTION_ASC
                                 : WC.SortDirection.SORT_DIRECTION_DESC;
        return rule;
    }
    function applySort() {
        wallpaperQuery.sorts = [_buildSortRule()];
    }
    // Guard: don't overwrite daemon state with proto defaults when the
    // local mirror of settings hasn't been populated yet. Without this,
    // a click that lands before filterSettingsGet's first response
    // ships a SettingsSet with only the touched field; the daemon then
    // resets target_extent to 0 and clears the filter on commit.
    function _persistGlobalChange(mutator) {
        if (Object.keys(filterSettingsGet.global).length === 0)
            return;
        const nextGlobal = Object.assign({}, filterSettingsGet.global);
        mutator(nextGlobal);
        filterSettingsSet.global = nextGlobal;
        filterSettingsSet.plugins = filterSettingsGet.plugins;
        filterSettingsSet.reload();
    }
    function pickSort(idx) {
        if (idx === sortIndex) {
            sortAsc = !sortAsc;
        } else {
            // Switching key keeps the current asc/desc order.
            sortIndex = idx;
        }
        applySort();
        _persistGlobalChange(g => { g.wallpaperSorts = [_buildSortRule()]; });
    }
    function restoreSortFromSettings(rules) {
        if (!rules || rules.length === 0) {
            // No persisted sort yet — keep whatever defaults are in place
            // and push them down so the list query has at least one rule.
            applySort();
            return;
        }
        const r = rules[0];
        const idx = sortOptions.findIndex(o => o.key === r.key);
        if (idx >= 0) sortIndex = idx;
        sortAsc = r.direction !== WC.SortDirection.SORT_DIRECTION_DESC;
        applySort();
    }

    function setWallpaperItemAspectRatio(ratio) {
        root.wallpaperItemAspectRatio = ratio;
    }

    // Renderers that advertise the selected wallpaper's wp_type, sorted
    // by descending priority. Recomputed on selection or registry change.
    readonly property var rendererCandidates: {
        const wp = root.selectedWallpaper;
        if (!wp) return [];
        const t = wp.wpType || "";
        if (!t) return [];
        const list = (pluginQuery.renderers || []).filter(r => (r.types || []).indexOf(t) >= 0);
        list.sort((a, b) => (b.priority || 0) - (a.priority || 0));
        return list;
    }

    property var selectedWallpaper: null
    property var currentWallpaperSelect: null
    property var wallpaperSelectSheet: null
    readonly property int selectionSheetReserve: wallpaperSelectSheetRelay.currentComponent ? 360 : 160
    readonly property int selectedWallpaperCount: root.currentWallpaperSelect
        ? root.currentWallpaperSelect.selectedCount
        : 0
    readonly property bool selectionActive: root.currentWallpaperSelect
        ? root.currentWallpaperSelect.active
        : false
    readonly property bool selectionActionSheetActive: root.selectionActive
        && root.currentWallpaperSelect
        && (root.currentWallpaperSelect.actions || []).length > 0

    onSelectionActiveChanged: {
        if (selectionActive) {
            selectedWallpaper = null;
            if (m_grid_view)
                m_grid_view.currentIndex = -1;
        } else {
            wallpaperSelectSheetRelay.reset();
        }
        root.syncWallpaperSelectSheet();
    }

    Connections {
        target: W.Action
        function onWallpaperSelectEntered(storage) {
            root.adoptWallpaperSelect(storage);
        }
    }

    Connections {
        target: root.currentWallpaperSelect
        function onActiveChanged() {
            root.syncWallpaperSelectSheet();
        }
    }

    function ensureWallpaperSelectSheet() {
        if (root.wallpaperSelectSheet)
            return root.wallpaperSelectSheet;

        const sheet = MD.Util.showPopup(wallpaperSelectSheetComponent, {}, root);
        if (sheet)
            root.wallpaperSelectSheet = sheet;
        return sheet;
    }

    function releaseWallpaperSelectSheet(sheet) {
        const target = sheet || root.wallpaperSelectSheet;
        if (!target)
            return;
        if (root.wallpaperSelectSheet === target)
            root.wallpaperSelectSheet = null;
    }

    function destroyWallpaperSelectSheet(sheet) {
        const target = sheet || root.wallpaperSelectSheet;
        root.releaseWallpaperSelectSheet(target);
        Qt.callLater(function() {
            target.destroy();
        });
    }

    function syncWallpaperSelectSheet() {
        root.configureWallpaperSelectSheetDefault();

        if (root.selectionActionSheetActive) {
            const sheet = root.ensureWallpaperSelectSheet();
            if (sheet && !sheet.opened && !sheet.entering)
                sheet.open();
            return;
        }

        if (root.wallpaperSelectSheet
                && (root.wallpaperSelectSheet.opened || root.wallpaperSelectSheet.entering)) {
            root.wallpaperSelectSheet.close();
            return;
        }

        if (root.wallpaperSelectSheet && !root.wallpaperSelectSheet.closing)
            root.destroyWallpaperSelectSheet(root.wallpaperSelectSheet);
    }

    function adoptWallpaperSelect(storage) {
        if (storage !== userWallpaperSelect && storage !== playlistWallpaperSelect)
            return;
        if (root.currentWallpaperSelect !== storage) {
            if (root.currentWallpaperSelect)
                root.currentWallpaperSelect.clear();
            root.currentWallpaperSelect = storage;
            wallpaperSelectSheetRelay.reset();
        }
        root.configureWallpaperSelectSheetDefault();
        root.syncWallpaperSelectSheet();
    }

    function configureWallpaperSelectSheetDefault() {
        wallpaperSelectSheetRelay.defaultComponent =
            root.currentWallpaperSelect === playlistWallpaperSelect
                ? playlistSelectDetailComponent
                : null;
    }

    function enterWallpaperSelect(storage) {
        if (!storage)
            return;
        root.adoptWallpaperSelect(storage);
        W.Action.enterWallpaperSelect(storage);
    }

    function interactionWallpaperSelect() {
        return root.currentWallpaperSelect && root.currentWallpaperSelect.active
            ? root.currentWallpaperSelect
            : userWallpaperSelect;
    }

    function beginWallpaperSelection(index) {
        root.enterWallpaperSelect(userWallpaperSelect);
        const row = index === undefined ? -1 : Number(index);
        if (!userWallpaperSelect.begin(row))
            return;

        root.selectedWallpaper = null;
        if (m_grid_view)
            m_grid_view.currentIndex = -1;
        if (m_grid_view)
            m_grid_view.forceActiveFocus();
        root.syncWallpaperSelectSheet();
    }

    function clearWallpaperSelection() {
        if (root.currentWallpaperSelect)
            root.currentWallpaperSelect.clear();
        root.currentWallpaperSelect = null;
        wallpaperSelectSheetRelay.reset();
        root.syncWallpaperSelectSheet();
    }

    function selectedWallpaperIds() {
        return root.currentWallpaperSelect
            ? root.currentWallpaperSelect.selectedWallpaperIds()
            : [];
    }

    property var playlistPlayDisplayId: null
    readonly property var playlistPlayDisplays: W.App.displayManager.displays || []

    onPlaylistPlayDisplaysChanged: {
        if (playlistPlayDisplays.length === 0) {
            playlistPlayDisplayId = null;
            return;
        }
        if (!root.displayById(playlistPlayDisplayId))
            playlistPlayDisplayId = playlistPlayDisplays[0].id;
    }

    function displayById(id) {
        if (id === null || id === undefined)
            return null;
        const key = String(id);
        const displays = root.playlistPlayDisplays || [];
        for (let i = 0; i < displays.length; ++i) {
            if (String(displays[i].id) === key)
                return displays[i];
        }
        return null;
    }

    function displayLabel(display) {
        if (!display)
            return qsTr("Display");
        const alias = display.displayLabel || "";
        if (alias.length > 0)
            return alias;
        const name = (display.name || "").replace(/^waywallen-[a-z]+-[a-z]+-/, "");
        return name.length > 0 ? name : qsTr("Display %1").arg(display.id);
    }

    function selectedPlaylistDisplay() {
        const displays = root.playlistPlayDisplays || [];
        if (displays.length === 0)
            return null;
        return root.displayById(root.playlistPlayDisplayId) || displays[0];
    }

    function selectedPlaylistDisplayId() {
        const display = root.selectedPlaylistDisplay();
        return display ? display.id : null;
    }

    function playlistDisplayStatuses(playlist) {
        if (!playlist)
            return [];
        const playlistId = String(playlist.id);
        const statuses = root.playlistPlayDisplays || [];
        const out = [];
        for (let i = 0; i < statuses.length; ++i) {
            if (String(statuses[i].activePlaylistId) === playlistId)
                out.push(statuses[i]);
        }
        return out;
    }

    function playlistDisplayLabels(playlist) {
        const statuses = root.playlistDisplayStatuses(playlist);
        const out = [];
        for (let i = 0; i < statuses.length; ++i)
            out.push(root.displayLabel(statuses[i]));
        return out;
    }

    function playlistIsPlayingOnSelectedDisplay(playlist) {
        const displayId = root.selectedPlaylistDisplayId();
        if (!playlist || displayId === null || displayId === undefined)
            return false;
        const playlistId = String(playlist.id);
        const displayKey = String(displayId);
        const statuses = root.playlistPlayDisplays || [];
        for (let i = 0; i < statuses.length; ++i) {
            if (String(statuses[i].id) === displayKey
                    && String(statuses[i].activePlaylistId) === playlistId)
                return true;
        }
        return false;
    }

    function togglePlaylistPlayback(playlist) {
        const display = root.selectedPlaylistDisplay();
        if (!playlist || !display || playlistPlaybackMutation.querying)
            return;
        const displayIds = [display.id];
        if (root.playlistIsPlayingOnSelectedDisplay(playlist))
            playlistPlaybackMutation.deactivate(displayIds, 0);
        else
            playlistPlaybackMutation.activate(playlist.id, displayIds, false);
    }

    function togglePlaylistListSheet() {
        if (playlistListSheet.opened || playlistListSheet.entering) {
            playlistListSheet.close();
            return;
        }
        if (wallpaperTweakSheet.opened || wallpaperTweakSheet.entering)
            wallpaperTweakSheet.close();
        playlistListQuery.reload();
        playlistListSheet.open();
    }

    function toggleWallpaperTweakSheet() {
        if (wallpaperTweakSheet.opened || wallpaperTweakSheet.entering) {
            wallpaperTweakSheet.close();
            return;
        }
        if (playlistListSheet.opened || playlistListSheet.entering)
            playlistListSheet.close();
        wallpaperTweakSheet.open();
    }

    function isEditingPlaylist(playlist) {
        return playlistWallpaperSelect.isEditingPlaylist(playlist);
    }

    function editPlaylistSelection(playlist) {
        if (!playlist)
            return;

        root.enterWallpaperSelect(playlistWallpaperSelect);
        playlistWallpaperSelect.editPlaylistSelection(playlist);
        root.selectedWallpaper = null;
        if (m_grid_view)
            m_grid_view.currentIndex = -1;
        if (playlistListSheet.opened || playlistListSheet.entering)
            playlistListSheet.close();
        if (m_grid_view)
            m_grid_view.forceActiveFocus();
        root.syncWallpaperSelectSheet();
    }

    function confirmPlaylistSelection(playlist) {
        if (!root.isEditingPlaylist(playlist) || playlistMutation.querying)
            return;
        playlistMutation.setItems(playlist.id, playlistWallpaperSelect.selectedWallpaperIds());
    }

    function applyPlaylistSelection() {
        root.confirmPlaylistSelection(playlistWallpaperSelect.playlistEditTarget);
    }

    function handleWallpaperClick(index, modifiers) {
        const model = wallpaperQuery.data;
        if (!model)
            return;

        if ((modifiers & Qt.ShiftModifier) !== 0) {
            const select = root.interactionWallpaperSelect();
            root.enterWallpaperSelect(select);
            const anchor = select.anchorIndex >= 0
                ? select.anchorIndex
                : (m_grid_view.currentIndex >= 0 ? m_grid_view.currentIndex : index);
            select.selectRange(anchor, index, true);
            select.selectionMode = true;
            select.anchorIndex = anchor;
            root.selectedWallpaper = null;
            root.syncWallpaperSelectSheet();
            return;
        }

        if (root.selectionActive || (modifiers & Qt.ControlModifier) !== 0) {
            const select = root.interactionWallpaperSelect();
            root.enterWallpaperSelect(select);
            select.toggleSelected(index);
            root.selectedWallpaper = null;
            root.syncWallpaperSelectSheet();
            return;
        }

        m_grid_view.currentIndex = index;
        userWallpaperSelect.anchorIndex = index;
        root.selectedWallpaper = model.item(index);
    }

    function requestWallpaperSelection(index) {
        const model = wallpaperQuery.data;
        if (!model)
            return;

        root.beginWallpaperSelection(index);
    }

    function createPlaylistFromSelection(name) {
        const ids = root.selectedWallpaperIds();
        if (ids.length === 0 || playlistMutation.querying)
            return;

        const title = String(name || "").trim();
        playlistMutation.create(title.length > 0 ? title : qsTr("New playlist"), 1, 300, ids);
    }

    function addSelectionToPlaylist(playlist) {
        const ids = root.selectedWallpaperIds();
        if (ids.length === 0 || !playlist || playlistMutation.querying)
            return;

        const merged = (playlist.entryIds || []).slice();
        const seen = {};
        for (let i = 0; i < merged.length; ++i)
            seen[String(merged[i])] = true;
        for (let j = 0; j < ids.length; ++j) {
            const key = String(ids[j]);
            if (seen[key] !== true) {
                merged.push(ids[j]);
                seen[key] = true;
            }
        }
        root.playlistMutationSuccessMessage = qsTr("Added to playlist");
        playlistMutation.setItems(playlist.id, merged);
    }

    function deletePlaylist(playlist) {
        if (!playlist || playlistMutation.querying)
            return;

        root.playlistMutationSuccessMessage = qsTr("Playlist deleted");
        playlistMutation.remove(playlist.id);
    }

    // Index into rendererCandidates; reset to 0 whenever the candidate
    // list changes (selection or registry update).
    property int rendererIndex: 0
    onRendererCandidatesChanged: rendererIndex = 0

    // Target display ids for Apply. Empty set = "All displays".
    property var applyTargetIds: []
    function isTargetAll() {
        return applyTargetIds.length === 0;
    }
    function toggleTarget(id) {
        const next = applyTargetIds.slice();
        const i = next.indexOf(id);
        if (i >= 0)
            next.splice(i, 1);
        else
            next.push(id);
        applyTargetIds = next;
    }
    function infoWallpaper() {
        return (wallpaperGetQuery.wallpaper?.id_proto ?? "") !== ""
            ? wallpaperGetQuery.wallpaper
            : root.selectedWallpaper;
    }
    function infoSizeOf(w) {
        return wallpaperQuery.data && w ? wallpaperQuery.data.sizeOf(w) : 0;
    }
    function openInfo() {
        const wp = infoWallpaper();
        if (!wp)
            return;
        MD.Util.showPopup('waywallen.ui/PagePopup', {
            source: 'waywallen.ui/WallpaperInfoPage',
            props: {
                wallpaper: wp,
                sizeBytes: root.infoSizeOf(wp)
            }
        }, root);
    }
    function containerFolderUrl(resource) {
        let path = String(resource || "");
        if (path.length === 0)
            return "";
        if (path.indexOf("file://") === 0)
            path = path.slice(7);
        const i = path.lastIndexOf("/");
        if (i <= 0)
            return "";
        return "file://" + path.slice(0, i).split("/").map(encodeURIComponent).join("/");
    }
    function openContainerFolder() {
        const url = root.containerFolderUrl(root.infoWallpaper()?.resource);
        if (url.length > 0)
            MD.Util.openUrlExternally(url);
    }
    showBackground: false
    padding: MD.MProp.size.isCompact ? 0 : 12

    contentItem: RowLayout {
        spacing: 12

        // --- Left: wallpaper grid ---
        MD.Pane {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.MD.MProp.page.backgroundRadius
            padding: 0
            showBackground: true

            contentItem: ColumnLayout {
                spacing: 0

                // Toolbar
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 4
                    spacing: 8

                    MD.EmbedChip {
                        id: sortChip
                        text: root.sortOptions[root.sortIndex].name
                        trailingIconName: root.sortAsc ? MD.Token.icon.arrow_downward
                                                       : MD.Token.icon.arrow_upward
                        mdState.borderWidth: 1
                        onClicked: sortMenu.open()

                        MD.Menu {
                            id: sortMenu
                            parent: sortChip
                            y: parent.height
                            model: root.sortOptions
                            contentDelegate: MD.MenuItem {
                                required property var modelData
                                required property int index
                                text: modelData.name
                                icon.name: index === root.sortIndex
                                    ? (root.sortAsc ? MD.Token.icon.arrow_downward
                                                    : MD.Token.icon.arrow_upward)
                                    : ' '
                                onClicked: {
                                    root.pickSort(index);
                                    sortMenu.close();
                                }
                            }
                        }
                    }

                    // Free-text search → wallpaperQuery.searchText.
                    // SearchChip debounces internally so this fires
                    // ~200ms after the user stops typing. Daemon-side
                    // the value becomes an extra `name CONTAINS`
                    // filter rule in its own group.
                    W.SearchChip {
                        id: m_search_field
                        Layout.preferredWidth: 120
                        placeholderText: qsTr("Search")
                        onTextEdited: wallpaperQuery.searchText = text
                    }

                    MD.ActionToolBar {
                        id: wallpaperActionToolBar
                        Layout.fillWidth: true
                        actions: [
                            playlistListAction,
                            tweakAction,
                            filterAction,
                            sourcesAction,
                            refreshAction
                        ]
                    }
                }

                // Horizontal scan-progress strip below the toolbar.
                // Only shown when the grid has wallpapers to display
                // (the empty-state path uses the centered BusyIndicator).
                MD.LinearIndicator {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 4
                    visible: m_grid_view.count > 0 && W.Notify.scanInProgress
                    running: visible
                }

                // Grid + centered empty-state overlay
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    MD.VerticalGridView {
                        id: m_grid_view
                        anchors.fill: parent
                        clip: true
                        focus: true
                        focusPolicy: Qt.StrongFocus
                        keyNavigationEnabled: true
                        keyNavigationWraps: true
                        currentIndex: -1
                        highlightRangeMode: GridView.NoHighlightRange
                        cacheBuffer: 300
                        displayMarginBeginning: 300
                        displayMarginEnd: 300
                        topMargin: 2
                        bottomMargin: root.selectionActionSheetActive ? root.selectionSheetReserve : 8
                        leftMargin: 8
                        rightMargin: 8
                        visible: m_grid_view.count > 0

                        readonly property real _availableWidth:
                            Math.max(0, width - leftMargin - rightMargin)
                        readonly property int _cols:
                            Math.max(1, Math.floor(_availableWidth / root.wallpaperItemSize))
                        readonly property real _stretchedItemWidth:
                            _availableWidth / _cols
                        readonly property bool _fillCell:
                            root.wallpaperItemLayoutMode === root.wallpaperItemLayoutFillCell
                        readonly property real _displayItemWidth: _fillCell
                            ? _stretchedItemWidth
                            : Math.min(root.wallpaperItemSize, _stretchedItemWidth)
                        readonly property real _displayItemHeight: _displayItemWidth
                            / Math.max(root.wallpaperItemAspectRatio, 0.1)
                        cellWidth: _stretchedItemWidth
                        cellHeight: _fillCell ? _displayItemHeight : root.wallpaperItemHeight

                        model: wallpaperQuery.data

                        delegate: WallpaperCard {
                            selected: model.selected ?? false
                            itemWidth: m_grid_view._displayItemWidth
                            itemHeight: m_grid_view._displayItemHeight
                            onClicked: modifiers => root.handleWallpaperClick(index, modifiers)
                            onSelectionRequested: modifiers => root.requestWallpaperSelection(index)
                        }

                        Keys.onEscapePressed: event => {
                            if (root.selectionActive) {
                                root.clearWallpaperSelection();
                                event.accepted = true;
                            }
                        }

                        highlightFollowsCurrentItem: true
                        highlight: Component {
                            Item {
                                visible: m_grid_view.currentItem !== null
                                z: 2
                                // Inset 2 = 6 (card margin) − 4 (ring outset),
                                // so the ring sits 4px outside the image
                                // control with the same concentric radius.
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    color: "transparent"
                                    border.color: MD.Token.color.primary
                                    border.width: 3
                                    radius: MD.Token.shape.corner.extra_small + 4
                                }
                            }
                        }
                    }

                    MD.Button {
                        id: cancelSelectionButton
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 16
                        anchors.topMargin: 12
                        z: 10
                        visible: root.selectionActive
                        checked: true
                        text: String(root.selectedWallpaperCount)
                        icon.name: MD.Token.icon.close
                        mdState.type: MD.Enum.BtElevated
                        onClicked: root.clearWallpaperSelection()
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 16
                        // Wait for the initial list query to settle before
                        // committing to the empty state — otherwise a
                        // brand-new user (empty DB, no libraries) sees a
                        // BusyIndicator flash from the in-flight fetch
                        // even though the daemon isn't scanning anything.
                        visible: m_grid_view.count === 0

                        // Daemon-side scan activity only. The list-fetch
                        // round-trip is a different concern and is gated
                        // by `visible` above.
                        readonly property bool scanning: W.Notify.scanInProgress

                        MD.BusyIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            visible: parent.scanning
                            running: visible
                        }

                        MD.Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !parent.scanning
                            text: "No wallpapers found"
                            typescale: MD.Token.typescale.body_large
                            color: MD.Token.color.on_surface_variant
                        }

                        MD.BusyButton {
                            Layout.alignment: Qt.AlignHCenter
                            // Only offer auto-detect when the empty grid is
                            // genuinely "fresh user, nothing configured" —
                            // not when filters are excluding existing rows
                            // and not when libraries are already registered
                            // (in that case the user wants Refresh, not a
                            // second round of auto-detection).
                            visible: !parent.scanning
                                  && root.filterRuleCount === 0
                                  && W.App.libraryManager.count === 0
                            text: "Auto detect libraries"
                            busy: autoDetectQuery.querying
                            mdState.type: MD.Enum.BtFilledTonal
                            onClicked: {
                                if (!busy) autoDetectQuery.reload();
                            }
                        }
                    }
                }
            }
        }

        // --- Right: wallpaper detail panel ---
        MD.Pane {
            Layout.preferredWidth: root.selectedWallpaper !== null && !root.selectionActive ? 280 : 0
            Layout.fillHeight: true
            Layout.maximumWidth: 280
            visible: root.selectedWallpaper !== null && !root.selectionActive
            radius: root.MD.MProp.page.backgroundRadius
            padding: 0
            showBackground: true

            contentItem: ColumnLayout {
                spacing: 0

                // Per-wallpaper user-property edits feed the daemon
                // through a single reused query — propertyKey/value
                // are rewritten on each flush.
                W.WallpaperPropertySetQuery {
                    id: setQuery
                    wallpaperId: root.selectedWallpaper?.id_proto ?? ""
                }

                W.UserPropertyListModel {
                    id: userPropModel
                    schemaJson: wallpaperGetQuery.wallpaper?.userPropertiesSchema ?? ""
                    overridesJson: wallpaperGetQuery.wallpaper?.userPropertyOverrides ?? ""
                }

                // Wire-side write buffer. The model emits one
                // `valueChanged` per user edit; we accumulate the latest
                // per key here and only fire the daemon RPC after the
                // user stops touching things for 200ms.
                QtObject {
                    id: m_pending_writes
                    property var entries: ({})
                }

                Qml.Timer {
                    id: m_flush_timer
                    interval: 200
                    repeat: false
                    onTriggered: {
                        const e = m_pending_writes.entries;
                        for (const k in e) {
                            setQuery.propertyKey = k;
                            setQuery.propertyValue = e[k];
                            setQuery.reload();
                        }
                        m_pending_writes.entries = {};
                    }
                }

                Connections {
                    target: userPropModel
                    function onValueChanged(key, value) {
                        const e = m_pending_writes.entries;
                        e[key] = value;
                        m_pending_writes.entries = e;
                        m_flush_timer.restart();
                    }
                }

                MD.VerticalListView {
                    id: m_detail_view
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: userPropModel
                    spacing: 8
                    leftMargin: 16
                    rightMargin: 16
                    topMargin: 0
                    bottomMargin: 8

                    header: ColumnLayout {
                        width: m_detail_view.contentWidth
                        spacing: 12

                        // Preview
                        W.ThumbnailImage {
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 200 : 0
                            Layout.topMargin: 12
                            visible: (root.selectedWallpaper?.preview ?? "") !== ""
                                     || (["video", "image"].indexOf(root.selectedWallpaper?.wpType ?? "") >= 0
                                         && (root.selectedWallpaper?.resource ?? "") !== "")
                            source  : root.selectedWallpaper?.preview ?? ""
                            resource: root.selectedWallpaper?.resource ?? ""
                            wpType  : root.selectedWallpaper?.wpType ?? ""
                            fillMode: Image.PreserveAspectFit
                        }

                        MD.Text {
                            Layout.fillWidth: true
                            text: root.selectedWallpaper?.name || "Untitled"
                            typescale: MD.Token.typescale.title_large
                            color: MD.Token.color.on_surface
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        // Type
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MD.Text {
                                Layout.fillWidth: true
                                text: root.selectedWallpaper?.wpType || ""
                                typescale: MD.Token.typescale.label_large
                                color: MD.Token.color.on_surface_variant
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            MD.ActionToolBar {
                                actions: [openContainerFolderDetailAction, infoDetailAction, closeDetailAction]
                                iconDelegate: MD.SmallIconButton {
                                    action: MD.ToolBarLayout.action
                                }
                            }
                        }

                        // Flat key/value grid. Each row hides itself
                        // when the value is unknown so missing fields
                        // collapse out of the layout.
                        GridLayout {
                            id: m_meta
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 4

                            // qtprotobuf marks int64 Q_PROPERTYs as
                            // SCRIPTABLE false, so `wallpaper.size` is
                            // undefined from QML. Read it via the model's
                            // C++ helper instead.
                            readonly property real sizeBytes: wallpaperQuery.data && root.selectedWallpaper
                                                              ? wallpaperQuery.data.sizeOf(root.selectedWallpaper)
                                                              : 0
                            readonly property bool hasPath: (root.selectedWallpaper?.resource ?? "") !== ""
                            readonly property bool hasResolution: Number(root.selectedWallpaper?.width ?? 0) > 0 && Number(root.selectedWallpaper?.height ?? 0) > 0
                            readonly property bool hasSize: sizeBytes > 0
                            readonly property bool hasFormat: (root.selectedWallpaper?.format ?? "") !== ""

                            function shortPath(p) {
                                const parts = (p || "").split("/").filter(s => s.length > 0);
                                return parts.slice(-2).join("/");
                            }
                            function formatSize(b) {
                                let v = Number(b ?? 0);
                                if (!(v > 0)) return "";
                                const u = ["B", "KB", "MB", "GB", "TB"];
                                let i = 0;
                                while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
                                return v.toFixed(i === 0 ? 0 : 1) + " " + u[i];
                            }

                            // Path
                            MD.Text {
                                visible: m_meta.hasPath
                                text: "Path"
                                typescale: MD.Token.typescale.label_medium
                                color: MD.Token.color.on_surface_variant
                            }
                            MD.Text {
                                visible: m_meta.hasPath
                                Layout.fillWidth: true
                                text: m_meta.shortPath(root.selectedWallpaper?.resource)
                                typescale: MD.Token.typescale.body_medium
                                color: MD.Token.color.on_surface
                                elide: Text.ElideMiddle
                                maximumLineCount: 1
                                wrapMode: Text.NoWrap
                            }

                            // Resolution
                            MD.Text {
                                visible: m_meta.hasResolution
                                text: "Resolution"
                                typescale: MD.Token.typescale.label_medium
                                color: MD.Token.color.on_surface_variant
                            }
                            MD.Text {
                                visible: m_meta.hasResolution
                                text: (root.selectedWallpaper?.width ?? 0) + "×" + (root.selectedWallpaper?.height ?? 0)
                                typescale: MD.Token.typescale.body_medium
                                color: MD.Token.color.on_surface
                            }

                            // Size
                            MD.Text {
                                visible: m_meta.hasSize
                                text: "Size"
                                typescale: MD.Token.typescale.label_medium
                                color: MD.Token.color.on_surface_variant
                            }
                            MD.Text {
                                visible: m_meta.hasSize
                                text: m_meta.formatSize(m_meta.sizeBytes)
                                typescale: MD.Token.typescale.body_medium
                                color: MD.Token.color.on_surface
                            }

                            // Format
                            MD.Text {
                                visible: m_meta.hasFormat
                                text: "Format"
                                typescale: MD.Token.typescale.label_medium
                                color: MD.Token.color.on_surface_variant
                            }
                            MD.Text {
                                visible: m_meta.hasFormat
                                text: (root.selectedWallpaper?.format ?? "").toLowerCase()
                                typescale: MD.Token.typescale.body_medium
                                color: MD.Token.color.on_surface
                            }
                        }

                        // Tags. Sourced from the per-item query
                        // (wallpaperGetQuery) so the panel reflects DB
                        // edits even if the list page is stale.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: (wallpaperGetQuery.wallpaper?.tags?.length ?? 0) > 0
                            Repeater {
                                model: wallpaperGetQuery.wallpaper?.tags ?? []
                                delegate: MD.AssistChip {
                                    required property string modelData
                                    text: modelData
                                }
                            }
                        }

                        // Description (project.json `description`) — collapsed
                        // to a fixed line count by default; user clicks the
                        // chevron to expand. Source string is Steam Workshop
                        // BBCode + bare URLs + `\n` line breaks; the C++
                        // `W.Util.bbcodeToHtml` helper converts it to the
                        // Qt.StyledText HTML subset before display.
                        ColumnLayout {
                            id: m_description
                            Layout.fillWidth: true
                            spacing: 4
                            visible: (wallpaperGetQuery.wallpaper?.description ?? "") !== ""

                            property bool expanded: false
                            // Collapsed view shows 3 lines; expanded shows all.
                            readonly property int collapsedLines: 3

                            MD.Divider {
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                MD.Text {
                                    Layout.fillWidth: true
                                    text: "Description"
                                    typescale: MD.Token.typescale.label_large
                                    color: MD.Token.color.on_surface_variant
                                }

                                MD.IconButton {
                                    icon.name: m_description.expanded ? MD.Token.icon.expand_less
                                                                       : MD.Token.icon.expand_more
                                    visible: m_descText.lineCount > m_description.collapsedLines
                                          || m_description.expanded
                                    onClicked: m_description.expanded = !m_description.expanded
                                }
                            }

                            MD.Text {
                                id: m_descText
                                Layout.fillWidth: true
                                text: W.Util.bbcodeToHtml(
                                    wallpaperGetQuery.wallpaper?.description ?? "")
                                textFormat: Text.StyledText
                                typescale: MD.Token.typescale.body_medium
                                color: MD.Token.color.on_surface
                                wrapMode: Text.WordWrap
                                maximumLineCount: m_description.expanded
                                                  ? Number.MAX_SAFE_INTEGER
                                                  : m_description.collapsedLines
                                elide: m_description.expanded ? Text.ElideNone
                                                              : Text.ElideRight
                                onLinkActivated: link => MD.Util.openUrlExternally(link)
                            }
                        }

                        // "Properties" section header — sits inside the
                        // ListView's `header` so the title hides cleanly
                        // when the model is empty.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: userPropModel.count > 0

                            MD.Divider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                MD.Text {
                                    Layout.fillWidth: true
                                    text: "Properties"
                                    typescale: MD.Token.typescale.label_large
                                    color: MD.Token.color.on_surface_variant
                                }

                                MD.IconButton {
                                    icon.name: MD.Token.icon.restart_alt
                                    mdState.size: MD.Enum.XS
                                    onClicked: userPropModel.resetAll()

                                    MD.ToolTip {
                                        visible: parent.hovered
                                        text: "Reset to defaults"
                                    }
                                }
                            }
                        }
                    }

                    // Per-property delegate. owe-supported types
                    // (color / slider / bool / combo) draw their native editor;
                    // anything else is a disabled label so the user
                    // knows the property exists.
                    delegate: ColumnLayout {
                        id: m_prop_delegate
                        required property string key
                        required property string label
                        required property string type
                        required property bool   supported
                        required property real   minVal
                        required property real   maxVal
                        required property string currentValue
                        required property bool   hasAlpha
                        required property var    optionLabels
                        required property var    optionValues

                        width: ListView.view ? (ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin) : 0
                        spacing: 2

                        function optionIndex(value) {
                            const values = m_prop_delegate.optionValues || [];
                            for (let i = 0; i < values.length; ++i) {
                                if (String(values[i]) === String(value))
                                    return i;
                            }
                            return 0;
                        }

                        MD.Text {
                            text: m_prop_delegate.label
                            textFormat: Text.StyledText
                            typescale: MD.Token.typescale.label_medium
                            color: MD.Token.color.on_surface
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            onLinkActivated: link => MD.Util.openUrlExternally(link)
                        }

                        // Bool → switch.
                        // Plain `checked: …` bindings get severed the first
                        // time the control writes its own state (Switch
                        // toggle on click, Slider drag, ColorPicker accept).
                        // Use Binding so model-driven changes (esp. Reset)
                        // still flow back into the control afterwards.
                        MD.Switch {
                            id: m_switch
                            visible: m_prop_delegate.type === "bool"
                            onToggled: userPropModel.setValue(m_prop_delegate.key,
                                                              checked ? "true" : "false")
                        }
                        Binding {
                            target: m_switch
                            property: "checked"
                            value: m_prop_delegate.currentValue === "true"
                        }

                        // Slider → MD.Slider with right-aligned readout
                        RowLayout {
                            visible: m_prop_delegate.type === "slider"
                            Layout.fillWidth: true
                            spacing: 8
                            MD.Slider {
                                id: m_slider
                                Layout.fillWidth: true
                                from: m_prop_delegate.minVal
                                to:   m_prop_delegate.maxVal
                                onMoved: userPropModel.setValue(m_prop_delegate.key, String(value))
                            }
                            MD.Text {
                                text: Number(m_prop_delegate.currentValue).toFixed(3)
                                typescale: MD.Token.typescale.body_small
                                color: MD.Token.color.on_surface_variant
                                Layout.preferredWidth: 56
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        Binding {
                            target: m_slider
                            property: "value"
                            value: Number(m_prop_delegate.currentValue)
                        }

                        // Color → MD.ColorPickerButton; alpha surfaces
                        // only when the wire value already had 4 floats
                        // (WE almost always emits RGB).
                        MD.ColorPickerButton {
                            id: m_color
                            visible: m_prop_delegate.type === "color"
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 32
                            showAlpha: m_prop_delegate.hasAlpha
                            onAccepted: c => userPropModel.setValue(
                                m_prop_delegate.key,
                                W.Util.colorToWire(c, showAlpha))
                        }
                        Binding {
                            target: m_color
                            property: "color"
                            value: W.Util.colorFromWire(m_prop_delegate.currentValue)
                        }

                        // Combo → dropdown using WE option labels, writing
                        // the original option value back to the renderer.
                        MD.ComboBox {
                            id: m_combo
                            visible: m_prop_delegate.type === "combo" && m_prop_delegate.supported
                            Layout.fillWidth: true
                            model: m_prop_delegate.optionLabels || []
                            onActivated: idx => {
                                const values = m_prop_delegate.optionValues || [];
                                if (idx >= 0 && idx < values.length)
                                    userPropModel.setValue(m_prop_delegate.key, String(values[idx]));
                            }
                        }
                        Binding {
                            target: m_combo
                            property: "currentIndex"
                            value: m_prop_delegate.optionIndex(m_prop_delegate.currentValue)
                        }

                        // Unsupported owe types: disabled row so users see
                        // the property exists, but editing is a no-op.
                        MD.Text {
                            visible: !m_prop_delegate.supported
                            text: "(" + m_prop_delegate.type + " — not yet supported)"
                            typescale: MD.Token.typescale.body_small
                            color: MD.Token.color.on_surface_variant
                        }
                    }
                }

                // Footer: pinned outside the Flickable so the Apply controls
                // — including target / renderer selectors — stay visible
                // regardless of how far the detail content scrolls.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    spacing: 8

                    // Apply target — chip row over DisplayManager.displays
                    // plus a leading "All" chip. Multi-select; empty
                    // selection ⇒ "All" (applied to every display).
                    // Resolution / FPS are resolved daemon-side from
                    // plugin settings, not configured here.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: (W.App.displayManager.displays || []).length > 0

                        MD.Text {
                            text: "Apply to"
                            typescale: MD.Token.typescale.label_medium
                            color: MD.Token.color.on_surface_variant
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            MD.FilterChip {
                                text: "All"
                                checked: root.isTargetAll()
                                onClicked: root.applyTargetIds = []
                            }

                            Repeater {
                                model: W.App.displayManager.displays

                                MD.FilterChip {
                                    required property var modelData
                                    text: (modelData?.displayLabel ?? "") || (modelData?.name ?? "").replace(/^waywallen-[a-z]+-[a-z]+-/, "") || ("Display " + modelData?.id)
                                    checked: root.applyTargetIds.indexOf(modelData?.id) >= 0
                                    onClicked: root.toggleTarget(modelData?.id)
                                }
                            }
                        }
                    }

                    // Renderer pick — only shown when the wallpaper
                    // type has more than one registered renderer.
                    // Single-select chip row; defaults to the highest-
                    // priority candidate (index 0).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.rendererCandidates.length >= 2

                        MD.Text {
                            text: "Renderer"
                            typescale: MD.Token.typescale.label_medium
                            color: MD.Token.color.on_surface_variant
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.rendererCandidates

                                MD.FilterChip {
                                    required property var modelData
                                    required property int index
                                    text: modelData?.name || ""
                                    checked: root.rendererIndex === index
                                    onClicked: root.rendererIndex = index
                                }
                            }
                        }
                    }

                    // Apply button — backed by either applyAction (the
                    // renderer/router path) or applyViaPortalAction (the
                    // xdg-desktop-portal fallback for image wallpapers
                    // when no display is registered). The active action
                    // owns text + busy + enabled + onTriggered.
                    MD.BusyButton {
                        id: applyBtn
                        Layout.fillWidth: true
                        action: root.activeApplyAction
                        mdState.type: MD.Enum.BtFilled

                        MD.ToolTip {
                            visible: applyBtn.hovered && !applyBtn.enabled
                            text: "No display connected"
                        }
                    }

                    // Status
                    RowLayout {
                        visible: applyQuery.status === 3
                        spacing: 8

                        MD.Icon {
                            name: MD.Token.icon.check
                            size: 20
                            color: MD.Token.color.primary
                        }
                        MD.Text {
                            text: "Applied"
                            typescale: MD.Token.typescale.label_large
                            color: MD.Token.color.primary
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wallpaperSelectSheetComponent

        MD.BottomSheet {
            id: wallpaperSelectSheetObject

            parent: root
            anchors.fill: parent
            z: 20
            sheetType: MD.Enum.BottomSheetStandard
            dim: false
            dismissOnDragDown: false
            collapsedHeight: 48

            onClosed: root.releaseWallpaperSelectSheet(wallpaperSelectSheetObject)

            ColumnLayout {
                width: wallpaperSelectSheetObject.sheetWidth
                spacing: 0

                MD.SheetActionBar {
                    Layout.fillWidth: true
                    delegateWidth: 88
                    actions: root.currentWallpaperSelect
                        ? (root.currentWallpaperSelect.actions || [])
                        : []
                }

                MD.Divider {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    visible: wallpaperSelectSheetRelay.currentComponent !== null
                }

                Loader {
                    Layout.fillWidth: true
                    visible: wallpaperSelectSheetRelay.currentComponent !== null
                    sourceComponent: visible ? wallpaperSelectSheetRelay.currentComponent : null
                }
            }
        }
    }

    Component {
        id: playlistSelectDetailComponent

        PlaylistDetailPanel {
            width: parent ? parent.width : implicitWidth
            playlist: playlistWallpaperSelect.playlistEditTarget
            mutation: playlistDetailMutation
        }
    }

    Component {
        id: newPlaylistSheetComponent

        ColumnLayout {
            width: parent ? parent.width : implicitWidth
            Layout.fillWidth: true
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                spacing: 8

                MD.Text {
                    Layout.fillWidth: true
                    text: qsTr("New playlist")
                    typescale: MD.Token.typescale.title_medium
                    color: MD.Token.color.on_surface
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                MD.TextField {
                    id: newPlaylistNameField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Name")
                    onAccepted: if (createPlaylistButton.enabled) root.createPlaylistFromSelection(text)
                }

                MD.BusyButton {
                    id: createPlaylistButton
                    Layout.fillWidth: true
                    text: qsTr("Create")
                    icon.name: MD.Token.icon.playlist_add
                    busy: playlistMutation.querying
                    enabled: root.selectedWallpaperCount > 0 && !playlistMutation.querying
                    mdState.type: MD.Enum.BtFilled
                    onClicked: root.createPlaylistFromSelection(newPlaylistNameField.text)
                }
            }
        }
    }

    Component {
        id: addToPlaylistSheetComponent

        ColumnLayout {
            width: parent ? parent.width : implicitWidth
            Layout.fillWidth: true
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                spacing: 8

                MD.Text {
                    Layout.fillWidth: true
                    text: qsTr("Add to playlist")
                    typescale: MD.Token.typescale.title_medium
                    color: MD.Token.color.on_surface
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                MD.LinearIndicator {
                    Layout.fillWidth: true
                    visible: root.playlistListLoading
                    running: visible
                }

                MD.Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    visible: !root.playlistListLoading
                          && (playlistListQuery.playlists || []).length === 0
                    text: qsTr("No playlists found")
                    typescale: MD.Token.typescale.body_medium
                    color: MD.Token.color.on_surface_variant
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                MD.VerticalListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(260, Math.max(88, contentHeight + topMargin + bottomMargin))
                    visible: (playlistListQuery.playlists || []).length > 0
                    interactive: contentHeight + topMargin + bottomMargin > height
                    model: playlistListQuery.playlists || []
                    spacing: 6
                    leftMargin: 0
                    rightMargin: 0
                    topMargin: 0
                    bottomMargin: 0

                    delegate: MD.ListItem {
                        id: selectPlaylistItem

                        required property var modelData

                        width: ListView.view.contentWidth
                        radius: 12
                        text: modelData.name || qsTr("Untitled")
                        supportText: qsTr("%1 wallpapers").arg((modelData.entryIds || []).length)

                        trailing: MD.BusyIconButton {
                            enabled: root.selectedWallpaperCount > 0 && !playlistMutation.querying
                            busy: playlistMutation.querying
                            icon.name: MD.Token.icon.add
                            onClicked: root.addSelectionToPlaylist(selectPlaylistItem.modelData)

                            MD.ToolTip {
                                visible: parent.hovered
                                text: qsTr("Add selection")
                            }
                        }
                    }
                }
            }
        }
    }

    MD.BottomSheet {
        id: wallpaperTweakSheet
        parent: root
        anchors.fill: parent
        z: 25
        sheetType: MD.Enum.BottomSheetModal
        dim: false
        dismissOnDragDown: true
        maxSheetWidth: 560

        ColumnLayout {
            width: wallpaperTweakSheet.sheetWidth
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16
                spacing: 16

                MD.Text {
                    Layout.fillWidth: true
                    text: qsTr("Tweak")
                    typescale: MD.Token.typescale.title_medium
                    color: MD.Token.color.on_surface
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MD.Text {
                        Layout.fillWidth: true
                        text: qsTr("Aspect ratio")
                        typescale: MD.Token.typescale.label_medium
                        color: MD.Token.color.on_surface_variant
                    }

                    MD.SegmentedButtonGroup {
                        size: MD.Enum.XS

                        MD.SegmentedButton {
                            text: "1:1"
                            checked: Math.abs(root.wallpaperItemAspectRatio - 1) < 0.001
                            onClicked: root.setWallpaperItemAspectRatio(1)
                        }

                        MD.SegmentedButton {
                            text: "4:3"
                            checked: Math.abs(root.wallpaperItemAspectRatio - 4 / 3) < 0.001
                            onClicked: root.setWallpaperItemAspectRatio(4 / 3)
                        }

                        MD.SegmentedButton {
                            text: "16:9"
                            checked: Math.abs(root.wallpaperItemAspectRatio - 16 / 9) < 0.001
                            onClicked: root.setWallpaperItemAspectRatio(16 / 9)
                        }

                        MD.SegmentedButton {
                            text: "9:16"
                            checked: Math.abs(root.wallpaperItemAspectRatio - 9 / 16) < 0.001
                            onClicked: root.setWallpaperItemAspectRatio(9 / 16)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        MD.Text {
                            Layout.fillWidth: true
                            text: qsTr("Size")
                            typescale: MD.Token.typescale.label_medium
                            color: MD.Token.color.on_surface_variant
                        }

                        MD.Text {
                            text: qsTr("%1 px").arg(root.wallpaperItemSize)
                            typescale: MD.Token.typescale.label_medium
                            color: MD.Token.color.on_surface_variant
                        }
                    }

                    MD.Slider {
                        Layout.fillWidth: true
                        from: 112
                        to: 260
                        stepSize: 8
                        snapMode: T.Slider.SnapAlways
                        value: root.wallpaperItemSize
                        onMoved: root.wallpaperItemSize = Math.round(value / 8) * 8
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MD.Text {
                        Layout.fillWidth: true
                        text: qsTr("Fill mode")
                        typescale: MD.Token.typescale.label_medium
                        color: MD.Token.color.on_surface_variant
                    }

                    MD.SegmentedButtonGroup {
                        size: MD.Enum.XS

                        MD.SegmentedButton {
                            text: qsTr("Fill cell")
                            checked: root.wallpaperItemLayoutMode === root.wallpaperItemLayoutFillCell
                            onClicked: root.wallpaperItemLayoutMode = root.wallpaperItemLayoutFillCell
                        }

                        MD.SegmentedButton {
                            text: qsTr("Fixed")
                            checked: root.wallpaperItemLayoutMode === root.wallpaperItemLayoutFixed
                            onClicked: root.wallpaperItemLayoutMode = root.wallpaperItemLayoutFixed
                        }
                    }
                }
            }
        }
    }

    MD.BottomSheet {
        id: playlistListSheet
        parent: root
        anchors.fill: parent
        z: 30
        sheetType: MD.Enum.BottomSheetModal
        dismissOnDragDown: true
        maxSheetWidth: 560

        ColumnLayout {
            width: playlistListSheet.sheetWidth
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 8

                MD.Text {
                    Layout.fillWidth: true
                    text: qsTr("Playlists")
                    typescale: MD.Token.typescale.title_medium
                    color: MD.Token.color.on_surface
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                MD.EmbedChip {
                    id: playlistDisplayChip
                    text: root.selectedPlaylistDisplay()
                        ? root.displayLabel(root.selectedPlaylistDisplay())
                        : qsTr("No displays")
                    enabled: root.playlistPlayDisplays.length > 0
                    icon.name: MD.Token.icon.monitor
                    trailingIconName: MD.Token.icon.expand_more
                    mdState.borderWidth: 1
                    onClicked: playlistDisplayMenu.open()

                    MD.Menu {
                        id: playlistDisplayMenu
                        parent: playlistDisplayChip
                        y: parent.height
                        model: root.playlistPlayDisplays
                        contentDelegate: MD.MenuItem {
                            required property var modelData
                            text: root.displayLabel(modelData)
                            icon.name: String(modelData.id) === String(root.selectedPlaylistDisplayId())
                                ? MD.Token.icon.check
                                : " "
                            onClicked: {
                                root.playlistPlayDisplayId = modelData.id;
                                playlistDisplayMenu.close();
                            }
                        }
                    }
                }
            }

            MD.LinearIndicator {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 8
                visible: root.playlistListLoading
                running: visible
            }

            MD.Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                visible: !root.playlistListLoading
                      && (playlistListQuery.playlists || []).length === 0
                text: qsTr("No playlists found")
                typescale: MD.Token.typescale.body_large
                color: MD.Token.color.on_surface_variant
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            MD.VerticalListView {
                id: playlistSheetList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, Math.max(120, contentHeight + topMargin + bottomMargin))
                visible: (playlistListQuery.playlists || []).length > 0
                interactive: contentHeight + topMargin + bottomMargin > height
                model: playlistListQuery.playlists || []
                spacing: 6
                leftMargin: 16
                rightMargin: 16
                topMargin: 0
                bottomMargin: 16

                delegate: MD.ListItem {
                    id: playlistSheetItem
                    required property var modelData

                    width: ListView.view.contentWidth
                    radius: 12
                    text: modelData.name || qsTr("Untitled")
                    supportText: qsTr("%1 wallpapers").arg((modelData.entryIds || []).length)
                    heightMode: playingDisplayLabels.length > 0
                        ? MD.Enum.ListItemThreeLine
                        : MD.Enum.ListItemTwoLine
                    readonly property bool playingOnSelectedDisplay: root.playlistIsPlayingOnSelectedDisplay(modelData)
                    readonly property var playingDisplayLabels: root.playlistDisplayLabels(modelData)
                    mdState.backgroundColor: root.isEditingPlaylist(modelData)
                        ? MD.Token.color.primary_container
                        : MD.Token.color.surface_container

                    below: Item {
                        implicitHeight: tagFlow.visible ? tagFlow.implicitHeight + 6 : 0

                        Flow {
                            id: tagFlow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            spacing: 4
                            visible: playlistSheetItem.playingDisplayLabels.length > 0

                            Repeater {
                                model: playlistSheetItem.playingDisplayLabels

                                W.Tag {
                                    required property var modelData
                                    text: modelData
                                    bgColor: MD.Token.color.secondary_container
                                    fgColor: MD.Token.color.on_secondary_container
                                }
                            }
                        }
                    }

                    trailing: RowLayout {
                        spacing: 4

                        MD.BusyIconButton {
                            enabled: root.selectedPlaylistDisplay() !== null
                                  && !playlistPlaybackMutation.querying
                            busy: playlistPlaybackMutation.querying
                            icon.name: playlistSheetItem.playingOnSelectedDisplay
                                ? MD.Token.icon.pause
                                : MD.Token.icon.play_arrow
                            onClicked: root.togglePlaylistPlayback(playlistSheetItem.modelData)

                            MD.ToolTip {
                                visible: parent.hovered && !parent.enabled
                                text: qsTr("No displays")
                            }
                        }

                        MD.IconButton {
                            enabled: !playlistMutation.querying
                            icon.name: MD.Token.icon.edit
                            onClicked: root.editPlaylistSelection(playlistSheetItem.modelData)

                            MD.ToolTip {
                                visible: parent.hovered
                                text: qsTr("Edit selection")
                            }
                        }

                        MD.IconButton {
                            enabled: !playlistMutation.querying
                            icon.name: MD.Token.icon.delete
                            onClicked: root.deletePlaylist(playlistSheetItem.modelData)

                            MD.ToolTip {
                                visible: parent.hovered
                                text: qsTr("Delete playlist")
                            }
                        }
                    }
                }
            }
        }
    }
}
