<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->
<!-- description: Run the tools of a workspace ocx.toml and ocx.lock from custom targets, tests and lazy groups. -->
# Run workspace tools from ocx.toml

Use `ocx_project` to turn a committed `ocx.toml` and `ocx.lock` into command lists that run your tools in custom targets, tests and groups.

## Declare tools and a group

Put tools in `[tools]` and rarely used tools in a group.

--8<-- "examples/project/ocx.toml" title="ocx.toml"

## Export the launchers

Call `ocx_project` with the tools you want as per-tool variables.

--8<-- "examples/project/CMakeLists.txt" from="^ocx_project\(NAME TOOLS" to="^ocx_project\(NAME TOOLS" title="examples/project/CMakeLists.txt"

`NAME TOOLS` gives `OCX_TOOLS_RUN` and `OCX_TOOLS_RUN_JQ`.
Without `NAME`, the variables are `OCX_PROJECT_RUN` and `OCX_PROJECT_RUN_JQ`.

The `ocx.toml` is found by the upward search, the lock is verified, and nothing is fetched yet.

## Use a launcher in a command

`OCX_TOOLS_RUN` is a plain CMake command list, so generator expressions such as `$<CONFIG>` work and you need no wrapper script.

--8<-- "examples/project/CMakeLists.txt" from="^add_custom_target\(validate" to="^\)$" title="CMakeLists.txt"

## Keep a group lazy

A group costs nothing until someone builds a target that uses it.

--8<-- "examples/project/CMakeLists.txt" from="^ocx_project\(NAME LINT" to="^\)$" title="CMakeLists.txt"

## Run a tool in a test

Use the per-tool variable as the test command.

--8<-- "examples/project/CMakeLists.txt" from="^add_test" to="data.json" title="CMakeLists.txt"

## Build and test

```console
cd examples/project
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

For the full signatures, see [`ocx_project`](../reference/commands.md).
Needs addressed: problems 1 and 2 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
