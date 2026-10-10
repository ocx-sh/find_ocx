# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Fixture: a registry with a port is stored by ocx as <index>/localhost_5001/p/...,
# so the snapshot leaf of localhost:5001/foo is watched like any other.

cmake_minimum_required(VERSION 3.25...4.4)
project(fixture_i3_index_port LANGUAGES NONE)

include(ocx)

ocx_package(NAME PORT PACKAGE localhost:5001/foo:1 INDEX "${CMAKE_CURRENT_SOURCE_DIR}/portindex")

get_property(deps DIRECTORY PROPERTY CMAKE_CONFIGURE_DEPENDS)
set(leaf "${CMAKE_CURRENT_SOURCE_DIR}/portindex/localhost_5001/p/foo.json")
list(FIND deps "${leaf}" found)
if(found EQUAL -1)
  message(FATAL_ERROR "i3 index_port fixture: ${leaf} is not a configure dependency (${deps})")
endif()
