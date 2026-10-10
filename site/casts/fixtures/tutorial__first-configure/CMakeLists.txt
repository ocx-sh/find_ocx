cmake_minimum_required(VERSION 3.25...4.4)
project(hello_jq LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME TOOLS BINS jq)
add_custom_target(validate ALL
  COMMAND ${OCX_TOOLS_RUN} jq -n -e "true"
  VERBATIM)
