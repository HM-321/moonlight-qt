#include "streaming/session.h"

#include <Limelight.h>
#include "SDL_compat.h"

#define VK_0 0x30
#define VK_A 0x41

// These are real Windows VK_* codes
#ifndef VK_F1
#define VK_F1 0x70
#define VK_F13 0x7C
#define VK_NUMPAD0 0x60
#endif

#define MAKE_KEYPRESS_STATE(code, modifiers, flags) \
    ((uint32_t)(uint16_t)(code) | \
    ((uint32_t)(uint8_t)((modifiers) & MODIFIER_EXTENDED) << 16) | \
    ((uint32_t)(uint8_t)(flags) << 24))

#define GET_KEYPRESS_CODE(x) ((short)((x) & 0xFFFF))
#define GET_KEYPRESS_EXTENDED_MODIFIER(x) ((char)(((x) >> 16) & 0xFF))
#define GET_KEYPRESS_FLAGS(x) ((char)(((x) >> 24) & 0xFF))

void SdlInputHandler::performSpecialKeyCombo(KeyCombo combo)
{
    switch (combo) {
    case KeyComboQuit:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected quit key combo");

        // Push a quit event to the main loop
        SDL_Event event;
        event.type = SDL_QUIT;
        event.quit.timestamp = SDL_GetTicks();
        SDL_PushEvent(&event);
        break;

    case KeyComboUngrabInput:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected mouse capture toggle combo");

        // Stop handling future input
        setCaptureActive(!isCaptureActive());

        // Force raise all keys to ensure they aren't stuck,
        // since we won't get their key up events.
        raiseAllKeys();
        break;

    case KeyComboToggleFullScreen:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected full-screen toggle combo");
        Session::s_ActiveSession->toggleFullscreen();

        // Force raise all keys just be safe across this full-screen/windowed
        // transition just in case key events get lost.
        raiseAllKeys();
        break;

    case KeyComboToggleStatsOverlay:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected stats toggle combo");

        // Toggle the stats overlay
        Session::get()->getOverlayManager().setOverlayState(Overlay::OverlayDebug,
                                                            !Session::get()->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug));
        break;

    case KeyComboToggleMouseMode:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected mouse mode toggle combo");

        // Uncapture input
        setCaptureActive(false);

        // Toggle mouse mode
        m_AbsoluteMouseMode = !m_AbsoluteMouseMode;

        // Recapture input
        setCaptureActive(true);
        break;

    case KeyComboToggleCursorHide:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected show mouse combo");

        if (!SDL_GetRelativeMouseMode()) {
            m_MouseCursorCapturedVisibilityState = !m_MouseCursorCapturedVisibilityState;
            SDL_ShowCursor(m_MouseCursorCapturedVisibilityState);
        }
        else {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Cursor can only be shown in remote desktop mouse mode");
        }
        break;

    case KeyComboToggleMinimize:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected minimize combo");
        SDL_MinimizeWindow(m_Window);
        break;

    case KeyComboPasteText:
    {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected type clipboard text combo");

        // Force raise all keys to ensure that none of them interfere
        // with the text we're going to type.
        raiseAllKeys();

        char* text;
        if (SDL_HasClipboardText() && (text = SDL_GetClipboardText()) != nullptr) {
            // Sending both CR and LF will lead to two newlines in the destination for
            // each newline in the source, so we fix up any CRLFs into just a single LF.
            for (char* c = text; *c != 0; c++) {
                if (*c == '\r' && *(c + 1) == '\n') {
                    // We're using strlen() rather than strlen() - 1 since we need to add 1
                    // to copy the null terminator which is not included in strlen()'s count.
                    memmove(c, c + 1, strlen(c));
                }
            }

            // Send this text to the PC
            LiSendUtf8TextEvent(text, (unsigned int)strlen(text));

            // SDL_GetClipboardText() allocates, so we must free
            SDL_free((void*)text);
        }
        else {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "No text in clipboard to paste!");
        }
        break;
    }

    case KeyComboTogglePointerRegionLock:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected pointer region lock toggle combo");
        m_PointerRegionLockActive = !m_PointerRegionLockActive;

        // Remember that the user changed this manually, so we don't mess with it anymore
        // during windowed <-> full-screen transitions.
        m_PointerRegionLockToggledByUser = true;

        // Apply the new region lock
        updatePointerRegionLock();
        break;

    case KeyComboQuitAndExit:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected quitAndExit key combo");

        // Indicate that we want to exit afterwards
        Session::get()->setShouldExit(true);

        // Push a quit event to the main loop
        SDL_Event quitExitEvent;
        quitExitEvent.type = SDL_QUIT;
        quitExitEvent.quit.timestamp = SDL_GetTicks();
        SDL_PushEvent(&quitExitEvent);
        break;

    case KeyComboToggleKeyboardGrab:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Detected keyboard grab toggle combo");

        // Toggle the system key capture mode
        if (isSystemKeyCaptureActive()) {
            m_CaptureSystemKeysMode = StreamingPreferences::CSK_OFF;
        }
        else {
            m_CaptureSystemKeysMode = StreamingPreferences::CSK_ALWAYS;
        }

        updateKeyboardGrabState();
        break;

    default:
        Q_UNREACHABLE();
    }
}

