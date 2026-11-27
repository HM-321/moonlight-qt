#include "maccapslockkeycapture.h"

#include "input/keyboardmapping.h"

#include <IOKit/hid/IOHIDManager.h>
#include <SDL.h>

namespace {

constexpr uint32_t kKeyboardUsagePage = 0x07;
constexpr uint32_t kCapsLockUsage = 0x39;

IOHIDManagerRef s_HidManager;
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

void handleHidValue(void*, IOReturn, void*, IOHIDValueRef value)
{
    IOHIDElementRef element = IOHIDValueGetElement(value);
    if (IOHIDElementGetUsagePage(element) != kKeyboardUsagePage ||
            IOHIDElementGetUsage(element) != kCapsLockUsage) {
        return;
    }

    // IOHID reports the physical switch value: 1 on press and 0 immediately
    // on release. Unlike the macOS Caps Lock flag, this is not toggle state.
    const bool down = IOHIDValueGetIntegerValue(value) != 0;
    if (down == s_CapsLockDown) {
        return;
    }

    s_CapsLockDown = down;
    pushCapsLockSentinel(down);
}

void stopCapture()
{
    if (s_HidManager != nullptr) {
        IOHIDManagerUnscheduleFromRunLoop(s_HidManager,
                                          CFRunLoopGetMain(),
                                          kCFRunLoopCommonModes);
        IOHIDManagerClose(s_HidManager, kIOHIDOptionsTypeNone);
        CFRelease(s_HidManager);
        s_HidManager = nullptr;
    }

    if (s_CapsLockDown) {
        s_CapsLockDown = false;
        pushCapsLockSentinel(false);
    }
}

}

bool MacCapsLockKeyCapture::setStreamingActive(bool active)
{
    if (!active) {
        stopCapture();
        return true;
    }

    if (s_HidManager != nullptr) {
        return true;
    }

    s_HidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (s_HidManager == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to create macOS IOHID manager for Caps Lock");
        return false;
    }

    const void* keys[] = { CFSTR(kIOHIDElementUsagePageKey), CFSTR(kIOHIDElementUsageKey) };
    const int page = kKeyboardUsagePage;
    const int usage = kCapsLockUsage;
    CFNumberRef pageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usageNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void* values[] = { pageNumber, usageNumber };
    CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault,
                                                   keys, values, 2,
                                                   &kCFTypeDictionaryKeyCallBacks,
                                                   &kCFTypeDictionaryValueCallBacks);

    IOHIDManagerSetInputValueMatching(s_HidManager, matching);
    IOHIDManagerRegisterInputValueCallback(s_HidManager, handleHidValue, nullptr);
    IOHIDManagerScheduleWithRunLoop(s_HidManager,
                                    CFRunLoopGetMain(),
                                    kCFRunLoopCommonModes);

    CFRelease(matching);
    CFRelease(pageNumber);
    CFRelease(usageNumber);

    const IOReturn result = IOHIDManagerOpen(s_HidManager, kIOHIDOptionsTypeNone);
    if (result != kIOReturnSuccess) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to open macOS IOHID manager for Caps Lock: 0x%x",
                     result);
        stopCapture();
        return false;
    }

    s_CapsLockDown = false;
    return true;
}
