#pragma once

#include "input/keyboardmapping.h"

#include <QByteArray>

class MacCapsLockMapping
{
public:
    ~MacCapsLockMapping();

    bool activate(SDL_Scancode targetKey);
    void restore();

private:
    QByteArray m_PreviousMappings;
    bool m_HasSavedMappings = false;
    bool m_IsActive = false;
    SDL_Scancode m_TargetKey = SDL_SCANCODE_UNKNOWN;
};
