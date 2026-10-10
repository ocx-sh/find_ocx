# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

#[=[.rst:
Findocx
-------

Overview
^^^^^^^^

Finds the `OCX <https://ocx.sh>`_ CLI and provides it as an imported target.
The module is written to work standalone on CMake 3.15 or later, but the tests run it on 3.25 and later only.
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
  A path that does not exist, and an ocx that fails ``ocx version``, count as not found.

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
  Empty or unset means ``OFF``, and a value other than ``ON``, ``OFF`` or ``ALWAYS`` is an error.

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

# OCX_BOOTSTRAP: ON, OFF or ALWAYS (the CMake booleans in any case); empty or
# unset means OFF here. A typo must not mean "off" silently.
set(__ocx_bootstrap "OFF")
if(DEFINED OCX_BOOTSTRAP AND NOT "${OCX_BOOTSTRAP}" STREQUAL "")
  string(TOUPPER "${OCX_BOOTSTRAP}" __ocx_value)
  if(__ocx_value STREQUAL "ALWAYS")
    set(__ocx_bootstrap "ALWAYS")
  elseif(__ocx_value MATCHES "^(ON|TRUE|YES|Y|1)$")
    set(__ocx_bootstrap "ON")
  elseif(__ocx_value MATCHES "^(OFF|FALSE|NO|N|0)$")
    set(__ocx_bootstrap "OFF")
  else()
    message(FATAL_ERROR "find_ocx: OCX_BOOTSTRAP='${OCX_BOOTSTRAP}' is not ON, OFF or ALWAYS")
  endif()
  unset(__ocx_value)
endif()

# A path this module chose itself on an earlier configure (PATH hit or
# bootstrap) is chosen again, so OCX_BOOTSTRAP=ALWAYS or a new pin reaches an
# existing build directory. find_program skips a variable that is already set,
# so an empty or NOTFOUND value is unset first. A non-empty path that does not
# exist is a mistake, not a search hint: the module is not found.
set(__ocx_given "${OCX_EXECUTABLE}")
if(__ocx_given MATCHES "-NOTFOUND$" OR __ocx_given STREQUAL "$CACHE{__OCX_AUTO_EXECUTABLE}")
  set(__ocx_given "")
endif()
if(NOT __ocx_given STREQUAL "" AND NOT EXISTS "${__ocx_given}")
  message(
    WARNING
    "find_ocx: OCX_EXECUTABLE='${__ocx_given}' does not exist - clear it with "
    "-DOCX_EXECUTABLE= to search PATH"
  )
  # A normal variable hides the cached value from this search only: the
  # cache keeps the mistake visible to a later include(ocx), which rejects it.
  set(OCX_EXECUTABLE "OCX_EXECUTABLE-NOTFOUND")
  set(__ocx_shadowed TRUE)
elseif(__ocx_given STREQUAL "")
  unset(OCX_EXECUTABLE CACHE)
  unset(OCX_EXECUTABLE)
  if(NOT __ocx_bootstrap STREQUAL "ALWAYS")
    find_program(OCX_EXECUTABLE NAMES ocx DOC "Path to the ocx CLI")
  endif()
  if(NOT OCX_EXECUTABLE AND NOT __ocx_bootstrap STREQUAL "OFF")
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
  if(OCX_EXECUTABLE)
    set(
      __OCX_AUTO_EXECUTABLE
      "${OCX_EXECUTABLE}"
      CACHE INTERNAL
      "find_ocx: ocx chosen by the module"
    )
  endif()
endif()
unset(__ocx_given)
unset(__ocx_bootstrap)

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
# A binary whose 'ocx version' fails leaves OCX_VERSION_STRING unset: not found.
set(__ocx_required OCX_EXECUTABLE)
if(OCX_EXECUTABLE)
  list(APPEND __ocx_required OCX_VERSION_STRING)
endif()
find_package_handle_standard_args(
  ocx
  REQUIRED_VARS ${__ocx_required}
  VERSION_VAR OCX_VERSION_STRING
)
unset(__ocx_required)

if(ocx_FOUND AND NOT TARGET ocx::ocx)
  add_executable(ocx::ocx IMPORTED)
  set_target_properties(ocx::ocx PROPERTIES IMPORTED_LOCATION "${OCX_EXECUTABLE}")
endif()

if(__ocx_shadowed)
  unset(OCX_EXECUTABLE)
  unset(__ocx_shadowed)
endif()

mark_as_advanced(OCX_EXECUTABLE)
