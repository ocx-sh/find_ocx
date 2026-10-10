# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

#[=[.rst:
Findocx
-------

Overview
^^^^^^^^

Finds the `OCX <https://ocx.sh>`_ CLI and provides it as an imported target.
The module works standalone on CMake 3.15 or later.
The provisioning commands :command:`ocx_project` and :command:`ocx_package` live in ``ocx.cmake``, which you add with ``include(ocx)``.

.. parsed-literal::

  find_package(ocx [<version>] [REQUIRED])

Both entry points resolve ``OCX_EXECUTABLE``, then ``PATH``, then the pinned bootstrap.
They differ only in the bootstrap default.
This module opts in, because find modules discover.
``ocx.cmake`` opts out, and ``OFF`` forbids the implicit download there.

Imported targets
^^^^^^^^^^^^^^^^

``ocx::ocx``
  Imported executable target for ``OCX_EXECUTABLE``.

Result variables
^^^^^^^^^^^^^^^^

``ocx_FOUND``, ``OCX_FOUND``
  True when the ocx CLI is found and satisfies the requested version.

``OCX_EXECUTABLE``
  Path of the ocx CLI.
  It is a cache variable and also the search hint.

``OCX_VERSION_STRING``
  Version that ``ocx version`` reports.

Hints
^^^^^

``OCX_EXECUTABLE``
  Set it to use a specific binary, for example one that :command:`ocx_bootstrap` provides.

``OCX_BOOTSTRAP``
  ``ON`` bootstraps the pinned ocx when none is found.
  ``ALWAYS`` skips the ``PATH`` search and always uses the pin.
  Both values need CMake 3.25 and an ``ocx.cmake`` next to ``Findocx.cmake``.

  .. versionchanged:: 0.4
    The bootstrap requires CMake 3.25.
    Release 0.3 required CMake 3.19.

Example
^^^^^^^

The tested project ``examples/find_package`` finds the ocx CLI.
Configure it with ``-DOCX_BOOTSTRAP=ON`` to bootstrap the pin when none is found.

.. code-block:: cmake

  find_package(ocx REQUIRED)

  message(STATUS "example: ocx ${OCX_VERSION_STRING} at ${OCX_EXECUTABLE}")
#]=]

if(NOT OCX_EXECUTABLE AND NOT "${OCX_BOOTSTRAP}" STREQUAL "ALWAYS")
  find_program(OCX_EXECUTABLE NAMES ocx DOC "Path to the ocx CLI")
endif()

if(NOT OCX_EXECUTABLE AND OCX_BOOTSTRAP)
  if(CMAKE_VERSION VERSION_LESS 3.25)
    message(
      WARNING
      "find_ocx: OCX_BOOTSTRAP requires CMake >= 3.25 (this is "
      "${CMAKE_VERSION}) - install ocx on PATH or set OCX_EXECUTABLE"
    )
  elseif(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/ocx.cmake")
    message(
      WARNING
      "find_ocx: OCX_BOOTSTRAP is set but ocx.cmake is not next to "
      "Findocx.cmake (${CMAKE_CURRENT_LIST_DIR})"
    )
  else()
    include("${CMAKE_CURRENT_LIST_DIR}/ocx.cmake")
    ocx_bootstrap()
  endif()
endif()

unset(OCX_VERSION_STRING)
if(OCX_EXECUTABLE AND EXISTS "${OCX_EXECUTABLE}")
  # OCX_QUIET=0: an ambient OCX_QUIET=1 would blank the version output.
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env OCX_QUIET=0 "${OCX_EXECUTABLE}" version
    RESULT_VARIABLE __ocx_find_rc
    OUTPUT_VARIABLE __ocx_find_out
    ERROR_QUIET
    ENCODING UTF-8
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
find_package_handle_standard_args(ocx REQUIRED_VARS OCX_EXECUTABLE VERSION_VAR OCX_VERSION_STRING)

if(ocx_FOUND AND NOT TARGET ocx::ocx)
  add_executable(ocx::ocx IMPORTED)
  set_target_properties(ocx::ocx PROPERTIES IMPORTED_LOCATION "${OCX_EXECUTABLE}")
endif()

mark_as_advanced(OCX_EXECUTABLE)
