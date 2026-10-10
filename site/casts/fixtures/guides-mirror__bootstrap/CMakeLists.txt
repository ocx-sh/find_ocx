cmake_minimum_required(VERSION 3.25...4.4)
project(behind_a_mirror LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_bootstrap()
message(STATUS "ocx is ${OCX_EXECUTABLE}")
