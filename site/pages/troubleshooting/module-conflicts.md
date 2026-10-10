<!-- doc_type: troubleshooting -->
<!-- description: Fixes for a configure that fails on a duplicate NAME or on a second copy of ocx.cmake at another version. -->
# Fix a module conflict

Each entry below starts with the message you see, then names the cause and the fix.
For a failing `ocx` call, see [Fix a failing configure](configure-errors.md).

## Error: duplicate NAME {#duplicate-name}

```text
find_ocx: duplicate ocx_package NAME 'SYSROOT'
```

This issue occurs when two calls share a `NAME` but differ in their arguments.
`NAME` prefixes the result variables, so it must be unique in a whole configure, including every `add_subdirectory`.

Give one of the calls another `NAME`.
A repeat with identical arguments is accepted, and that matters in a toolchain file.
CMake reads a toolchain file more than once, so an `ocx_package` or `ocx_project` call in it runs twice with the same arguments.

## Error: a second copy of ocx.cmake at another version {#second-copy}

This issue occurs when a subproject or a dependency vendors its own `ocx.cmake`, and that copy differs in version from the one already included.
Two versions would define the same commands with different behaviour, so find_ocx stops the configure.

Bring the copies to one version.
Update the vendored files in place with `cmake -DOCX_SELF_UPDATE_VERSION=vX.Y.Z -P cmake/ocx.cmake`, as [Update the vendored module](../guides/update-vendored.md) shows.
