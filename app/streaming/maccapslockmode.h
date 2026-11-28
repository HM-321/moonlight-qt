#pragma once

class MacCapsLockMode
{
public:
    void setStreamingActive(bool active);
    void forceOff();

private:
    bool readState(bool& enabled);
    bool writeState(bool enabled);
    void restoreState();

    bool m_HasSavedState = false;
    bool m_IsStreamingActive = false;
    bool m_PreviousState = false;
};
