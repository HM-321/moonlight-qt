#include "keyboardmapping.h"

#include <QDebug>
#include <QSet>
#include <QSettings>
#include <QVariantMap>

static QList<SDL_Scancode> supportedScancodes()
{
    QList<SDL_Scancode> scancodes;

    for (int scancode = SDL_SCANCODE_A; scancode <= SDL_SCANCODE_Z; scancode++) {
        scancodes.append(static_cast<SDL_Scancode>(scancode));
    }
    for (int scancode = SDL_SCANCODE_1; scancode <= SDL_SCANCODE_9; scancode++) {
        scancodes.append(static_cast<SDL_Scancode>(scancode));
    }
    scancodes.append(SDL_SCANCODE_0);

    for (int scancode = SDL_SCANCODE_F1; scancode <= SDL_SCANCODE_F12; scancode++) {
        scancodes.append(static_cast<SDL_Scancode>(scancode));
    }
    for (int scancode = SDL_SCANCODE_F13; scancode <= SDL_SCANCODE_F24; scancode++) {
        scancodes.append(static_cast<SDL_Scancode>(scancode));
    }
    for (int scancode = SDL_SCANCODE_KP_1; scancode <= SDL_SCANCODE_KP_9; scancode++) {
        scancodes.append(static_cast<SDL_Scancode>(scancode));
    }

    const SDL_Scancode specialScancodes[] = {
        SDL_SCANCODE_LCTRL, SDL_SCANCODE_LSHIFT, SDL_SCANCODE_LALT, SDL_SCANCODE_LGUI,
        SDL_SCANCODE_RCTRL, SDL_SCANCODE_RSHIFT, SDL_SCANCODE_RALT, SDL_SCANCODE_RGUI,
        SDL_SCANCODE_BACKSPACE, SDL_SCANCODE_TAB, SDL_SCANCODE_CLEAR,
        SDL_SCANCODE_KP_ENTER, SDL_SCANCODE_RETURN, SDL_SCANCODE_PAUSE,
        SDL_SCANCODE_CAPSLOCK, SDL_SCANCODE_ESCAPE, SDL_SCANCODE_SPACE,
        SDL_SCANCODE_PAGEUP, SDL_SCANCODE_PAGEDOWN, SDL_SCANCODE_END,
        SDL_SCANCODE_HOME, SDL_SCANCODE_LEFT, SDL_SCANCODE_UP,
        SDL_SCANCODE_RIGHT, SDL_SCANCODE_DOWN, SDL_SCANCODE_SELECT,
        SDL_SCANCODE_EXECUTE, SDL_SCANCODE_PRINTSCREEN, SDL_SCANCODE_INSERT,
        SDL_SCANCODE_DELETE, SDL_SCANCODE_HELP, SDL_SCANCODE_KP_0,
        SDL_SCANCODE_KP_MULTIPLY, SDL_SCANCODE_KP_PLUS, SDL_SCANCODE_KP_COMMA,
        SDL_SCANCODE_KP_MINUS, SDL_SCANCODE_KP_PERIOD, SDL_SCANCODE_KP_DIVIDE,
        SDL_SCANCODE_NUMLOCKCLEAR, SDL_SCANCODE_SCROLLLOCK, SDL_SCANCODE_APPLICATION,
        SDL_SCANCODE_AC_BACK, SDL_SCANCODE_AC_FORWARD, SDL_SCANCODE_AC_REFRESH,
        SDL_SCANCODE_AC_STOP, SDL_SCANCODE_AC_SEARCH, SDL_SCANCODE_AC_BOOKMARKS,
        SDL_SCANCODE_AC_HOME, SDL_SCANCODE_SEMICOLON, SDL_SCANCODE_EQUALS,
        SDL_SCANCODE_COMMA, SDL_SCANCODE_MINUS, SDL_SCANCODE_PERIOD,
        SDL_SCANCODE_SLASH, SDL_SCANCODE_GRAVE, SDL_SCANCODE_LEFTBRACKET,
        SDL_SCANCODE_BACKSLASH, SDL_SCANCODE_RIGHTBRACKET, SDL_SCANCODE_APOSTROPHE,
        SDL_SCANCODE_INTERNATIONAL1, SDL_SCANCODE_INTERNATIONAL3,
        SDL_SCANCODE_NONUSBACKSLASH, SDL_SCANCODE_LANG1, SDL_SCANCODE_LANG2
    };
    for (SDL_Scancode scancode : specialScancodes) {
        scancodes.append(scancode);
    }

    return scancodes;
}

