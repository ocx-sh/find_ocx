<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->
<!-- description: Update the vendored ocx.cmake and Findocx.cmake in script mode, verified against the release SHA256SUMS. -->
# Update the vendored files

Use the self-update in script mode to move `ocx.cmake` and `Findocx.cmake` to another find_ocx release.

The vendored pair self-updates in script mode, verified against the release `SHA256SUMS`:

```console
cmake -P cmake/ocx.cmake                                # latest release
cmake -DOCX_SELF_UPDATE_VERSION=v0.3.0 -P cmake/ocx.cmake
cmake -DOCX_SELF_UPDATE_VERSION=v0.3.0 \
      -DOCX_SELF_UPDATE_URL=https://mirror.corp/find_ocx \
      -P cmake/ocx.cmake                                # corporate mirror
```

Review the diff and commit the new files.
Needs addressed: problem 2 of the [use-case research](https://github.com/ocx-sh/find_ocx/blob/main/.agents/research/docs-use-cases.md).
