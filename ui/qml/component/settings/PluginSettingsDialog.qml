pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import Qcm.Material as MD
import waywallen.ui as W

// Schema-driven settings editor for one renderer plugin. The dialog
// owns its dirty buffer (`pendingValues`) so transient input never
// touches `currentValues` until the user hits Apply. Re-fetching from
// the daemon overwrites only entries the user has not edited, so a
// concurrent peer write can't clobber in-progress edits.
MD.Dialog {
    id: root
    parent: T.Overlay.overlay

    required property string pluginName
    // Array of schema dicts (verbatim from
    // RendererPluginInfo.settings, flattened in C++).
    required property var schemaList
    // {key: stringValue} as exposed by SettingsGetQuery —
    // *just this plugin's* current values.
    property var currentValues: ({})
    // Daemon's SettingsGet snapshot for *all* plugins. Required because
    // SettingsSet is full-replace: plugins absent from the request get
    // dropped. We forward everyone else verbatim so editing one plugin
    // doesn't wipe the rest.
    property var allCurrentPlugins: ({})
    // Likewise the global block is required so the daemon doesn't
    // reset defaultWidth/defaultHeight to zero on a single-plugin edit.
    property var currentGlobal: ({})

    // Local edit buffer keyed by setting `key`. Populated lazily as
    // controls emit `valueChanged`. Apply ships this merged with
    // `currentValues` (defaults filled in for any key the user never
    // touched).
    property var pendingValues: ({})

    title: "Configure " + pluginName
    standardButtons: T.Dialog.Cancel | T.Dialog.Ok

    signal applied

    width: Math.min(parent ? parent.width - 64 : 520, 640)
    height: Math.min(parent ? parent.height - 96 : 720, 720)

    W.SettingsSetQuery {
        id: setQuery
        // 2 = QAsyncResult::Status::Finished. Codebase uses raw ints
        // for status (see StatusPage / WallpaperPage); we follow suit
        // rather than reach for the Q_ENUM via QML.
        onStatusChanged: {
            if (status === 2) {
                root.applied();
                root.close();
            }
        }
    }

    // Bindings that read this function track `currentValues` and
    // `pendingValues` because we touch those properties in the body —
    // QML's binding analyzer picks them up. So a `syncCurrent` call
    // (peer/daemon push) re-runs every dependent field unless the
    // user has already overridden the key locally.
    function valueFor(key) {
        const pv = root.pendingValues;
        const cv = root.currentValues;
        if (key in pv)
            return pv[key];
        if (key in cv)
            return cv[key];
        for (let i = 0; i < root.schemaList.length; ++i) {
            const s = root.schemaList[i];
            if (s.key === key)
                return s.default_value;
        }
        return "";
    }

    // Refresh `currentValues` from a fresh SettingsGet; preserves any
    // in-flight pending edits so the user doesn't lose work to a peer
    // write (or to the daemon's own SettingsChanged echo of our own
    // SettingsSet).
    function syncCurrent(values) {
        root.currentValues = values || ({});
    }

    // Build {group: [schema...]} sorted by `order` ascending. Items
    // with no group land in "General".
    readonly property var groupedSchemas: {
        const buckets = {};
        for (let i = 0; i < schemaList.length; ++i) {
            const s = schemaList[i];
            const g = (s.group && s.group.length > 0) ? s.group : "General";
            if (!buckets[g])
                buckets[g] = [];
            buckets[g].push(s);
        }
        const keys = Object.keys(buckets).sort();
        const out = [];
        for (let i = 0; i < keys.length; ++i) {
            const k = keys[i];
            buckets[k].sort(function (a, b) {
                return (a.order || 0) - (b.order || 0);
            });
            out.push({
                "group": k,
                "items": buckets[k]
            });
        }
        return out;
    }

    contentItem: ColumnLayout {
        spacing: 12

        MD.Text {
            // 3 = QAsyncResult::Status::Error.
            visible: setQuery.status === 3
            Layout.fillWidth: true
            text: setQuery.error
            color: MD.Token.color.error
            typescale: MD.Token.typescale.body_small
            wrapMode: Text.WordWrap
        }

        MD.Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: contentHeight
            contentHeight: groupsCol.implicitHeight

            ColumnLayout {
                id: groupsCol
                width: parent.width
                spacing: 16

                Repeater {
                    model: root.groupedSchemas

                    delegate: ColumnLayout {
                        id: groupItem
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        MD.Text {
                            text: groupItem.modelData.group
                            typescale: MD.Token.typescale.title_small
                            color: MD.Token.color.on_surface_variant
                        }

                        Repeater {
                            model: groupItem.modelData.items
                            delegate: SettingField {
                                required property var modelData
                                Layout.fillWidth: true
                                schema: modelData
                                value: root.valueFor(modelData.key)
                                onCommitted: function (key, newValue) {
                                    const next = Object.assign({}, root.pendingValues);
                                    next[key] = newValue;
                                    root.pendingValues = next;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    onAccepted: {
        // Compose the final per-plugin values: defaults for any key the
        // user (or daemon) hasn't set, then layer current and pending.
        const merged = ({});
        for (let i = 0; i < root.schemaList.length; ++i) {
            const s = root.schemaList[i];
            merged[s.key] = s.default_value;
        }
        for (const k in root.currentValues)
            merged[k] = root.currentValues[k];
        for (const k in root.pendingValues)
            merged[k] = root.pendingValues[k];

        // Full-replace semantics: forward every other plugin's values
        // unchanged, then overwrite our own with the merged buffer.
        const plugins = Object.assign({}, root.allCurrentPlugins);
        plugins[root.pluginName] = merged;
        setQuery.global = root.currentGlobal;
        setQuery.plugins = plugins;
        setQuery.reload();
    }

    onClosed: {
        pendingValues = ({});
        setQuery.setError("");
    }
}
