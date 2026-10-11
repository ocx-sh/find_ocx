@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Copyright 2026 The OCX Authors
rem
rem Stand-in for the ocx CLI (see fake_ocx.sh): the first FAKE_OCX_FAIL_COUNT
rem calls exit FAKE_OCX_FAIL_RC with an ocx-style error, later calls succeed.
setlocal enabledelayedexpansion
set n=0
if exist "%FAKE_OCX_STATE%" set /p n=<"%FAKE_OCX_STATE%"
set /a n=n+1
>"%FAKE_OCX_STATE%" echo !n!
if !n! LEQ %FAKE_OCX_FAIL_COUNT% (
  >&2 echo error: shim failure !n!: shim failure !n!
  exit /b %FAKE_OCX_FAIL_RC%
)
echo {"ok":true}
exit /b 0
