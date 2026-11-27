#include "macfunctionkeymode.h"

#include <CoreFoundation/CFNumber.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

#include <SDL.h>

namespace {

constexpr int kMediaKeyMode = 0;
constexpr int kFunctionKeyMode = 1;
constexpr char kHidSystemPath[] = "IOService:/IOResources/IOHIDSystem";

io_service_t getHidSystemService()
{
    io_service_t service = IORegistryEntryFromPath(kIOMainPortDefault, kHidSystemPath);
    if (service == IO_OBJECT_NULL) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to find IOHIDSystem in the IORegistry");
    }
    return service;
}

}

bool MacFunctionKeyMode::readMode(int& mode)
{
    io_service_t service = getHidSystemService();
    if (service == IO_OBJECT_NULL) {
        return false;
    }

    CFTypeRef parameters = IORegistryEntryCreateCFProperty(service,
                                                            CFSTR("HIDParameters"),
                                                            kCFAllocatorDefault,
                                                            0);
    IOObjectRelease(service);
    if (parameters == nullptr || CFGetTypeID(parameters) != CFDictionaryGetTypeID()) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to read IOHIDSystem HIDParameters");
        if (parameters != nullptr) {
            CFRelease(parameters);
        }
        return false;
    }

    CFTypeRef value = CFDictionaryGetValue(static_cast<CFDictionaryRef>(parameters),
                                           CFSTR(kIOHIDFKeyModeKey));
    int currentMode;
    bool success = value != nullptr &&
                   CFGetTypeID(value) == CFNumberGetTypeID() &&
                   CFNumberGetValue(static_cast<CFNumberRef>(value),
                                    kCFNumberIntType,
                                    &currentMode) &&
                   (currentMode == kMediaKeyMode || currentMode == kFunctionKeyMode);
    if (success) {
        mode = currentMode;
    }
    else {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to read a valid HIDFKeyMode value");
    }

    CFRelease(parameters);
    return success;
}

bool MacFunctionKeyMode::writeMode(int mode)
{
    io_service_t service = getHidSystemService();
    if (service == IO_OBJECT_NULL) {
        return false;
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
        return false;
    }

    CFNumberRef value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &mode);
    if (value == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to create the HIDFKeyMode value");
        IOServiceClose(connection);
        return false;
    }

    result = IOHIDSetCFTypeParameter(connection, CFSTR(kIOHIDFKeyModeKey), value);
    CFRelease(value);
    IOServiceClose(connection);
    if (result != KERN_SUCCESS) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "IOHIDSetCFTypeParameter for HIDFKeyMode failed: 0x%x",
                     static_cast<unsigned int>(result));
        return false;
    }

    return true;
}

void MacFunctionKeyMode::restoreMode()
{
    if (!m_HasSavedMode) {
        return;
    }

    if (writeMode(m_PreviousMode)) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Restored macOS F-key mode to %d",
                    m_PreviousMode);
        m_HasSavedMode = false;
        m_IsStreamingActive = false;
    }
}

void MacFunctionKeyMode::setStreamingActive(bool active)
{
    if (!active) {
        m_IsStreamingActive = false;
        restoreMode();
        return;
    }

    if (m_IsStreamingActive) {
        return;
    }

    if (!m_HasSavedMode) {
        if (!readMode(m_PreviousMode)) {
            return;
        }
        m_HasSavedMode = true;
    }

    if (m_PreviousMode != kFunctionKeyMode && !writeMode(kFunctionKeyMode)) {
        restoreMode();
        return;
    }

    if (m_PreviousMode != kFunctionKeyMode) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Temporarily switched macOS F-key mode from %d to %d",
                    m_PreviousMode,
                    kFunctionKeyMode);
    }
    m_IsStreamingActive = true;
}
