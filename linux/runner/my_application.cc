#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <pango/pangocairo.h>

#include <algorithm>
#include <cctype>
#include <set>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include <multi_window_manager/multi_window_manager_plugin.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static std::string trim_ascii_whitespace(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         std::isspace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  size_t end = value.size();
  while (end > start &&
         std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return value.substr(start, end - start);
}

static FlValue* list_system_fonts() {
  FlValue* list = fl_value_new_list();
  PangoFontMap* font_map = pango_cairo_font_map_get_default();
  if (font_map == nullptr) {
    return list;
  }

  PangoFontFamily** families = nullptr;
  int n_families = 0;
  pango_font_map_list_families(font_map, &families, &n_families);

  std::set<std::string> unique_names;
  for (int i = 0; i < n_families; ++i) {
    const char* name = pango_font_family_get_name(families[i]);
    if (name == nullptr) {
      continue;
    }
    std::string trimmed = trim_ascii_whitespace(name);
    if (!trimmed.empty()) {
      unique_names.insert(std::move(trimmed));
    }
  }
  g_free(families);

  std::vector<std::string> sorted(unique_names.begin(), unique_names.end());
  std::sort(sorted.begin(), sorted.end(),
            [](const std::string& a, const std::string& b) {
              const size_t min_len = std::min(a.size(), b.size());
              for (size_t i = 0; i < min_len; ++i) {
                const int ca =
                    std::tolower(static_cast<unsigned char>(a[i]));
                const int cb =
                    std::tolower(static_cast<unsigned char>(b[i]));
                if (ca != cb) return ca < cb;
              }
              if (a.size() != b.size()) return a.size() < b.size();
              return a < b;
            });

  for (const auto& name : sorted) {
    fl_value_append_take(list, fl_value_new_string(name.c_str()));
  }
  return list;
}

static void fonts_method_call_cb(FlMethodChannel* channel,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  (void)channel;
  (void)user_data;
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "listFonts") == 0) {
    g_autoptr(FlValue) result = list_system_fonts();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void register_system_fonts_channel(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry,
                                                  "SystemFontsPlugin");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "mithka/fonts",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, fonts_method_call_cb,
                                            nullptr, nullptr);
  g_object_set_data_full(G_OBJECT(registry), "mithka-fonts-channel", channel,
                         g_object_unref);
}

static void register_all_plugins(FlPluginRegistry* registry) {
  fl_register_plugins(registry);
  register_system_fonts_channel(registry);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Mithka paints its own title bar and caption buttons on Linux (see
  // DesktopWindowControls), so this window has to be undecorated from the
  // moment it is created.
  //
  // The stock runner installs a GtkHeaderBar whenever it cannot prove it is on
  // a non-GNOME X11 session - which on Wayland is always, because the
  // GDK_IS_X11_SCREEN guard never matches. Dart then takes the decoration back
  // off during startup (setTitleBarStyle(hidden)). That costs a second
  // geometry negotiation after the window is already on screen: the content
  // area grows by the header bar height and GDK's CSD shadow extents drop to
  // zero, so GTK asks the Flutter view to resize while the engine is still
  // rendering its first frames.
  //
  // On Wayland that race does not settle. FlView gives up waiting ("Timed out
  // waiting for OpenGL frame of size WxH (have W'xH')") and keeps the stale
  // frame, so the Dart side goes on laying out against a viewport that is
  // wider than the real window: the maximize and close buttons land past the
  // right edge where they cannot be clicked, and the strip they should have
  // covered is left unpainted. Never installing the header bar keeps one
  // window size in play for the whole session.
  gtk_window_set_title(window, "Mithka");
  gtk_window_set_decorated(window, FALSE);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  register_all_plugins(FL_PLUGIN_REGISTRY(view));
  multi_window_manager_linux_init(GTK_APPLICATION(application),
                                  register_all_plugins);
  multi_window_manager_linux_detach_flutter_quit_on_window_close(window, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
