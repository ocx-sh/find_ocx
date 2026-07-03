Examples
========

All examples live in `examples/
<https://github.com/ocx-sh/find_ocx/tree/main/examples>`_ and are built and
tested on Linux, macOS, and Windows in CI — the sources below are included
verbatim.

Workspace toolchain (``ocx_project``)
-------------------------------------

A committed ``ocx.toml`` + ``ocx.lock`` pair describes the toolchain; CMake
turns it into launcher variables. Tools materialize lazily on first
execution, and groups only when a target that uses them is built.

.. literalinclude:: ../examples/project/ocx.toml
   :language: toml
   :caption: examples/project/ocx.toml

.. literalinclude:: ../examples/project/CMakeLists.txt
   :caption: examples/project/CMakeLists.txt
   :start-at: cmake_minimum_required

Highlights:

* The ``ocx.toml`` is found by the upward search, the lock is verified,
  nothing is fetched yet.
* ``NAME`` picks the result-variable prefix: ``NAME TOOLS`` →
  ``OCX_TOOLS_RUN`` / ``OCX_TOOLS_RUN_JQ`` (``NAME`` defaults to
  ``PROJECT``).
* :variable:`OCX_<NAME>_RUN` is a plain CMake command list — generator
  expressions like ``$<CONFIG>`` compose naturally, no wrapper scripts.
* The ``lint`` group costs nothing until someone builds the ``lint`` target.

Ad-hoc packages (``ocx_package``)
---------------------------------

No project file at all — pull straight from the registry, floating or
digest-pinned per platform, with an optional ``<name>_ROOT`` export that
makes a later ``find_package()``/``find_library()`` search the
OCX-provisioned content (CMP0074).

.. literalinclude:: ../examples/package/CMakeLists.txt
   :caption: examples/package/CMakeLists.txt
   :start-at: cmake_minimum_required

Highlights:

* Floating + ``PULL``: resolved eagerly at configure time; the log prints
  the digest to copy into ``PINS`` for reproducibility.
* ``PINS`` + lazy: fully reproducible, and nothing is downloaded until the
  first build-time execution.
* ``INDEX`` + a committed snapshot: frozen tag resolution (rules_ocx-style)
  — the third pinning mechanism next to ``PINS`` and ``@sha256:`` digests,
  refreshed deliberately via :command:`ocx_index_update_command`.
* Reconfigures are memoized — with unchanged inputs no ``ocx`` process is
  spawned at all.

Classic discovery (``find_package``)
------------------------------------

The find-module entry point for projects that want a system ocx to win:
``PATH`` / ``-DOCX_EXECUTABLE`` first, pinned bootstrap only as the
explicit ``-DOCX_BOOTSTRAP=ON`` fallback.

.. literalinclude:: ../examples/find_package/CMakeLists.txt
   :caption: examples/find_package/CMakeLists.txt
   :start-at: cmake_minimum_required

Running them
------------

.. code-block:: console

   cd examples/project        # or examples/package
   cmake -S . -B build
   cmake --build build
   ctest --test-dir build --output-on-failure

For CI, add ``-DOCX_PULL=ON`` to materialize everything at configure time.
