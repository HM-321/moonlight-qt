#pragma once

#include "SDL_compat.h"

#include <QList>
#include <QString>
#include <QVariantList>

constexpr SDL_Scancode kMacCapsLockHidSentinelScancode = SDL_SCANCODE_F24;

struct KeyboardMapping
{
    SDL_Scancode sourceKey;
    int sourceModifiers;
    SDL_Scancode targetKey;
    int targetModifiers;
};

struct HostKeyboardSettings
{
    bool macFunctionKeysOnFocus = false;
    bool disableMacCapsLock = false;
    bool macJapaneseInputKeys = true;
};

class KeyboardMappingStore
{
public:
    enum Modifier
    {
        ModifierCtrl = 1,
        ModifierAlt = 2,
        ModifierShift = 4,
        ModifierMeta = 8,
        ModifierMask = ModifierCtrl | ModifierAlt | ModifierShift | ModifierMeta
    };

    static QList<KeyboardMapping> load(const QString& hostUuid);
    static HostKeyboardSettings loadHostSettings(const QString& hostUuid);
    static bool saveConfiguration(const QString& hostUuid,
                                  const QList<KeyboardMapping>& mappings,
                                  const HostKeyboardSettings& hostSettings);
    static void remove(const QString& hostUuid);
    static QVariantList supportedSourceKeys();
    static QVariantList supportedTargetKeys();
    static bool isSupportedSourceKey(SDL_Scancode scancode);
    static bool isSupportedTargetKey(SDL_Scancode scancode);
    static int modifiersFromSdl(Uint16 modifiers);
    static SDL_Keymod modifiersToSdl(int modifiers);
    static int modifierForScancode(SDL_Scancode scancode);
};