bool SdlInputHandler::handleSpecialKeyComboIfAny(SDL_KeyboardEvent* event)
{
    if (event->state != SDL_PRESSED ||
            !(event->keysym.mod & KMOD_CTRL) ||
            !(event->keysym.mod & KMOD_ALT) ||
            !(event->keysym.mod & KMOD_SHIFT)) {
        return false;
    }

    for (int i = 0; i < KeyComboMax; i++) {
        if (m_SpecialKeyCombos[i].enabled && event->keysym.sym == m_SpecialKeyCombos[i].keyCode) {
            flushPendingModifierKeyDowns();
            performSpecialKeyCombo(m_SpecialKeyCombos[i].keyCombo);
            return true;
        }
    }

    for (int i = 0; i < KeyComboMax; i++) {
        if (m_SpecialKeyCombos[i].enabled && event->keysym.scancode == m_SpecialKeyCombos[i].scanCode) {
            flushPendingModifierKeyDowns();
            performSpecialKeyCombo(m_SpecialKeyCombos[i].keyCombo);
            return true;
        }
    }

    return false;
}

void SdlInputHandler::handleKeyEventDirect(SDL_KeyboardEvent* event, bool mapped)
{
    const bool bypassKeyboardMappings = m_BypassKeyboardMappings;
    const bool processingMappedKey = m_ProcessingMappedKey;
    m_BypassKeyboardMappings = true;
    m_ProcessingMappedKey = mapped;
    handleKeyEvent(event);
    m_BypassKeyboardMappings = bypassKeyboardMappings;
    m_ProcessingMappedKey = processingMappedKey;
}

void SdlInputHandler::handleMappedKeyEvent(SDL_KeyboardEvent* event, const KeyboardMapping& mapping)
{
    SDL_KeyboardEvent mappedEvent = *event;
    mappedEvent.keysym.scancode = mapping.targetKey;
    mappedEvent.keysym.mod = static_cast<SDL_Keymod>(
        KeyboardMappingStore::modifiersToSdl(mapping.targetModifiers) |
        (event->keysym.mod & (KMOD_CAPS | KMOD_NUM)));

    if (event->state == SDL_PRESSED &&
            (mapping.targetModifiers & KeyboardMappingStore::ModifierMeta)) {
        SDL_KeyboardEvent metaEvent = mappedEvent;
        metaEvent.keysym.scancode = SDL_SCANCODE_LGUI;
        metaEvent.keysym.mod = static_cast<SDL_Keymod>(KMOD_GUI |
            (event->keysym.mod & (KMOD_CAPS | KMOD_NUM)));
        handleKeyEventDirect(&metaEvent, true);
    }

    handleKeyEventDirect(&mappedEvent, true);

    if (event->state == SDL_RELEASED &&
            (mapping.targetModifiers & KeyboardMappingStore::ModifierMeta)) {
        SDL_KeyboardEvent metaEvent = mappedEvent;
        metaEvent.keysym.scancode = SDL_SCANCODE_LGUI;
        metaEvent.keysym.mod = static_cast<SDL_Keymod>(event->keysym.mod & (KMOD_CAPS | KMOD_NUM));
        handleKeyEventDirect(&metaEvent, true);
    }
}

int SdlInputHandler::mapKeyboardModifiers(int sourceModifiers) const
{
    int mappedModifiers = 0;
    const int modifierBits[] = {
        KeyboardMappingStore::ModifierCtrl,
        KeyboardMappingStore::ModifierAlt,
        KeyboardMappingStore::ModifierShift,
        KeyboardMappingStore::ModifierMeta
    };

    for (int sourceModifier : modifierBits) {
        if (!(sourceModifiers & sourceModifier)) {
            continue;
        }

        int targetModifier = sourceModifier;
        for (const ModifierMapping& mapping : std::as_const(m_ModifierMappings)) {
            if (mapping.sourceModifier == sourceModifier) {
                targetModifier = mapping.targetModifier;
                break;
            }
        }
        mappedModifiers |= targetModifier;
    }

    return mappedModifiers;
}