QList<KeyboardMapping> KeyboardMappingStore::load(const QString& hostUuid)
{
    QList<KeyboardMapping> mappings;
    if (hostUuid.isEmpty()) {
        return mappings;
    }

    QSettings settings;
    settings.beginGroup(QStringLiteral("keyboardmappings"));
    settings.beginGroup(hostUuid);
    const int count = settings.beginReadArray(QStringLiteral("mappings"));
    QSet<quint32> sourceChords;

    for (int i = 0; i < count; i++) {
        settings.setArrayIndex(i);

        KeyboardMapping mapping = {
            static_cast<SDL_Scancode>(settings.value(QStringLiteral("sourceKey")).toInt()),
            settings.value(QStringLiteral("sourceModifiers")).toInt(),
            static_cast<SDL_Scancode>(settings.value(QStringLiteral("targetKey")).toInt()),
            settings.value(QStringLiteral("targetModifiers")).toInt()
        };
        const quint32 sourceChord = (static_cast<quint32>(mapping.sourceKey) << 4) |
                                    static_cast<quint32>(mapping.sourceModifiers);

        if (!isSupportedKey(mapping.sourceKey) ||
                !isSupportedKey(mapping.targetKey) ||
                (mapping.sourceModifiers & ~ModifierMask) != 0 ||
                (mapping.targetModifiers & ~ModifierMask) != 0 ||
                sourceChords.contains(sourceChord)) {
            qWarning() << "Ignoring invalid or duplicate saved keyboard mapping for host" << hostUuid;
            continue;
        }

        sourceChords.insert(sourceChord);
        mappings.append(mapping);
    }

    settings.endArray();
    settings.endGroup();
    settings.endGroup();
    return mappings;
}

HostKeyboardSettings KeyboardMappingStore::loadHostSettings(const QString& hostUuid)
{
    HostKeyboardSettings hostSettings;
    if (hostUuid.isEmpty()) {
        return hostSettings;
    }

    QSettings settings;
    const bool legacyFunctionKeySetting = settings.value(QStringLiteral("macfunctionkeysonfocus"), false).toBool();
    settings.beginGroup(QStringLiteral("keyboardmappings"));
    settings.beginGroup(hostUuid);
    const bool hasHostFunctionKeySetting = settings.contains(QStringLiteral("macFunctionKeysOnFocus"));
    hostSettings.macFunctionKeysOnFocus =
        settings.value(QStringLiteral("macFunctionKeysOnFocus"), legacyFunctionKeySetting).toBool();
    hostSettings.disableMacCapsLock =
        settings.value(QStringLiteral("disableMacCapsLock"), false).toBool();
    if (!hasHostFunctionKeySetting) {
        settings.setValue(QStringLiteral("macFunctionKeysOnFocus"), hostSettings.macFunctionKeysOnFocus);
        if (settings.status() != QSettings::NoError) {
            qWarning() << "Failed to migrate macOS F-key preference for host" << hostUuid;
        }
    }
    settings.endGroup();
    settings.endGroup();
    return hostSettings;
}

