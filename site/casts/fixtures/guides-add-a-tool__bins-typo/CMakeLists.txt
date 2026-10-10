cmake_minimum_required(VERSION 3.25...4.4)
project(bins_typo LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME TOOLS BINS jqq)