SDL_Scancode SdlInputHandler::mapModifierScancode(SDL_Scancode sourceScancode) const
{
    const int sourceModifier = KeyboardMappingStore::modifierForScancode(sourceScancode);
    if (sourceModifier == 0) {
        return sourceScancode;
    }

    int targetModifier = sourceModifier;
    for (const ModifierMapping& mapping : std::as_const(m_ModifierMappings)) {
        if (mapping.sourceModifier == sourceModifier) {
            targetModifier = mapping.targetModifier;
            break;
        }
    }

    const bool isRight = sourceScancode == SDL_SCANCODE_RCTRL ||
                         sourceScancode == SDL_SCANCODE_RALT ||
                         sourceScancode == SDL_SCANCODE_RSHIFT ||
                         sourceScancode == SDL_SCANCODE_RGUI;
    switch (targetModifier) {
    case KeyboardMappingStore::ModifierCtrl:
        return isRight ? SDL_SCANCODE_RCTRL : SDL_SCANCODE_LCTRL;
    case KeyboardMappingStore::ModifierAlt:
        return isRight ? SDL_SCANCODE_RALT : SDL_SCANCODE_LALT;
    case KeyboardMappingStore::ModifierShift:
        return isRight ? SDL_SCANCODE_RSHIFT : SDL_SCANCODE_LSHIFT;
    case KeyboardMappingStore::ModifierMeta:
        return isRight ? SDL_SCANCODE_RGUI : SDL_SCANCODE_LGUI;
    default:
        return sourceScancode;
    }
}

void SdlInputHandler::handleMappedModifierKeyEvent(SDL_KeyboardEvent* event, SDL_Scancode targetScancode)
{
    SDL_KeyboardEvent mappedEvent = *event;
    mappedEvent.keysym.scancode = targetScancode;
    mappedEvent.keysym.mod = static_cast<SDL_Keymod>(
        KeyboardMappingStore::modifiersToSdl(
            mapKeyboardModifiers(KeyboardMappingStore::modifiersFromSdl(event->keysym.mod))) |
        (event->keysym.mod & (KMOD_CAPS | KMOD_NUM)));

    if (event->state == SDL_PRESSED) {
        m_ActiveModifierMappings.insert(event->keysym.scancode, targetScancode);
    }
    else {
        m_ActiveModifierMappings.remove(event->keysym.scancode);
    }

    handleKeyEventDirect(&mappedEvent, targetScancode != event->keysym.scancode);
}

void SdlInputHandler::flushPendingModifierKeyDowns()
{
    const QList<SDL_Scancode> pendingScancodes = m_PendingModifierKeyDowns.keys();
    for (SDL_Scancode scancode : pendingScancodes) {
        SDL_KeyboardEvent event = m_PendingModifierKeyDowns.value(scancode);
        m_ForwardedModifierKeys.insert(scancode);
        handleMappedModifierKeyEvent(&event, mapModifierScancode(scancode));
    }
    m_PendingModifierKeyDowns.clear();
}

