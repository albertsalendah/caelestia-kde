// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QStringList>
#include <memory>

namespace caelestia::services {

class PipewireStreamWatcherPrivate;

class PipewireStreamWatcher : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // The PipeWire thread only runs while this is true (and CAELESTIA_STREAM_WATCHER is not "0").
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool streaming READ isStreaming NOTIFY streamingChanged)
    Q_PROPERTY(int streamCount READ streamCount NOTIFY streamCountChanged)
    Q_PROPERTY(QStringList activeStreams READ activeStreams NOTIFY activeStreamsChanged)

public:
    explicit PipewireStreamWatcher(QObject* parent = nullptr);
    ~PipewireStreamWatcher() override;

    [[nodiscard]] bool isEnabled() const;
    void setEnabled(bool enabled);

    [[nodiscard]] bool isStreaming() const;
    [[nodiscard]] int streamCount() const;
    [[nodiscard]] QStringList activeStreams() const;

    Q_INVOKABLE void rescan();

signals:
    void enabledChanged(bool enabled);
    void streamingChanged(bool streaming);
    void streamCountChanged(int count);
    void activeStreamsChanged();

private:
    friend class PipewireStreamWatcherPrivate;
    std::unique_ptr<PipewireStreamWatcherPrivate> d;
};

} // namespace caelestia::services
