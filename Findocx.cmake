# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

#[=[.rst:
Findocx
-------

Finds the `OCX <https://ocx.sh>`_ CLI::

  find_package(ocx [<version>] [REQUIRED])

Result variables and targets:

``ocx_FOUND`` / ``OCX_FOUND``
  True when the ocx CLI was found (and satisfies the requested version).
``OCX_EXECUTABLE``
  Path to the ocx CLI (cache; also the search hint).
``OCX_VERSION_STRING``
  Version reported by ``ocx version``.
``ocx::ocx``
  Imported executable target.

Hints: set ``OCX_EXECUTABLE`` (e.g. via :command:`ocx_bootstrap` from the
sibling ``ocx.cmake``) to use a specific binary. With ``OCX_BOOTSTRAP=ON``
this module bootstraps the pinned ocx itself when none is found, and with
``OCX_BOOTSTRAP=ALWAYS`` it skips the ``PATH`` search and always uses the
pin (both require CMake 3.19 and ``ocx.cmake`` next to this file)::

  find_package(ocx REQUIRED)   # -DOCX_BOOTSTRAP=ON => zero-setup corporate UX

Both entry points resolve ``OCX_EXECUTABLE``, then ``PATH``, then the
pinned bootstrap — they differ only in the bootstrap default: opt-*in*
here (find modules discover), opt-*out* in ``ocx.cmake`` (``OFF`` forbids
the implicit download there).

This find module works standalone on CMake 3.15+. The provisioning
commands (:command:`ocx_project`, :command:`ocx_package`) live in
``ocx.cmake`` — ``include(ocx)``.
#]=]

if(NOT OCX_EXECUTABLE AND NOT "${OCX_BOOTSTRAP}" STREQUAL "ALWAYS")
  find_program(OCX_EXECUTABLE NAMES ocx DOC "Path to the ocx CLI")
endif()

if(NOT OCX_EXECUTABLE AND OCX_BOOTSTRAP)
  if(CMAKE_VERSION VERSION_LESS 3.19)
    message(WARNING
      "find_ocx: OCX_BOOTSTRAP requires CMake >= 3.19 (this is "
      "${CMAKE_VERSION}) - install ocx on PATH or set OCX_EXECUTABLE")
  elseif(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/ocx.cmake")
    message(WARNING
      "find_ocx: OCX_BOOTSTRAP is set but ocx.cmake is not next to "
      "Findocx.cmake (${CMAKE_CURRENT_LIST_DIR})")
  else()
    include("${CMAKE_CURRENT_LIST_DIR}/ocx.cmake")
    ocx_bootstrap()
  endif()
endif()

unset(OCX_VERSION_STRING)
if(OCX_EXECUTABLE AND EXISTS "${OCX_EXECUTABLE}")
  execute_process(
    COMMAND "${OCX_EXECUTABLE}" version
    RESULT_VARIABLE __ocx_find_rc
    OUTPUT_VARIABLE __ocx_find_out
    ERROR_QUIET
  )
  if(__ocx_find_rc EQUAL 0)
    string(STRIP "${__ocx_find_out}" __ocx_find_out)
    if(__ocx_find_out MATCHES "^([0-9]+\\.[0-9]+\\.[0-9]+[^ \t\n]*)")
      set(OCX_VERSION_STRING "${CMAKE_MATCH_1}")
    endif()
  endif()
  unset(__ocx_find_rc)
  unset(__ocx_find_out)
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(ocx
  REQUIRED_VARS OCX_EXECUTABLE
  VERSION_VAR OCX_VERSION_STRING
)

if(ocx_FOUND AND NOT TARGET ocx::ocx)
  add_executable(ocx::ocx IMPORTED)
  set_target_properties(ocx::ocx PROPERTIES
    IMPORTED_LOCATION "${OCX_EXECUTABLE}")
endif()

mark_as_advanced(OCX_EXECUTABLE)
