<!-- doc_type: readme -->

# find_ocx

find_ocx lets a CMake build run pinned, sha256-verified command-line tools such as `jq`, `ninja` or `shellcheck` without installing them.
It is a pair of CMake files that use the [OCX](https://ocx.sh) package manager to fetch each tool at the digest your `ocx.lock` fixes.

A build that needs `jq` usually says "install jq first" or takes whatever `find_program` finds on the host.
Every machine then runs its own version.
With find_ocx a teammate or a CI runner builds with nothing installed beyond CMake.

## Quick start

You need CMake 3.25 or later, network access to the OCX registry or a mirror, and the [`ocx` CLI](https://ocx.sh/install/) once, to write the lock file.

1. Copy `Findocx.cmake` and `ocx.cmake` from the [release assets](https://github.com/ocx-sh/find_ocx/releases) into a `cmake/` directory of your repository.
2. List the tool in `ocx.toml` and run `ocx lock` to write `ocx.lock`.
3. Add the tool to your `CMakeLists.txt`.

```toml
[tools]
jq = "ocx.sh/jqlang/jq:latest"
```

<!-- doc: readme/quick-start -->
```cmake
cmake_minimum_required(VERSION 3.25...4.4)
project(hello_jq LANGUAGES NONE)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(ocx)

ocx_project(NAME TOOLS BINS jq)

add_custom_target(show_jq ALL COMMAND ${OCX_TOOLS_RUN} jq --version VERBATIM)
```

Then `cmake -S . -B build && cmake --build build` ends with a line like `jq-1.8.2`.
The [tutorial](https://ocx.sh/integrations/cmake/tutorial/) walks through this project step by step.

## Documentation

Guides, concepts, the troubleshooting pages and the command and variable reference are at <https://ocx.sh/integrations/cmake/>.

## Examples

The tested example projects in [`examples/`](examples) show each entry point.

- [`examples/tutorial`](examples/tutorial): the project above, run by the tutorial recording
- [`examples/project`](examples/project): a workspace toolchain with groups, generator expressions and ctest
- [`examples/package`](examples/package): one package without a project file, floating, pinned and frozen
- [`examples/frozen_index`](examples/frozen_index): a committed index snapshot and a deliberate refresh target
- [`examples/find_package`](examples/find_package): classic `find_package(ocx)` discovery

## Testing

The harness dogfoods find_ocx.
The CMake versions under test are provisioned as OCX packages (`ocx.sh/kitware/cmake:<tag>`) through `ocx_package()` itself.
Each fixture runs on every version through `ctest --build-and-test` on Linux, macOS and Windows.

```sh
ocx exec -- task verify
```

## License

Apache-2.0. See [LICENSE](LICENSE).
