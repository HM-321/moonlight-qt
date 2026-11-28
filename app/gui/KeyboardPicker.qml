import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

Dialog {
    id: picker
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.min(parent ? parent.width - 48 : 1240, 1240)
    height: Math.min(parent ? parent.height - 48 : 700, 700)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0

    property var keyOptions: []
    property int selectedCode: 0
    property string heading: qsTr("Select a key")
    signal keySelected(int code)

    title: heading
    standardButtons: Dialog.Cancel

    property var keyboardRows: [
        [41, -1, 58, 59, 60, 61, -1, 62, 63, 64, 65, -1, 66, 67, 68, 69],
        [53, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 45, 46, 42],
        [43, 20, 26, 8, 21, 23, 28, 24, 12, 18, 19, 47, 48, 49],
        [57, 4, 22, 7, 9, 10, 11, 13, 14, 15, 51, 52, 40],
        [225, 29, 27, 6, 25, 5, 17, 16, 54, 55, 56, 229],
        [224, 226, 227, 145, 44, 144, 231, 230, 228]
    ]

    function optionForCode(code)
    {
        for (var i = 0; i < keyOptions.length; i++) {
            if (keyOptions[i].code === code) {
                return keyOptions[i]
            }
        }
        return null
    }

    function fallbackName(code)
    {
        var names = {
            41: "Esc", 58: "F1", 59: "F2", 60: "F3", 61: "F4",
            62: "F5", 63: "F6", 64: "F7", 65: "F8", 66: "F9",
            67: "F10", 68: "F11", 69: "F12", 42: "Backspace",
            43: "Tab", 57: "Caps Lock", 40: "Enter", 225: "Left Shift",
            229: "Right Shift", 224: "Left Ctrl", 228: "Right Ctrl",
            226: "Left Option", 230: "Right Option", 227: "Left Command",
            231: "Right Command", 44: "Space", 144: "Kana", 145: "Eisu",
            73: "Insert", 74: "Home", 75: "Page Up", 76: "Delete",
            77: "End", 78: "Page Down", 80: "Left", 81: "Down",
            82: "Up", 79: "Right"
        }
        return names[code] || ""
    }

    function keyText(code)
    {
        if (code === 41) return "Esc"
        var option = optionForCode(code)
        return option ? option.name : fallbackName(code)
    }

    function keyWidth(code)
    {
        if (code === 44) return 250
        if (code === 42 || code === 43 || code === 57 || code === 40) return 112
        if (code === 225 || code === 229) return 132
        if (code === 227 || code === 231) return 126
        if (code === 224 || code === 226 || code === 228 || code === 230) return 112
        if (code === 144 || code === 145) return 105
        return 64
    }

    contentItem: ColumnLayout {
        spacing: 10

        Label {
            text: qsTr("Unavailable keys are dimmed. Key names follow the selected input or output side.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 8

                Repeater {
                model: picker.keyboardRows

                RowLayout {
                    spacing: 5
                    Layout.alignment: Qt.AlignHCenter
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16

                    Repeater {
                        model: modelData

                        Item {
                            property int keyCode: modelData
                            Layout.preferredWidth: keyCode < 0 ? 20 : picker.keyWidth(keyCode)
                            Layout.preferredHeight: 48

                            Button {
                                anchors.fill: parent
                                visible: parent.keyCode >= 0
                                text: picker.keyText(parent.keyCode)
                                enabled: picker.optionForCode(parent.keyCode) !== null
                                highlighted: parent.keyCode === picker.selectedCode
                                onClicked: {
                                    picker.keySelected(parent.keyCode)
                                    picker.close()
                                }
                            }
                        }
                    }
                }
            }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 12
                    spacing: 14

                    GridLayout {
                        columns: 3
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: [73, 74, 75, 76, 77, 78]
                            Button {
                                Layout.preferredWidth: 92
                                Layout.preferredHeight: 48
                                text: picker.keyText(modelData)
                                enabled: picker.optionForCode(modelData) !== null
                                highlighted: modelData === picker.selectedCode
                                onClicked: {
                                    picker.keySelected(modelData)
                                    picker.close()
                                }
                            }
                        }
                    }

                    GridLayout {
                        columns: 3
                        rowSpacing: 6
                        columnSpacing: 6

                        Item { Layout.preferredWidth: 68; Layout.preferredHeight: 48 }
                        Button {
                            Layout.preferredWidth: 68; Layout.preferredHeight: 48
                            text: picker.keyText(82); enabled: picker.optionForCode(82) !== null
                            highlighted: picker.selectedCode === 82
                            onClicked: { picker.keySelected(82); picker.close() }
                        }
                        Item { Layout.preferredWidth: 68; Layout.preferredHeight: 48 }
                        Button {
                            Layout.preferredWidth: 68; Layout.preferredHeight: 48
                            text: picker.keyText(80); enabled: picker.optionForCode(80) !== null
                            highlighted: picker.selectedCode === 80
                            onClicked: { picker.keySelected(80); picker.close() }
                        }
                        Button {
                            Layout.preferredWidth: 68; Layout.preferredHeight: 48
                            text: picker.keyText(81); enabled: picker.optionForCode(81) !== null
                            highlighted: picker.selectedCode === 81
                            onClicked: { picker.keySelected(81); picker.close() }
                        }
                        Button {
                            Layout.preferredWidth: 68; Layout.preferredHeight: 48
                            text: picker.keyText(79); enabled: picker.optionForCode(79) !== null
                            highlighted: picker.selectedCode === 79
                            onClicked: { picker.keySelected(79); picker.close() }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4

            Label { text: qsTr("Other supported keys") }

            ComboBox {
                id: otherKeys
                Layout.fillWidth: true
                model: picker.keyOptions
                textRole: "name"
                Component.onCompleted: currentIndex = picker.optionIndex(picker.selectedCode)
            }

            Button {
                text: qsTr("Select")
                enabled: otherKeys.currentIndex >= 0 && picker.keyOptions.length > 0
                onClicked: {
                    picker.keySelected(picker.keyOptions[otherKeys.currentIndex].code)
                    picker.close()
                }
            }
        }
    }

    function optionIndex(code)
    {
        for (var i = 0; i < keyOptions.length; i++) {
            if (keyOptions[i].code === code) return i
        }
        return 0
    }

    onOpened: otherKeys.currentIndex = optionIndex(selectedCode)
}
