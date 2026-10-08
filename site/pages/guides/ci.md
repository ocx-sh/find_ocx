<!-- doc_type: how-to -->
<!-- doc_tier: integration -->
<!-- description: Run the same pinned tools on a laptop and on Linux, macOS and Windows CI runners. -->
# Reproduce the build in CI

Use these settings so a CI runner on Linux, macOS or Windows runs the same `ocx` and the same tool versions as your laptop.

## Materialize everything at configure time

Configure with `-DOCX_PULL=ON`.
Every `ocx_project` and `ocx_package` call then installs its content during configure, so a missing package fails the job early and warms the caches.

## Run one pinned ocx everywhere

Configure with `-DOCX_BOOTSTRAP=ALWAYS`.
The `PATH` search is skipped, so every developer and runner executes the identical pinned binary.
Pair it with `OCX_INSTALL_VERSION` to choose the version.

## Keep the bootstrap cache on the runner

The bootstrapped binary goes to a per-machine cache.
On runners where the home directory is unreliable, point `OCX_BOOTSTRAP_CACHE` into the workspace and restore it with your CI cache.

## Run the examples on three platforms

find_ocx runs its own examples this way in GitHub Actions on `ubuntu-latest`, `macos-latest` and `windows-latest`.

--8<-- ".github/workflows/ci.yml" from="- name: Configure, build, test" to="ctest --test-dir" lang=yaml title=".github/workflows/ci.yml"

The job sets `-Werror=dev` and `-DOCX_PULL=ON`.
It also sets `-DOCX_BOOTSTRAP=ON`, which only matters for the `find_package` example.

## Check that the build works offline

Configure once online, then configure a fresh build directory with `OCX_OFFLINE=1`.
The second configure must succeed from the local store.

--8<-- ".github/workflows/ci.yml" from="- name: Warm configure" to="-B build/offline" lang=yaml title=".github/workflows/ci.yml"

For every variable on this page, see the [variable reference](../reference/variables.md).
Needs addressed: problems 2 and 5 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
