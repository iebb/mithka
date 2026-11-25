#include "system_fonts_channel.h"

#include <flutter/standard_method_codec.h>

#include <string>
#include <variant>
#include <vector>

#include "windows_font_catalog.h"

namespace {

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "listFonts") {
    const auto entries = LoadWindowsSystemFonts();
    flutter::EncodableList payload;
    payload.reserve(entries.size());
    for (const auto& entry : entries) {
      flutter::EncodableMap item;
      item[flutter::EncodableValue("family")] =
          flutter::EncodableValue(entry.family);
      item[flutter::EncodableValue("displayName")] =
          flutter::EncodableValue(entry.display_name);
      item[flutter::EncodableValue("isMonospace")] =
          flutter::EncodableValue(entry.is_monospace);
      payload.emplace_back(std::move(item));
    }
    result->Success(flutter::EncodableValue(std::move(payload)));
    return;
  }

  if (call.method_name() == "normalizeFontFamilies") {
    const auto* raw_list =
        call.arguments()
            ? std::get_if<flutter::EncodableList>(call.arguments())
            : nullptr;
    if (!raw_list) {
      result->Error("invalid_args", "Expected a list of font family names.");
      return;
    }
    std::vector<std::string> requested;
    requested.reserve(raw_list->size());
    for (const auto& value : *raw_list) {
      if (const auto* text = std::get_if<std::string>(&value)) {
        requested.push_back(*text);
      } else {
        requested.emplace_back();
      }
    }
    const auto normalized = NormalizeWindowsFontFamilies(requested);
    flutter::EncodableList payload;
    payload.reserve(normalized.size());
    for (const auto& item : normalized) {
      payload.emplace_back(item);
    }
    result->Success(flutter::EncodableValue(std::move(payload)));
    return;
  }

  result->NotImplemented();
}

}  // namespace

std::unique_ptr<SystemFontsChannel> SystemFontsChannel::Register(
    flutter::BinaryMessenger* messenger) {
  if (!messenger) {
    return nullptr;
  }
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "mithka/fonts",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(&HandleMethodCall);
  return std::unique_ptr<SystemFontsChannel>(
      new SystemFontsChannel(std::move(channel)));
}

SystemFontsChannel::SystemFontsChannel(
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
    : channel_(std::move(channel)) {}

SystemFontsChannel::~SystemFontsChannel() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}
