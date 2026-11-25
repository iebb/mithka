#ifndef RUNNER_SYSTEM_FONTS_CHANNEL_H_
#define RUNNER_SYSTEM_FONTS_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Registers the `mithka/fonts` platform channel on the supplied binary
// messenger so both primary and multi-window Flutter engines can query local
// Windows DirectWrite font families.
class SystemFontsChannel {
 public:
  static std::unique_ptr<SystemFontsChannel> Register(
      flutter::BinaryMessenger* messenger);

  ~SystemFontsChannel();

  SystemFontsChannel(const SystemFontsChannel&) = delete;
  SystemFontsChannel& operator=(const SystemFontsChannel&) = delete;

 private:
  explicit SystemFontsChannel(
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SYSTEM_FONTS_CHANNEL_H_
