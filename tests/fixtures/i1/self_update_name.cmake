# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors
#
# Child of module_checks.cmake (script mode): the self-update entry is the
# public command ocx_self_update (no private __ name) and rejects arguments.
# Offline: the call fails before any download.
#
#   cmake -DCMAKE_MODULE_PATH=<repo> -P self_update_name.cmake

include(ocx)

if(NOT COMMAND ocx_self_update)
  message(FATAL_ERROR "self_update_name: ocx_self_update is not defined")
endif()
if(COMMAND __ocx_self_update)
  message(FATAL_ERROR "self_update_name: the private __ocx_self_update still exists")
endif()

ocx_self_update(BOGUS)
