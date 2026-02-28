import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    property string currentDnsName: pluginApi ? pluginApi.tr("status.checking") : "Checking..."
    property string currentStatusDetail: pluginApi ? pluginApi.tr("status.probing") : "Probing network state..."
    property string currentIconName: "world"
    property string modeId: "unknown"
    property string currentDnsIp: ""
    property bool vpnConnected: false
    property bool blockyActive: false
    property bool mullvadBlocked: false
    property bool isChanging: false
    property bool isCustomDns: false
    property string activeProviderId: "unknown"
    property string lastError: ""

    readonly property var defaultProviders: [
        { id: "google", label: "Google", ip: "8.8.8.8 8.8.4.4", icon: "brand-google" },
        { id: "cloudflare", label: "Cloudflare", ip: "1.1.1.1 1.0.0.1", icon: "cloud" },
        { id: "opendns", label: "OpenDNS", ip: "208.67.222.222 208.67.220.220", icon: "world" },
        { id: "adguard", label: "AdGuard", ip: "94.140.14.14 94.140.15.15", icon: "shield-check" },
        { id: "quad9", label: "Quad9", ip: "9.9.9.9 149.112.112.112", icon: "shield" }
    ]

    readonly property string oscCommand: {
        var settings = pluginApi ? pluginApi.pluginSettings : null;
        var value = settings ? settings.oscCommand : null;
        if (value === undefined || value === null || String(value).trim() === "") {
            return "osc-mullvad";
        }
        return String(value).trim();
    }

    readonly property string stateScript: String(Qt.resolvedUrl("scripts/state.sh")).replace(/^file:\/\//, "")
    readonly property string actionScript: String(Qt.resolvedUrl("scripts/apply.sh")).replace(/^file:\/\//, "")

    function isValidIp(ip) {
        if (!ip || !/^(\d{1,3}\.){3}\d{1,3}$/.test(ip)) {
            return false;
        }
        var parts = ip.split(".");
        for (var i = 0; i < parts.length; ++i) {
            var num = parseInt(parts[i], 10);
            if (num < 0 || num > 255) {
                return false;
            }
        }
        return true;
    }

    function normalizeDnsList(value) {
        var parts = String(value === undefined || value === null ? "" : value).split(/[\s,]+/);
        var seen = {};
        var list = [];
        for (var i = 0; i < parts.length; ++i) {
            var item = parts[i].trim();
            if (!isValidIp(item) || seen[item]) {
                continue;
            }
            seen[item] = true;
            list.push(item);
        }
        list.sort();
        return list.join(" ");
    }

    function providerById(providerId) {
        for (var i = 0; i < defaultProviders.length; ++i) {
            if (defaultProviders[i].id === providerId) {
                return defaultProviders[i];
            }
        }
        return null;
    }

    function providerForDns(normalizedDns) {
        if (!normalizedDns) {
            return null;
        }
        for (var i = 0; i < defaultProviders.length; ++i) {
            if (normalizeDnsList(defaultProviders[i].ip) === normalizedDns) {
                return defaultProviders[i];
            }
        }
        return null;
    }

    function isLocalResolverOnly(normalizedDns) {
        if (!normalizedDns) {
            return true;
        }
        var parts = normalizedDns.split(/\s+/);
        if (!parts.length) {
            return true;
        }
        for (var i = 0; i < parts.length; ++i) {
            var ip = parts[i];
            if (!ip) {
                continue;
            }
            if (ip.indexOf("127.") === 0 || ip.indexOf("192.168.") === 0 || ip.indexOf("10.") === 0) {
                continue;
            }
            if (ip.indexOf("172.") === 0) {
                var octets = ip.split(".");
                var second = octets.length > 1 ? parseInt(octets[1], 10) : -1;
                if (second >= 16 && second <= 31) {
                    continue;
                }
            }
            return false;
        }
        return true;
    }

    function setModeProperties(id, label, detail, iconName, dnsValue, customFlag) {
        modeId = id;
        activeProviderId = id;
        currentDnsName = label;
        currentStatusDetail = detail;
        currentIconName = iconName;
        currentDnsIp = dnsValue;
        isCustomDns = customFlag;
    }

    function setUnknown(detail, keepError) {
        setModeProperties(
            "unknown",
            pluginApi ? pluginApi.tr("status.unknown") : "Unknown",
            detail || (pluginApi ? pluginApi.tr("status.unavailable") : "Unable to read state"),
            "alert-circle",
            "",
            false
        );
        vpnConnected = false;
        blockyActive = false;
        mullvadBlocked = false;
        if (!keepError) {
            lastError = "";
        }
    }

    function deriveState(data) {
        var dns = normalizeDnsList(data.dns || "");
        var autoDns = Boolean(data.auto_dns);

        vpnConnected = Boolean(data.vpn_connected);
        blockyActive = Boolean(data.blocky_active);
        mullvadBlocked = Boolean(data.blocked);

        if (mullvadBlocked) {
            setModeProperties("blocked", pluginApi ? pluginApi.tr("status.blocked") : "Blocked", pluginApi ? pluginApi.tr("status.blocked_detail") : "Mullvad device is blocked or revoked", "shield-x", dns, true);
            return;
        }

        if (vpnConnected && !blockyActive) {
            setModeProperties("mullvad", "Mullvad", pluginApi ? pluginApi.tr("status.mullvad_detail") : "VPN connected, Blocky stopped", "shield-lock", dns, true);
            return;
        }

        if (!vpnConnected && blockyActive) {
            setModeProperties("blocky", "Blocky", pluginApi ? pluginApi.tr("status.blocky_detail") : "Blocky DNS fallback active", "shield-check", dns, true);
            return;
        }

        if (vpnConnected && blockyActive) {
            setModeProperties("mixed", pluginApi ? pluginApi.tr("status.mixed") : "Mixed", pluginApi ? pluginApi.tr("status.mixed_detail") : "VPN and Blocky are active together", "shield-half", dns, true);
            return;
        }

        var provider = providerForDns(dns);
        if (provider) {
            setModeProperties(provider.id, provider.label, pluginApi ? pluginApi.tr("status.provider_detail") : "Custom DNS preset active", provider.icon, dns, true);
            return;
        }

        if (autoDns || !dns || isLocalResolverOnly(dns)) {
            setModeProperties("default", pluginApi ? pluginApi.tr("status.default") : "Default (ISP)", pluginApi ? pluginApi.tr("status.default_detail") : "NetworkManager auto DNS is active", "world", "", false);
            return;
        }

        setModeProperties("custom", pluginApi ? pluginApi.tr("status.custom", { ip: dns }) : ("Custom (" + dns + ")"), pluginApi ? pluginApi.tr("status.custom_detail") : "A custom DNS configuration is active", "server", dns, true);
    }

    function applyState(rawText) {
        var payload = String(rawText === undefined || rawText === null ? "" : rawText).trim();
        if (!payload) {
            setUnknown(pluginApi ? pluginApi.tr("status.empty") : "Empty status response", false);
            return;
        }

        try {
            deriveState(JSON.parse(payload));
            lastError = "";
        } catch (error) {
            setUnknown(pluginApi ? pluginApi.tr("status.invalid_response") : "Invalid backend response", true);
            lastError = String(error);
        }
    }

    function refreshState() {
        if (!isChanging) {
            checkProcess.running = true;
        }
    }

    function runAction(actionId) {
        if (isChanging) {
            return;
        }

        var cmd = [actionScript, oscCommand];
        if (actionId === "toggle" || actionId === "mullvad" || actionId === "blocky" || actionId === "repair" || actionId === "default") {
            cmd.push(actionId);
        } else if (String(actionId).indexOf("provider:") === 0) {
            var providerId = String(actionId).slice(9);
            var provider = providerById(providerId);
            if (!provider) {
                return;
            }
            cmd.push("provider");
            cmd.push(provider.ip);
        } else {
            return;
        }

        isChanging = true;
        lastError = "";
        currentDnsName = pluginApi ? pluginApi.tr("status.switching") : "Switching...";
        actionProcess.command = cmd;
        actionProcess.running = true;
    }

    function withCurrentScreenOrPrimary(callback) {
        if (!callback) {
            return;
        }

        if (pluginApi && pluginApi.withCurrentScreen) {
            pluginApi.withCurrentScreen(callback);
            return;
        }

        if (Quickshell.screens.length > 0) {
            callback(Quickshell.screens[0]);
        }
    }

    function openPanelUi() {
        withCurrentScreenOrPrimary(function(screen) {
            if (pluginApi && pluginApi.openPanel) {
                pluginApi.openPanel(screen, null);
            }
        });
    }

    function closePanelUi() {
        withCurrentScreenOrPrimary(function(screen) {
            if (pluginApi && pluginApi.closePanel) {
                pluginApi.closePanel(screen);
            }
        });
    }

    function togglePanelUi() {
        withCurrentScreenOrPrimary(function(screen) {
            if (pluginApi && pluginApi.togglePanel) {
                pluginApi.togglePanel(screen, null);
            }
        });
    }

    function openSettingsUi() {
        withCurrentScreenOrPrimary(function(screen) {
            if (pluginApi && pluginApi.manifest) {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            }
        });
    }

    function normalizeProviderShortcut(name) {
        var normalized = String(name === undefined || name === null ? "" : name).toLowerCase();
        normalized = normalized.replace(/[^a-z0-9]+/g, "");

        switch (normalized) {
        case "google":
            return "google";
        case "cloudflare":
            return "cloudflare";
        case "opendns":
        case "open":
            return "opendns";
        case "adguard":
            return "adguard";
        case "quad9":
        case "quad":
            return "quad9";
        case "default":
        case "isp":
        case "system":
        case "auto":
            return "default";
        default:
            return "";
        }
    }

    function runShortcut(name) {
        var normalized = normalizeProviderShortcut(name);
        if (!normalized) {
            return;
        }

        if (normalized === "default") {
            runAction("default");
            return;
        }

        runAction("provider:" + normalized);
    }

    IpcHandler {
        target: "plugin:ndns"

        function openPanel() {
            root.openPanelUi();
        }

        function closePanel() {
            root.closePanelUi();
        }

        function togglePanel() {
            root.togglePanelUi();
        }

        function panel() {
            root.togglePanelUi();
        }

        function openSettings() {
            root.openSettingsUi();
        }

        function toggle() {
            root.runAction("toggle");
        }

        function mullvad() {
            root.runAction("mullvad");
        }

        function blocky() {
            root.runAction("blocky");
        }

        function isp() {
            root.runAction("default");
        }

        function defaultDns() {
            root.runAction("default");
        }

        function repair() {
            root.runAction("repair");
        }

        function set(mode: string) {
            root.runShortcut(mode);
        }

        function provider(name: string) {
            root.runShortcut(name);
        }
    }

    Timer {
        interval: 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshState()
    }

    Process {
        id: checkProcess
        command: [root.stateScript]
        stdout: StdioCollector {
            id: checkStdout
            onTextChanged: root.applyState(text)
        }
        stderr: StdioCollector {
            id: checkStderr
        }
        onExited: function(code) {
            if (code !== 0) {
                root.setUnknown(pluginApi ? pluginApi.tr("status.command_failed") : "Status command failed", true);
                root.lastError = (checkStderr.text || "").trim() || (pluginApi ? pluginApi.tr("error.status_failed") : ("Status check failed (exit " + code + ")"));
            }
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            id: actionStdout
        }
        stderr: StdioCollector {
            id: actionStderr
        }
        onExited: function(code) {
            root.isChanging = false;
            if (code !== 0) {
                root.lastError = (actionStderr.text || actionStdout.text || "").trim();
                if (!root.lastError) {
                    root.lastError = pluginApi ? pluginApi.tr("error.apply_failed") : ("Action failed (exit " + code + ")");
                }
            }
            checkProcess.running = true;
        }
    }
}
