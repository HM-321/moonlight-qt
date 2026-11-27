#include "macjapaneseinputkeycapture.h"

#include <AppKit/AppKit.h>
#include <SDL.h>

namespace {

constexpr unsigned short kJisEisuKeyCode = 0x66;
constexpr unsigned short kJisKanaKeyCode = 0x68;

id s_JapaneseInputKeyMonitor;

}

bool MacJapaneseInputKeyCapture::setStreamingActive(bool active)
{
    if (!active) {
        if (s_JapaneseInputKeyMonitor != nil) {
            [NSEvent removeMonitor:s_JapaneseInputKeyMonitor];
            s_JapaneseInputKeyMonitor = nil;
        }
        return true;
    }

    if (s_JapaneseInputKeyMonitor != nil) {
        return true;
    }

    // SDL queues these events before AppKit dispatches them to the local input method.
    s_JapaneseInputKeyMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskKeyDown | NSEventMaskKeyUp)
                                              handler:^NSEvent*(NSEvent* event) {
        const unsigned short keyCode = [event keyCode];
        if (keyCode == kJisEisuKeyCode || keyCode == kJisKanaKeyCode) {
            return nil;
        }
        return event;
    }];

    if (s_JapaneseInputKeyMonitor == nil) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to suppress local macOS Eisu/Kana key actions");
        return false;
    }

    return true;
}
