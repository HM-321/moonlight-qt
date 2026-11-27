#pragma once

class MacFunctionKeyMode
{
public:
    void setStreamingActive(bool active);

private:
    bool readMode(int& mode);
    bool writeMode(int mode);
    void restoreMode();

    bool m_HasSavedMode = false;
    bool m_IsStreamingActive = false;
    int m_PreviousMode = 0;
};
