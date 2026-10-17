// SPDX-FileCopyrightText: 2026 Lingmo OS Team
//
// SPDX-License-Identifier: GPL-3.0-or-later

// 非正式版本（Alpha/Beta）的桌面测试水印，正式版本不显示。
//
// KWin 脚本跑在 KWin 进程里，既没有文件读写能力，也访问不到系统总线上的
// dsg DConfig，所以版本信息与开关这样取：
//   * 版本号：会话总线 org.deepin.dde.SystemInfo1 的 OsBuild 属性，取值就是
//     /etc/os-version 里 [Version] OsBuild 的内容（构建号，例如 26a01）；
//   * 版本类型：按 base-files/debian/rules 里既有的派生规则由构建号得出
//     （含 a → Alpha，含 b → Beta，其余 → Release），与 os-release 里
//     VERSION_TYPE 的取值一致；
//   * 开关：kwinrc 的 [Script-watermark] WaterMark_Available，默认 Enabled。
// 任何一步取不到值都不显示水印。

import QtQuick
import QtQuick.Window
import org.kde.kwin 2.0 as KWinModule

Window {
    id: root

    // Lingmo 的 KWin 分支按窗口标题识别水印窗口：不进任务栏、不出现在
    // Alt-Tab 和多任务视图里，也不出现在窗口截图中。
    title: "deepin-watermark"

    flags: (Qt.FramelessWindowHint | Qt.WindowTransparentForInput
            | Qt.WindowDoesNotAcceptFocus | Qt.Tool | Qt.X11BypassWindowManagerHint)
    color: "transparent"
    visible: root.shown

    width: column.implicitWidth
    height: column.implicitHeight
    x: Screen.width - width - 16
    y: Screen.height - height - 16

    // 取到的构建号，拿不到时保持空串
    property string buildVersion: ""
    // 由构建号派生出的版本类型：Alpha / Beta / Release
    property string versionType: ""
    // 第一行文本：版本类型 + 版本号，例如 "Alpha 26a01"
    property string versionText: ""
    property bool shown: false

    // 重试次数：会话刚起来时服务可能还没导出对象
    property int retries: 0

    // 会显示水印的版本类型（白名单），以及正式版本类型（黑名单），
    // 两个列表都只写实际出现过的取值，不做模糊匹配。
    readonly property var nonReleaseTypes: ["Alpha", "Beta"]
    readonly property var releaseTypes: ["Release", "Stable", "Final", "正式"]

    // 多语言文案，跟随系统语言；至少覆盖 zh_CN / zh_TW / en
    readonly property var texts: ({
        "zh_CN": { "testingOnly": "此副本仅供测试" },
        "zh_TW": { "testingOnly": "此副本僅供測試" },
        "en": { "testingOnly": "This copy is for testing only" }
    })

    function language() {
        var name = String(Qt.locale().name).replace("-", "_")
        if (name.indexOf("zh_TW") === 0 || name.indexOf("zh_HK") === 0 || name.indexOf("zh_Hant") === 0) {
            return "zh_TW"
        }
        if (name.indexOf("zh") === 0) {
            return "zh_CN"
        }
        return "en"
    }

    property string testingOnlyText: root.texts[root.language()].testingOnly

    // base-files/debian/rules 的派生规则：构建号含 a → Alpha，含 b → Beta，
    // 其余（如 26R01、5.0.0）→ Release
    function derivedVersionType(build) {
        var value = String(build).toLowerCase()
        if (value.indexOf("a") !== -1) {
            return "Alpha"
        }
        if (value.indexOf("b") !== -1) {
            return "Beta"
        }
        return "Release"
    }

    // kwinrc 里的运行时开关，未配置时按启用处理
    function switchEnabled() {
        var value = KWin.readConfig("WaterMark_Available", "Enabled")
        if (value === undefined || value === null) {
            return true
        }
        var text = String(value).toLowerCase()
        return text === "enabled" || text === "true" || text === "1"
    }

    function refresh() {
        root.versionType = root.buildVersion === "" ? "" : root.derivedVersionType(root.buildVersion)
        var isNonRelease = root.nonReleaseTypes.indexOf(root.versionType) !== -1
        var isRelease = root.releaseTypes.indexOf(root.versionType) !== -1
        root.shown = root.switchEnabled()
                && root.buildVersion !== ""
                && isNonRelease
                && !isRelease
        root.versionText = root.versionType + " " + root.buildVersion
    }

    function reposition() {
        root.x = Screen.width - root.width - 16
        root.y = Screen.height - root.height - 16
    }

    KWinModule.DBusCall {
        id: buildCall
        service: "org.deepin.dde.SystemInfo1"
        path: "/org/deepin/dde/SystemInfo1"
        dbusInterface: "org.freedesktop.DBus.Properties"
        method: "Get"
        arguments: ["org.deepin.dde.SystemInfo1", "OsBuild"]

        onFinished: function(returnValue) {
            var value = ""
            if (returnValue !== undefined && returnValue !== null && returnValue.length > 0) {
                var raw = returnValue[0]
                value = (raw === undefined || raw === null) ? "" : String(raw)
            }
            root.buildVersion = value.trim()
            root.refresh()
        }

        onFailed: {
            root.buildVersion = ""
            root.refresh()
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.buildVersion === "" && root.retries < 6
        onTriggered: {
            root.retries += 1
            buildCall.call()
        }
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: 2

        Text {
            text: root.versionText
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: "#E0E0E0"
            opacity: 0.85
        }

        Text {
            text: root.testingOnlyText
            font.pixelSize: 9
            font.italic: true
            color: "#A0A0A0"
            opacity: 0.7
        }
    }

    Connections {
        target: Screen
        function onWidthChanged() {
            root.reposition()
        }
        function onHeightChanged() {
            root.reposition()
        }
    }

    Component.onCompleted: {
        root.refresh()
        buildCall.call()
    }
}
