private func setupSubscriptions() {
    duckPlayer.mediaControlPublisher.sink { [weak self] pause in
        print("DP: Received mediaControl update: \(pause)")
        guard let self = self, let broker = self.broker, let webView = self.webView else {
            print("DP: Error: Broker or webView not available for mediaControl update.")
            return
        }
        print("DP: Sending Broker message onMediaControl: \(pause)")
        broker.push(method: "onMediaControl", params: ["pause": pause], for: self, into: webView)
    }
    .store(in: &cancellables)

    duckPlayer.serpNotificationPublisher.sink { [weak self] enabled in
        print("DP: Received serpNotification update: \(enabled)")
        guard let self = self, let broker = self.broker, let webView = self.webView else {
            print("DP: Error: Broker or webView not available for serpNotification update.")
            return
        }
        print("DP: Sending Broker message onSerpNotification: \(enabled)")
        broker.push(method: "onSerpNotification", params: ["enabled": enabled], for: self, into: webView)
    }
    .store(in: &cancellables)

    duckPlayer.muteAudioPublisher.sink { [weak self] mute in
        print("DP: Received muteAudio update: \(mute)")
        guard let self = self, let broker = self.broker, let webView = self.webView else {
            print("DP: Error: Broker or webView not available for muteAudio update.")
            return
        }
        print("DP: Sending Broker message onMuteAudio: \(mute)")
        broker.push(method: "onMuteAudio", params: ["mute": mute], for: self, into: webView)
    }
    .store(in: &cancellables)
}

// MARK: - Subfeature 