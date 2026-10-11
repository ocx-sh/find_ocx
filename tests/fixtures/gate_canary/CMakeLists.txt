# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture (negative): a configure that must FAIL under the leg's gate. Proves
# the gate is live on this binary - exit 0 here means -Werror silently did
# nothing and every other test's gate proves nothing.
#   -DCANARY=author       an author warning
#   -DCANARY=deprecation  a deprecation warning

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_gate_canary LANGUAGES NONE)

if(CANARY STREQUAL "deprecation")
  message(DEPRECATION "gate canary")
else()
  message(AUTHOR_WARNING "gate canary")
endif()
