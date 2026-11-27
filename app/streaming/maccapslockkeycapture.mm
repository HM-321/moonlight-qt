#include "maccapslockkeycapture.h"

#include "input/keyboardmapping.h"

#include <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <SDL.h>

namespace {

constexpr unsigned short kCapsLockKeyCode = 0x39;
id s_CapsLockMonitor;
bool s_CapsLockDown;

void pushCapsLockSentinel(bool down)
{
    SDL_Event event = {};
    event.type = down ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.type = event.type;
    event.key.state = down ? SDL_PRESSED : SDL_RELEASED;
    event.key.repeat = 0;
    event.key.keysym.scancode = kMacCapsLockHidSentinelScancode;
    event.key.keysym.sym = SDLK_F24;
    event.key.keysym.mod = static_cast<SDL_Keymod>(SDL_GetModState() & (KMOD_NUM | KMOD_CAPS));

    if (SDL_PushEvent(&event) != 1) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Failed to queue synthetic Caps Lock event: %s",
                     SDL_GetError());
        return;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Captured physical macOS Caps Lock %s as F24 sentinel",
                down ? "down" : "up");
}

}

bool MacCapsLockKeyCapture::setStreamingActive(bool active)
{
    if (!active) {
        if (s_CapsLockMonitor != nil) {
            [NSEvent removeMonitor:s_CapsLockMonitor];
            s_CapsLockMonitor = nil;
        }
        if (s_CapsLockDown) {
            s_CapsLockDown = false;
            pushCapsLockSentinel(false);
        }
        return true;
    }

    if (s_CapsLockMonitor != nil) {
        return true;
    }

    s_CapsLockDown = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState,
                                            kCapsLockKeyCode);
    s_CapsLockMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged
                                              handler:^NSEvent*(NSEvent* event) {
        if ([event keyCode] != kCapsLockKeyCode) {
            return event;
        }

        const bool down = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState,
                                                 kCapsLockKeyCode);
        if (down != s_CapsLockDown) {
            s_CapsLockDown = down;
            pushCapsLockSentinel(down);
        }

        // Prevent Caps Lock from toggling the local macOS state while streaming.
        return nil;
    }];

    if (s_CapsLockMonitor == nil) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to capture physical macOS Caps Lock events");
        return false;
    }

    return true;
}