bool KeyboardMappingStore::saveConfiguration(const QString& hostUuid,
                                             const QList<KeyboardMapping>& mappings,
                                             const HostKeyboardSettings& hostSettings)
{
    if (hostUuid.isEmpty()) {
        qWarning() << "Cannot save keyboard configuration without a host UUID";
        return false;
    }

    QSet<quint32> sourceChords;
    for (const KeyboardMapping& mapping : mappings) {
        const quint32 sourceChord = (static_cast<quint32>(mapping.sourceKey) << 4) |
                                    static_cast<quint32>(mapping.sourceModifiers);
        if (!isSupportedKey(mapping.sourceKey) ||
                !isSupportedKey(mapping.targetKey) ||
                (mapping.sourceModifiers & ~ModifierMask) != 0 ||
                (mapping.targetModifiers & ~ModifierMask) != 0 ||
                sourceChords.contains(sourceChord)) {
            qWarning() << "Refusing to save invalid or duplicate keyboard mappings for host" << hostUuid;
            return false;
        }
        sourceChords.insert(sourceChord);
    }

    QSettings settings;
    settings.beginGroup(QStringLiteral("keyboardmappings"));
    settings.beginGroup(hostUuid);
    settings.remove(QString());
    settings.beginWriteArray(QStringLiteral("mappings"), mappings.size());
    for (int i = 0; i < mappings.size(); i++) {
        const KeyboardMapping& mapping = mappings[i];
        settings.setArrayIndex(i);
        settings.setValue(QStringLiteral("sourceKey"), static_cast<int>(mapping.sourceKey));
        settings.setValue(QStringLiteral("sourceModifiers"), mapping.sourceModifiers);
        settings.setValue(QStringLiteral("targetKey"), static_cast<int>(mapping.targetKey));
        settings.setValue(QStringLiteral("targetModifiers"), mapping.targetModifiers);
    }
    settings.endArray();
    settings.setValue(QStringLiteral("macFunctionKeysOnFocus"), hostSettings.macFunctionKeysOnFocus);
    settings.setValue(QStringLiteral("disableMacCapsLock"), hostSettings.disableMacCapsLock);
    settings.endGroup();
    settings.endGroup();

    if (settings.status() != QSettings::NoError) {
        qWarning() << "Failed to save keyboard configuration for host" << hostUuid;
        return false;
    }
    return true;
}

void KeyboardMappingStore::remove(const QString& hostUuid)
{
    if (hostUuid.isEmpty()) {
        return;
    }

    QSettings settings;
    settings.beginGroup(QStringLiteral("keyboardmappings"));
    settings.remove(hostUuid);
    settings.endGroup();
}

QVariantList KeyboardMappingStore::supportedKeys()
{
    QVariantList keys;
    for (SDL_Scancode scancode : supportedScancodes()) {
        const char* name = SDL_GetScancodeName(scancode);
        if (name == nullptr || *name == '\0') {
            continue;
        }

        QVariantMap key;
        key.insert(QStringLiteral("name"), QString::fromUtf8(name));
        key.insert(QStringLiteral("code"), static_cast<int>(scancode));
        keys.append(key);
    }
    return keys;
}

bool KeyboardMappingStore::isSupportedKey(SDL_Scancode scancode)
{
    return supportedScancodes().contains(scancode);
}

int KeyboardMappingStore::modifiersFromSdl(Uint16 modifiers)
{
    int result = 0;
    if (modifiers & KMOD_CTRL) {
        result |= ModifierCtrl;
    }
    if (modifiers & KMOD_ALT) {
        result |= ModifierAlt;
    }
    if (modifiers & KMOD_SHIFT) {
        result |= ModifierShift;
    }
    if (modifiers & KMOD_GUI) {
        result |= ModifierMeta;
    }
    return result;
}

SDL_Keymod KeyboardMappingStore::modifiersToSdl(int modifiers)
{
    SDL_Keymod result = KMOD_NONE;
    if (modifiers & ModifierCtrl) {
        result = static_cast<SDL_Keymod>(result | KMOD_CTRL);
    }
    if (modifiers & ModifierAlt) {
        result = static_cast<SDL_Keymod>(result | KMOD_ALT);
    }
    if (modifiers & ModifierShift) {
        result = static_cast<SDL_Keymod>(result | KMOD_SHIFT);
    }
    if (modifiers & ModifierMeta) {
        result = static_cast<SDL_Keymod>(result | KMOD_GUI);
    }
    return result;
}

int KeyboardMappingStore::modifierForScancode(SDL_Scancode scancode)
{
    switch (scancode) {
    case SDL_SCANCODE_LCTRL:
    case SDL_SCANCODE_RCTRL:
        return ModifierCtrl;
    case SDL_SCANCODE_LALT:
    case SDL_SCANCODE_RALT:
        return ModifierAlt;
    case SDL_SCANCODE_LSHIFT:
    case SDL_SCANCODE_RSHIFT:
        return ModifierShift;
    case SDL_SCANCODE_LGUI:
    case SDL_SCANCODE_RGUI:
        return ModifierMeta;
    default:
        return 0;
    }
}