void SdlInputHandler::handleKeyEvent(SDL_KeyboardEvent* event)
{
    short keyCode;
    char modifiers;
    char flags;
    bool shouldNotConvertToScanCodeOnServer = false;

    if (event->repeat) {
        // Ignore repeat key down events
        SDL_assert(event->state == SDL_PRESSED);
        return;
    }

    if (!m_BypassKeyboardMappings &&
            event->state == SDL_PRESSED &&
            handleSpecialKeyComboIfAny(event)) {
        return;
    }

    if (!m_BypassKeyboardMappings &&
            (!m_KeyboardMappings.isEmpty() || !m_ModifierMappings.isEmpty())) {
        const SDL_Scancode sourceScancode = event->keysym.scancode;
        const int sourceModifier = KeyboardMappingStore::modifierForScancode(sourceScancode);

        if (sourceModifier != 0) {
            if (event->state == SDL_PRESSED) {
                if (!m_KeyboardMappings.isEmpty()) {
                    m_PendingModifierKeyDowns.insert(sourceScancode, *event);
                }
                else {
                    handleMappedModifierKeyEvent(event, mapModifierScancode(sourceScancode));
                }
                return;
            }

            if (m_ConsumedModifierKeyUps.remove(sourceScancode)) {
                return;
            }

            auto activeModifierMapping = m_ActiveModifierMappings.find(sourceScancode);
            if (activeModifierMapping != m_ActiveModifierMappings.end()) {
                const SDL_Scancode targetScancode = activeModifierMapping.value();
                m_ForwardedModifierKeys.remove(sourceScancode);
                handleMappedModifierKeyEvent(event, targetScancode);
                return;
            }

            auto pendingModifier = m_PendingModifierKeyDowns.find(sourceScancode);
            if (pendingModifier != m_PendingModifierKeyDowns.end()) {
                SDL_KeyboardEvent keyDownEvent = pendingModifier.value();
                m_PendingModifierKeyDowns.erase(pendingModifier);
                handleMappedModifierKeyEvent(&keyDownEvent, mapModifierScancode(sourceScancode));
                m_ForwardedModifierKeys.remove(sourceScancode);
                handleMappedModifierKeyEvent(event, mapModifierScancode(sourceScancode));
                return;
            }

            m_ForwardedModifierKeys.remove(sourceScancode);
            if (m_KeyboardMappings.isEmpty()) {
                handleKeyEventDirect(event);
                return;
            }
        }
        else {
            if (event->state == SDL_PRESSED && !m_KeyboardMappings.isEmpty()) {
                const int sourceModifiers = KeyboardMappingStore::modifiersFromSdl(event->keysym.mod);
                for (const KeyboardMapping& mapping : std::as_const(m_KeyboardMappings)) {
                    if (mapping.sourceKey != sourceScancode || mapping.sourceModifiers != sourceModifiers) {
                        continue;
                    }

                    int forwardedModifiers = 0;
                    for (SDL_Scancode forwardedKey : std::as_const(m_ForwardedModifierKeys)) {
                        forwardedModifiers |= KeyboardMappingStore::modifierForScancode(forwardedKey);
                    }
                    if (forwardedModifiers & mapping.sourceModifiers) {
                        break;
                    }

                    const QList<SDL_Scancode> pendingScancodes = m_PendingModifierKeyDowns.keys();
                    for (SDL_Scancode scancode : pendingScancodes) {
                        m_ConsumedModifierKeyUps.insert(scancode);
                    }
                    m_PendingModifierKeyDowns.clear();
                    m_ActiveKeyboardMappings.insert(sourceScancode, mapping);

                    handleMappedKeyEvent(event, mapping);
                    return;
                }
            }
            else if (event->state == SDL_RELEASED && !m_KeyboardMappings.isEmpty()) {
                auto activeMapping = m_ActiveKeyboardMappings.find(sourceScancode);
                if (activeMapping != m_ActiveKeyboardMappings.end()) {
                    const KeyboardMapping mapping = activeMapping.value();
                    m_ActiveKeyboardMappings.erase(activeMapping);
                    handleMappedKeyEvent(event, mapping);
                    return;
                }
            }

            flushPendingModifierKeyDowns();

            if (!m_ModifierMappings.isEmpty()) {
                SDL_KeyboardEvent mappedEvent = *event;
                mappedEvent.keysym.mod = static_cast<SDL_Keymod>(
                    KeyboardMappingStore::modifiersToSdl(
                        mapKeyboardModifiers(KeyboardMappingStore::modifiersFromSdl(event->keysym.mod))) |
                    (event->keysym.mod & (KMOD_CAPS | KMOD_NUM)));
                handleKeyEventDirect(&mappedEvent, true);
                return;
            }
        }
    }

    // Set modifier flags
    modifiers = 0;
    if (event->keysym.mod & KMOD_CTRL) {
        modifiers |= MODIFIER_CTRL;
    }
    if (event->keysym.mod & KMOD_ALT) {
        modifiers |= MODIFIER_ALT;
    }
    if (event->keysym.mod & KMOD_SHIFT) {
        modifiers |= MODIFIER_SHIFT;
    }
    if (event->keysym.mod & KMOD_GUI) {
        if (isSystemKeyCaptureActive() || m_ProcessingMappedKey) {
            modifiers |= MODIFIER_META;
        }
    }

    // Set keycode. We explicitly use scancode here because GFE will try to correct
    // for AZERTY layouts on the host but it depends on receiving VK_ values matching
    // a QWERTY layout to work.
    if (event->keysym.scancode >= SDL_SCANCODE_1 && event->keysym.scancode <= SDL_SCANCODE_9) {
        // SDL defines SDL_SCANCODE_0 > SDL_SCANCODE_9, so we need to handle that manually
        keyCode = (event->keysym.scancode - SDL_SCANCODE_1) + VK_0 + 1;
    }
    else if (event->keysym.scancode >= SDL_SCANCODE_A && event->keysym.scancode <= SDL_SCANCODE_Z) {
        keyCode = (event->keysym.scancode - SDL_SCANCODE_A) + VK_A;
    }
    else if (event->keysym.scancode >= SDL_SCANCODE_F1 && event->keysym.scancode <= SDL_SCANCODE_F12) {
        keyCode = (event->keysym.scancode - SDL_SCANCODE_F1) + VK_F1;
    }
    else if (event->keysym.scancode >= SDL_SCANCODE_F13 && event->keysym.scancode <= SDL_SCANCODE_F24) {
        keyCode = (event->keysym.scancode - SDL_SCANCODE_F13) + VK_F13;
    }
    else if (event->keysym.scancode >= SDL_SCANCODE_KP_1 && event->keysym.scancode <= SDL_SCANCODE_KP_9) {
        // SDL defines SDL_SCANCODE_KP_0 > SDL_SCANCODE_KP_9, so we need to handle that manually
        keyCode = (event->keysym.scancode - SDL_SCANCODE_KP_1) + VK_NUMPAD0 + 1;
    }
    else {
        switch (event->keysym.scancode) {
            case SDL_SCANCODE_BACKSPACE:
                keyCode = 0x08;
                break;
            case SDL_SCANCODE_TAB:
                keyCode = 0x09;
                break;
            case SDL_SCANCODE_CLEAR:
                keyCode = 0x0C;
                break;
            case SDL_SCANCODE_KP_ENTER:
                modifiers |= MODIFIER_EXTENDED;
                Q_FALLTHROUGH();
            case SDL_SCANCODE_RETURN:
                keyCode = 0x0D;
                break;
            case SDL_SCANCODE_PAUSE:
                keyCode = 0x13;
                break;
            case SDL_SCANCODE_CAPSLOCK:
                keyCode = 0x14;
                break;
            case SDL_SCANCODE_ESCAPE:
                keyCode = 0x1B;
                break;
            case SDL_SCANCODE_SPACE:
                keyCode = 0x20;
                break;
            case SDL_SCANCODE_PAGEUP:
                keyCode = 0x21;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_PAGEDOWN:
                keyCode = 0x22;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_END:
                keyCode = 0x23;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_HOME:
                keyCode = 0x24;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_LEFT:
                keyCode = 0x25;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_UP:
                keyCode = 0x26;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_RIGHT:
                keyCode = 0x27;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_DOWN:
                keyCode = 0x28;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_SELECT:
                keyCode = 0x29;
                break;
            case SDL_SCANCODE_EXECUTE:
                keyCode = 0x2B;
                break;
            case SDL_SCANCODE_PRINTSCREEN:
                keyCode = 0x2C;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_INSERT:
                keyCode = 0x2D;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_DELETE:
                keyCode = 0x2E;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_HELP:
                keyCode = 0x2F;
                break;
            case SDL_SCANCODE_KP_0:
                // See comment above about why we only handle SDL_SCANCODE_KP_0 here
                keyCode = VK_NUMPAD0;
                break;
            case SDL_SCANCODE_0:
                // See comment above about why we only handle SDL_SCANCODE_0 here
                keyCode = VK_0;
                break;
            case SDL_SCANCODE_KP_MULTIPLY:
                keyCode = 0x6A;
                break;
            case SDL_SCANCODE_KP_PLUS:
                keyCode = 0x6B;
                break;
            case SDL_SCANCODE_KP_COMMA:
                keyCode = 0x6C;
                break;
            case SDL_SCANCODE_KP_MINUS:
                keyCode = 0x6D;
                break;
            case SDL_SCANCODE_KP_PERIOD:
                keyCode = 0x6E;
                break;
            case SDL_SCANCODE_KP_DIVIDE:
                keyCode = 0x6F;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_NUMLOCKCLEAR:
                keyCode = 0x90;
                break;
            case SDL_SCANCODE_SCROLLLOCK:
                keyCode = 0x91;
                break;
            case SDL_SCANCODE_LSHIFT:
                keyCode = 0xA0;
                break;
            case SDL_SCANCODE_RSHIFT:
                keyCode = 0xA1;
                break;
            case SDL_SCANCODE_LCTRL:
                keyCode = 0xA2;
                break;
            case SDL_SCANCODE_RCTRL:
                keyCode = 0xA3;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_LALT:
                keyCode = 0xA4;
                break;
            case SDL_SCANCODE_RALT:
                keyCode = 0xA5;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_LGUI:
                if (!isSystemKeyCaptureActive() && !m_ProcessingMappedKey) {
                    return;
                }
                keyCode = 0x5B;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_RGUI:
                if (!isSystemKeyCaptureActive() && !m_ProcessingMappedKey) {
                    return;
                }
                keyCode = 0x5C;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_APPLICATION:
                keyCode = 0x5D;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_BACK:
                keyCode = 0xA6;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_FORWARD:
                keyCode = 0xA7;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_REFRESH:
                keyCode = 0xA8;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_STOP:
                keyCode = 0xA9;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_SEARCH:
                keyCode = 0xAA;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_BOOKMARKS:
                keyCode = 0xAB;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_AC_HOME:
                keyCode = 0xAC;
                modifiers |= MODIFIER_EXTENDED;
                break;
            case SDL_SCANCODE_SEMICOLON:
                keyCode = 0xBA;
                break;
            case SDL_SCANCODE_EQUALS:
                keyCode = 0xBB;
                break;
            case SDL_SCANCODE_COMMA:
                keyCode = 0xBC;
                break;
            case SDL_SCANCODE_MINUS:
                keyCode = 0xBD;
                break;
            case SDL_SCANCODE_PERIOD:
                keyCode = 0xBE;
                break;
            case SDL_SCANCODE_SLASH:
                keyCode = 0xBF;
                break;
            case SDL_SCANCODE_GRAVE:
                keyCode = 0xC0;
                break;
            case SDL_SCANCODE_LEFTBRACKET:
                keyCode = 0xDB;
                break;
            case SDL_SCANCODE_INTERNATIONAL3:
                shouldNotConvertToScanCodeOnServer = true;
                Q_FALLTHROUGH();
            case SDL_SCANCODE_BACKSLASH:
                keyCode = 0xDC;
                break;
            case SDL_SCANCODE_RIGHTBRACKET:
                keyCode = 0xDD;
                break;
            case SDL_SCANCODE_APOSTROPHE:
                keyCode = 0xDE;
                break;
            case SDL_SCANCODE_INTERNATIONAL1:
                shouldNotConvertToScanCodeOnServer = true;
                Q_FALLTHROUGH();
            case SDL_SCANCODE_NONUSBACKSLASH:
                keyCode = 0xE2;
                break;
            case SDL_SCANCODE_LANG1:
                keyCode = 0x1C;
                break;
            case SDL_SCANCODE_LANG2:
                keyCode = 0x1D;
                break;
            default:
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                            "Unhandled button event: %d",
                             event->keysym.scancode);
                return;
        }
    }

    keyCode |= 0x8000;
    flags = shouldNotConvertToScanCodeOnServer ? SS_KBE_FLAG_NON_NORMALIZED : 0;

    // Track the key state so we always know which keys are down
    if (event->state == SDL_PRESSED) {
        m_KeysDown.insert(MAKE_KEYPRESS_STATE(keyCode, modifiers, flags));
    }
    else {
        m_KeysDown.remove(MAKE_KEYPRESS_STATE(keyCode, modifiers, flags));
    }

    LiSendKeyboardEvent2(keyCode,
                         event->state == SDL_PRESSED ?
                             KEY_ACTION_DOWN : KEY_ACTION_UP,
                         modifiers,
                         flags);
}

void SdlInputHandler::raiseAllKeys()
{
    if (m_KeysDown.isEmpty()) {
        m_PendingModifierKeyDowns.clear();
        m_ConsumedModifierKeyUps.clear();
        m_ForwardedModifierKeys.clear();
        m_ActiveKeyboardMappings.clear();
        return;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Raising %d keys",
                (int)m_KeysDown.count());

    for (auto keyDown : std::as_const(m_KeysDown)) {
        LiSendKeyboardEvent2(GET_KEYPRESS_CODE(keyDown),
                             KEY_ACTION_UP,
                             GET_KEYPRESS_EXTENDED_MODIFIER(keyDown),
                             GET_KEYPRESS_FLAGS(keyDown));
    }

    m_KeysDown.clear();
    m_PendingModifierKeyDowns.clear();
    m_ConsumedModifierKeyUps.clear();
    m_ForwardedModifierKeys.clear();
    m_ActiveKeyboardMappings.clear();
}
