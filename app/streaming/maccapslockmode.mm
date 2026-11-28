#include "maccapslockmode.h"

#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

#include <SDL.h>

namespace {

constexpr char kHidSystemPath[] = "IOService:/IOResources/IOHIDSystem";

io_connect_t openHidSystemConnection()
{
    io_service_t service = IORegistryEntryFromPath(kIOMainPortDefault, kHidSystemPath);
    if (service == IO_OBJECT_NULL) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to find IOHIDSystem in the IORegistry");
        return IO_OBJECT_NULL;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service,
                                         mach_task_self(),
                                         static_cast<uint32_t>(kIOHIDParamConnectType),
                                         &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS || connection == IO_OBJECT_NULL) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "IOServiceOpen for IOHIDSystem failed: 0x%x",
                     static_cast<unsigned int>(result));
        if (connection != IO_OBJECT_NULL) {
            IOServiceClose(connection);
        }
        return IO_OBJECT_NULL;
    }

    return connection;
}

}

bool MacCapsLockMode::readState(bool& enabled)
{
    io_connect_t connection = openHidSystemConnection();
    if (connection == IO_OBJECT_NULL) {
        return false;
    }

    kern_return_t result = IOHIDGetModifierLockState(connection, kIOHIDCapsLockState, &enabled);
    IOServiceClose(connection);
    if (result != KERN_SUCCESS) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "IOHIDGetModifierLockState for Caps Lock failed: 0x%x",
                     static_cast<unsigned int>(result));
        return false;
    }
    return true;
}

bool MacCapsLockMode::writeState(bool enabled)
{
    io_connect_t connection = openHidSystemConnection();
    if (connection == IO_OBJECT_NULL) {
        return false;
    }

    kern_return_t result = IOHIDSetModifierLockState(connection, kIOHIDCapsLockState, enabled);
    IOServiceClose(connection);
    if (result != KERN_SUCCESS) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "IOHIDSetModifierLockState for Caps Lock failed: 0x%x",
                     static_cast<unsigned int>(result));
        return false;
    }
    return true;
}

void MacCapsLockMode::restoreState()
{
    if (!m_HasSavedState) {
        return;
    }

    if (writeState(m_PreviousState)) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Restored macOS Caps Lock state to %s",
                    m_PreviousState ? "on" : "off");
        m_HasSavedState = false;
        m_IsStreamingActive = false;
    }
}

void MacCapsLockMode::setStreamingActive(bool active)
{
    if (!active) {
        m_IsStreamingActive = false;
        restoreState();
        return;
    }

    if (m_IsStreamingActive) {
        return;
    }

    if (!m_HasSavedState) {
        if (!readState(m_PreviousState)) {
            return;
        }
        m_HasSavedState = true;
    }

    if (m_PreviousState && !writeState(false)) {
        restoreState();
        return;
    }

    m_IsStreamingActive = true;
}

void MacCapsLockMode::forceOff()
{
    if (m_IsStreamingActive) {
        writeState(false);
    }
}
