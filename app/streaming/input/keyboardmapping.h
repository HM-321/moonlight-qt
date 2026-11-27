#pragma once

#include "SDL_compat.h"

#include <QList>
#include <QString>
#include <QVariantList>

struct KeyboardMapping
{
    SDL_Scancode sourceKey;
    int sourceModifiers;
    SDL_Scancode targetKey;
    int targetModifiers;
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
    static bool save(const QString& hostUuid, const QList<KeyboardMapping>& mappings);
    static void remove(const QString& hostUuid);
    static QVariantList supportedKeys();
    static bool isSupportedKey(SDL_Scancode scancode);
    static int modifiersFromSdl(SDL_Keymod modifiers);
    static SDL_Keymod modifiersToSdl(int modifiers);
    static int modifierForScancode(SDL_Scancode scancode);
};
