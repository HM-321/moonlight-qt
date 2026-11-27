import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import SystemProperties 1.0

Item {
    id: root
    objectName: qsTr("Keyboard Mapping")
    anchors.fill: parent

    property var computerModel
    property string computerUuid
    property string computerName
    property var keyOptions: []
    property var mappings: []
    property string statusText: ""
    property bool saveSucceeded: false
    property bool macFunctionKeysOnFocus: false
    property bool disableMacCapsLock: false
    property var sourceModifierOptions: makeModifierOptions(true)
    property var targetModifierOptions: makeModifierOptions(false)

    function makeModifierOptions(source)
    {
        var modifierNames = [
            "Ctrl",
            source ? "Option" : "Alt",
            "Shift",
            source ? "Command" : "Win"
        ]
        var options = [{ "name": qsTr("None"), "mask": 0 }]

        for (var mask = 1; mask < 16; mask++) {
            var names = []
            for (var bit = 0; bit < modifierNames.length; bit++) {
                if (mask & (1 << bit)) {
                    names.push(modifierNames[bit])
                }
            }
            options.push({ "name": names.join("+"), "mask": mask })
        }

        return options
    }

    function keyIndex(code)
    {
        for (var i = 0; i < keyOptions.length; i++) {
            if (keyOptions[i].code === code) {
                return i
            }
        }
        return 0
    }

    function modifierIndex(options, mask)
    {
        for (var i = 0; i < options.length; i++) {
            if (options[i].mask === mask) {
                return i
            }
        }
        return 0
    }

    function updateMapping(row, field, value)
    {
        var updated = mappings.slice()
        var mapping = {}
        for (var key in updated[row]) {
            mapping[key] = updated[row][key]
        }
        mapping[field] = value
        updated[row] = mapping
        mappings = updated
        statusText = ""
    }

    function addMapping()
    {
        if (keyOptions.length === 0) {
            return
        }

        var key = keyOptions[0].code
        mappings = mappings.concat([{
            "sourceKey": key,
            "sourceModifiers": 0,
            "targetKey": key,
            "targetModifiers": 0
        }])
    }

    function removeMapping(row)
    {
        var updated = mappings.slice()
        updated.splice(row, 1)
        mappings = updated
        statusText = ""
    }

    function saveMappings()
    {
        var hostSettings = {
            "macFunctionKeysOnFocus": macFunctionKeysOnFocus,
            "disableMacCapsLock": disableMacCapsLock
        }
        if (!computerModel.saveKeyboardConfiguration(computerUuid, mappings, hostSettings)) {
            statusText = qsTr("Could not save mappings. Each input shortcut must be unique.")
            saveSucceeded = false
            return
        }

        statusText = qsTr("Keyboard mappings saved.")
        saveSucceeded = true
    }

    Component.onCompleted: {
        keyOptions = computerModel.keyboardMappingKeys()
        mappings = computerModel.getKeyboardMappings(computerUuid)
        var hostSettings = computerModel.getHostKeyboardSettings(computerUuid)
        macFunctionKeysOnFocus = hostSettings.macFunctionKeysOnFocus
        disableMacCapsLock = hostSettings.disableMacCapsLock
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Label {
            text: qsTr("Keyboard mappings for %1").arg(root.computerName)
            font.pointSize: 20
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        Label {
            text: qsTr("Map any input key or combination to a Windows key or combination, including modifier keys. Unmapped keys pass through unchanged.")
            font.pointSize: 12
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: root.width - 48
                spacing: 8

                GroupBox {
                    visible: SystemProperties.isDarwin
                    Layout.fillWidth: true
                    title: qsTr("Host keyboard settings")

                    ColumnLayout {
                        anchors.fill: parent

                        CheckBox {
                            visible: SystemProperties.isDarwin
                            hoverEnabled: true
                            text: qsTr("Use standard function keys while streaming")
                            checked: root.macFunctionKeysOnFocus
                            onCheckedChanged: root.macFunctionKeysOnFocus = checked

                            ToolTip.delay: 1000
                            ToolTip.timeout: 10000
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Temporarily switches macOS to standard F1-F12 keys while the streaming window is focused. The previous mode is restored when focus leaves or the stream ends. Press Fn with a key to use its Mac function.")
                        }

                        CheckBox {
                            visible: SystemProperties.isDarwin
                            hoverEnabled: true
                            text: qsTr("Keep macOS Caps Lock off while streaming")
                            checked: root.disableMacCapsLock
                            onCheckedChanged: root.disableMacCapsLock = checked

                            ToolTip.delay: 1000
                            ToolTip.timeout: 10000
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Prevents Caps Lock from lighting on the Mac while this stream is focused. The key is still sent to the Windows host, and the previous Mac state is restored when focus leaves or the stream ends.")
                        }
                    }
                }

                Repeater {
                    model: root.mappings

                    delegate: GroupBox {
                        property int rowIndex: index
                        property var mappingData: modelData
                        Layout.fillWidth: true
                        title: qsTr("Mapping %1").arg(rowIndex + 1)

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    text: qsTr("When")
                                    Layout.preferredWidth: 75
                                }

                                ComboBox {
                                    Layout.preferredWidth: 220
                                    model: root.sourceModifierOptions
                                    textRole: "name"
                                    Component.onCompleted: currentIndex = root.modifierIndex(root.sourceModifierOptions, mappingData.sourceModifiers)
                                    onActivated: root.updateMapping(rowIndex, "sourceModifiers", root.sourceModifierOptions[currentIndex].mask)
                                }

                                ComboBox {
                                    Layout.fillWidth: true
                                    model: root.keyOptions
                                    textRole: "name"
                                    Component.onCompleted: currentIndex = root.keyIndex(mappingData.sourceKey)
                                    onActivated: root.updateMapping(rowIndex, "sourceKey", root.keyOptions[currentIndex].code)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    text: qsTr("Send as")
                                    Layout.preferredWidth: 75
                                }

                                ComboBox {
                                    Layout.preferredWidth: 220
                                    model: root.targetModifierOptions
                                    textRole: "name"
                                    Component.onCompleted: currentIndex = root.modifierIndex(root.targetModifierOptions, mappingData.targetModifiers)
                                    onActivated: root.updateMapping(rowIndex, "targetModifiers", root.targetModifierOptions[currentIndex].mask)
                                }

                                ComboBox {
                                    Layout.fillWidth: true
                                    model: root.keyOptions
                                    textRole: "name"
                                    Component.onCompleted: currentIndex = root.keyIndex(mappingData.targetKey)
                                    onActivated: root.updateMapping(rowIndex, "targetKey", root.keyOptions[currentIndex].code)
                                }

                                Button {
                                    text: qsTr("Remove")
                                    onClicked: root.removeMapping(rowIndex)
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: qsTr("Add Mapping")
                onClicked: root.addMapping()
            }

            Item {
                Layout.fillWidth: true
            }

            Label {
                text: root.statusText
                color: root.saveSucceeded ? "lightgreen" : "tomato"
                visible: root.statusText.length > 0
            }

            Button {
                text: qsTr("Save")
                onClicked: root.saveMappings()
            }
        }
    }
}
