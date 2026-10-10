# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Example toolchain file: provisions the content of the target platform from
# the same ocx.lock as the host build and hands it to CMake's find_*() commands.
#
#   cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake

# region toolchain
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# CMake reads a toolchain file again for every compiler probe. An identical
# ocx_project call is a no-op on re-entry, so no guard is needed.
# In your own project, vendor ocx.cmake into cmake/ and use that directory here.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/../..")
include(ocx)
ocx_project(NAME TARGET TOML "${CMAKE_CURRENT_LIST_DIR}/ocx.toml" PLATFORM linux/arm64)

list(APPEND CMAKE_FIND_ROOT_PATH ${OCX_TARGET_PATHS})
# endregion
