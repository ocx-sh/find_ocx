cmake_minimum_required(VERSION 3.25...4.4)
project(cross_build LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME WIN PLATFORM windows/amd64 BINS jq)
file(GLOB files RELATIVE "${OCX_WIN_PATHS}" "${OCX_WIN_PATHS}/*")
message(STATUS "windows/amd64 content: ${files}")
