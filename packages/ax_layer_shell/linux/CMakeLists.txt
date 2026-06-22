cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "ax_layer_shell")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.13...3.24)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK_LAYER_SHELL REQUIRED IMPORTED_TARGET gtk-layer-shell-0)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)

list(APPEND PLUGIN_SOURCES
  "ax_layer_shell_plugin.cc"
  "window_registry.cc"
  "layer_shell_handler.cc"
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK_LAYER_SHELL)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::WAYLAND_CLIENT)

set(ax_layer_shell_bundled_libraries "" PARENT_SCOPE)
