#include "maccapslockmapping.h"

#include "SDL_compat.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>

namespace {

constexpr quint64 kCapsLockHidUsage = 0x700000039ULL;

quint64 modifierHidUsage(SDL_Scancode scancode)
{
    switch (scancode) {
    case SDL_SCANCODE_LCTRL:
        return 0x7000000E0ULL;
    case SDL_SCANCODE_LSHIFT:
        return 0x7000000E1ULL;
    case SDL_SCANCODE_LALT:
        return 0x7000000E2ULL;
    case SDL_SCANCODE_LGUI:
        return 0x7000000E3ULL;
    case SDL_SCANCODE_RCTRL:
        return 0x7000000E4ULL;
    case SDL_SCANCODE_RSHIFT:
        return 0x7000000E5ULL;
    case SDL_SCANCODE_RALT:
        return 0x7000000E6ULL;
    case SDL_SCANCODE_RGUI:
        return 0x7000000E7ULL;
    default:
        return 0;
    }
}

bool runHidutil(const QStringList& arguments, QByteArray* standardOutput)
{
    QProcess process;
    process.start(QStringLiteral("/usr/bin/hidutil"), arguments);
    if (!process.waitForStarted(2000) || !process.waitForFinished(5000)) {
        process.kill();
        process.waitForFinished();
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "hidutil did not finish: %s",
                     qPrintable(process.errorString()));
        return false;
    }

    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "hidutil failed: %s",
                     process.readAllStandardError().constData());
        return false;
    }

    if (standardOutput != nullptr) {
        *standardOutput = process.readAllStandardOutput();
    }
    return true;
}

bool parseHidMappings(const QByteArray& output, QJsonArray& mappings)
{
    const QRegularExpression entryPattern(QStringLiteral("\\{([^}]*)\\}"));
    const QRegularExpression sourcePattern(
        QStringLiteral("HIDKeyboardModifierMappingSrc\\s*=\\s*(0[xX][0-9A-Fa-f]+|[0-9]+)\\s*;"));
    const QRegularExpression targetPattern(
        QStringLiteral("HIDKeyboardModifierMappingDst\\s*=\\s*(0[xX][0-9A-Fa-f]+|[0-9]+)\\s*;"));

    const QString text = QString::fromUtf8(output);
    auto entries = entryPattern.globalMatch(text);
    while (entries.hasNext()) {
        const QString entryText = entries.next().captured(1);
        const auto sourceMatch = sourcePattern.match(entryText);
        const auto targetMatch = targetPattern.match(entryText);
        if (!sourceMatch.hasMatch() || !targetMatch.hasMatch()) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "Unable to parse hidutil UserKeyMapping entry");
            return false;
        }

        bool sourceOk = false;
        bool targetOk = false;
        const quint64 source = sourceMatch.captured(1).toULongLong(&sourceOk, 0);
        const quint64 target = targetMatch.captured(1).toULongLong(&targetOk, 0);
        if (!sourceOk || !targetOk) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "Invalid numeric value in hidutil UserKeyMapping");
            return false;
        }

        QJsonObject entry;
        entry.insert(QStringLiteral("HIDKeyboardModifierMappingSrc"),
                     static_cast<double>(source));
        entry.insert(QStringLiteral("HIDKeyboardModifierMappingDst"),
                     static_cast<double>(target));
        mappings.append(entry);
    }

    static const QRegularExpression emptyArrayPattern(QStringLiteral("^\\(\\s*\\)$"));
    if (!mappings.isEmpty() || emptyArrayPattern.match(text.trimmed()).hasMatch()) {
        return true;
    }

    SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                 "Unexpected hidutil UserKeyMapping output: %s",
                 output.constData());
    return false;
}

QByteArray serializeHidMappings(const QJsonArray& mappings)
{
    QJsonObject properties;
    properties.insert(QStringLiteral("UserKeyMapping"), mappings);
    return QJsonDocument(properties).toJson(QJsonDocument::Compact);
}

bool writeHidMappings(const QByteArray& json)
{
    return runHidutil({QStringLiteral("property"),
                       QStringLiteral("--set"),
                       QString::fromUtf8(json)},
                      nullptr);
}

}

MacCapsLockMapping::~MacCapsLockMapping()
{
    restore();
}

bool MacCapsLockMapping::activate(SDL_Scancode targetKey)
{
    const quint64 targetUsage = modifierHidUsage(targetKey);
    if (targetUsage == 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Cannot map Caps Lock to unsupported HID modifier scancode %d",
                     targetKey);
        return false;
    }

    if (m_IsActive && m_TargetKey == targetKey) {
        return true;
    }
    if (m_HasSavedMappings) {
        restore();
        if (m_HasSavedMappings) {
            return false;
        }
    }

    QByteArray currentOutput;
    if (!runHidutil({QStringLiteral("property"),
                     QStringLiteral("--get"),
                     QStringLiteral("UserKeyMapping")},
                    &currentOutput)) {
        return false;
    }

    QJsonArray currentMappings;
    if (!parseHidMappings(currentOutput, currentMappings)) {
        return false;
    }

    m_PreviousMappings = serializeHidMappings(currentMappings);
    m_HasSavedMappings = true;

    QJsonArray activeMappings;
    for (const QJsonValue& value : currentMappings) {
        const QJsonObject entry = value.toObject();
        if (static_cast<quint64>(entry.value(QStringLiteral("HIDKeyboardModifierMappingSrc")).toDouble()) !=
                kCapsLockHidUsage) {
            activeMappings.append(value);
        }
    }

    QJsonObject capsLockMapping;
    capsLockMapping.insert(QStringLiteral("HIDKeyboardModifierMappingSrc"),
                           static_cast<double>(kCapsLockHidUsage));
    capsLockMapping.insert(QStringLiteral("HIDKeyboardModifierMappingDst"),
                           static_cast<double>(targetUsage));
    activeMappings.append(capsLockMapping);

    if (!writeHidMappings(serializeHidMappings(activeMappings))) {
        restore();
        return false;
    }

    m_IsActive = true;
    m_TargetKey = targetKey;
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Temporarily mapped macOS Caps Lock to SDL scancode %d",
                targetKey);
    return true;
}

void MacCapsLockMapping::restore()
{
    if (!m_HasSavedMappings) {
        return;
    }

    if (!writeHidMappings(m_PreviousMappings)) {
        return;
    }

    m_PreviousMappings.clear();
    m_HasSavedMappings = false;
    m_IsActive = false;
    m_TargetKey = SDL_SCANCODE_UNKNOWN;
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Restored previous macOS HID keyboard mapping");
}
