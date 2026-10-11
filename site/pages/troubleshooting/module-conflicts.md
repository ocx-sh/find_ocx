<!-- doc_type: troubleshooting -->
<!-- description: Fixes for a configure that fails on a duplicate NAME or on a second copy of ocx.cmake at another version. -->
# Fix a module conflict

Each entry below starts with the message you see, then names the cause and the fix.
For a failing `ocx` call, see [Fix a failing configure](configure-errors.md).

## Error: duplicate NAME {#duplicate-name}

```log
find_ocx: duplicate ocx_package NAME 'SYSROOT'
```

This issue occurs when two calls share a `NAME` but differ in their arguments.
`NAME` prefixes the result variables, so it must be unique in a whole configure, including every `add_subdirectory`.
The check upper-cases the name and covers `ocx_project` and `ocx_package` together, so `sysroot` and `SYSROOT` collide.
The message names the command of the second call and prints the name in upper case.

Give one of the calls another `NAME`.
A repeat with identical arguments is accepted, and that matters in a toolchain file.
CMake reads a toolchain file more than once, so an `ocx_package` or `ocx_project` call in it runs twice with the same arguments.

## Error: a second copy of ocx.cmake at another version {#second-copy}

```log
find_ocx: two copies of ocx.cmake with different versions are loaded: 0.3.0 from /src/cmake/ocx.cmake and 0.4.0 from /src/third_party/x/ocx.cmake
hint: vendor one copy and point CMAKE_MODULE_PATH at it
```

This issue occurs when a subproject or a dependency vendors its own `ocx.cmake`, and that copy differs from the included one in path and version.
Two versions would define the same commands with different behaviour, so find_ocx stops the configure.
A second copy with the same version at another path is not an error.

Bring the copies to one version.
Update the vendored files in place with `cmake -DOCX_SELF_UPDATE_VERSION=vX.Y.Z -P cmake/ocx.cmake`, as [Update the vendored module](../guides/update-vendored.md) shows.
