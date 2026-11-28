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
    property var sourceKeyOptions: []
    property var targetKeyOptions: []
    property var mappings: []
    property string statusText: ""
    property bool saveSucceeded: false
    property bool macFunctionKeysOnFocus: false
    property bool disableMacCapsLock: false
    property bool macJapaneseInputKeys: true
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

    function keyIndex(options, code)
    {
        for (var i = 0; i < options.length; i++) {
            if (options[i].code === code) {
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

    function keyName(options, code)
    {
        var index = keyIndex(options, code)
        return options.length > 0 ? options[index].name : ""
    }

    function openKeyPicker(row, field, options, code, title)
    {
        keyPicker.mappingRow = row
        keyPicker.mappingField = field
        keyPicker.keyOptions = options
        keyPicker.selectedCode = code
        keyPicker.heading = title
        keyPicker.open()
    }

    KeyboardPicker {
        id: keyPicker
        parent: root
        property int mappingRow: -1
        property string mappingField: ""
        onKeySelected: root.updateMapping(mappingRow, mappingField, code)
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
        if (sourceKeyOptions.length === 0 || targetKeyOptions.length === 0) {
            return
        }

        mappings = mappings.concat([{
            "sourceKey": sourceKeyOptions[0].code,
            "sourceModifiers": 0,
            "targetKey": targetKeyOptions[0].code,
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
            "disableMacCapsLock": disableMacCapsLock,
            "macJapaneseInputKeys": macJapaneseInputKeys
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
        sourceKeyOptions = computerModel.keyboardMappingSourceKeys()
        targetKeyOptions = computerModel.keyboardMappingTargetKeys()
        mappings = computerModel.getKeyboardMappings(computerUuid)
        var hostSettings = computerModel.getHostKeyboardSettings(computerUuid)
        macFunctionKeysOnFocus = hostSettings.macFunctionKeysOnFocus
        disableMacCapsLock = hostSettings.disableMacCapsLock
        macJapaneseInputKeys = hostSettings.macJapaneseInputKeys
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
            text: qsTr("Map a Mac key or combination to a host key or combination. Source and target key choices are listed separately. Caps Lock mapped to a modifier uses a temporary macOS HID relay so it remains held until release and stays separate from other modifier mappings. The previous HID mapping is restored when streaming ends. Unmapped keys pass through unchanged.")
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

                        CheckBox {
                            visible: SystemProperties.isDarwin
                            hoverEnabled: true
                            text: qsTr("Use Mac Eisu/Kana keys for Japanese input")
                            checked: root.macJapaneseInputKeys
                            onCheckedChanged: root.macJapaneseInputKeys = checked

                            ToolTip.delay: 1000
                            ToolTip.timeout: 10000
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("While Moonlight is focused, Eisu/Kana will not change the Mac input source. Eisu is sent as the Windows Alphanumeric mode key and Kana as the Hiragana mode key, not Convert/Nonconvert.")
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
                                    text: qsTr("From")
                                    Layout.preferredWidth: 75
                                }

                                ComboBox {
                                    Layout.preferredWidth: 220
                                    model: root.sourceModifierOptions
                                    textRole: "name"
                                    Component.onCompleted: currentIndex = root.modifierIndex(root.sourceModifierOptions, mappingData.sourceModifiers)
                                    onActivated: root.updateMapping(rowIndex, "sourceModifiers", root.sourceModifierOptions[currentIndex].mask)
                                }

                                Button {
                                    Layout.fillWidth: true
                                    text: root.keyName(root.sourceKeyOptions, mappingData.sourceKey) + "  ▾"
                                    onClicked: root.openKeyPicker(rowIndex,
                                                                 "sourceKey",
                                                                 root.sourceKeyOptions,
                                                                 mappingData.sourceKey,
                                                                 qsTr("Select source key"))
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    text: qsTr("To")
                                    Layout.preferredWidth: 75
                                }

                                ComboBox {
                                    Layout.preferredWidth: 220
                                    model: root.targetModifierOptions
                                    textRole: "name"
                                    Component.onCompleted: currentIndex = root.modifierIndex(root.targetModifierOptions, mappingData.targetModifiers)
                                    onActivated: root.updateMapping(rowIndex, "targetModifiers", root.targetModifierOptions[currentIndex].mask)
                                }

                                Button {
                                    Layout.fillWidth: true
                                    text: root.keyName(root.targetKeyOptions, mappingData.targetKey) + "  ▾"
                                    onClicked: root.openKeyPicker(rowIndex,
                                                                 "targetKey",
                                                                 root.targetKeyOptions,
                                                                 mappingData.targetKey,
                                                                 qsTr("Select target key"))
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
