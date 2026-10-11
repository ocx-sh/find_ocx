#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

"""Specification tests for the supply-chain guards in update_dist.py.

Run: python3 -I -m unittest discover -s scripts -p update_dist_test.py
(= `task dist:test`; CTest runs it as dist_script).

setup.ocx.sh names the versions, artifacts and sha256 that ocx_bootstrap()
will execute. These pin the guards that keep it from choosing what we pin:
per-row validation, direction, additions only, and no write before the guards.
No network, no writes; every fixture is inline.
"""

import contextlib
import hashlib
import io
import json
import pathlib
import shutil
import sys
import tempfile
import unittest
import urllib.request

import update_dist

# The 8 targets dist:check requires a pinned version to cover.
TARGETS = (
    "aarch64-apple-darwin",
    "aarch64-pc-windows-msvc",
    "aarch64-unknown-linux-gnu",
    "aarch64-unknown-linux-musl",
    "x86_64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-linux-gnu",
    "x86_64-unknown-linux-musl",
)

# Every field of a shared row that a rewrite could move. The key is
# (version, target), so those two are excluded.
ROW_FIELDS = ("sha256", "url", "filename", "tag", "channel")


def row(version, target, channel="stable"):
    """One dist.json release row, shaped like the committed snapshot."""
    filename = f"ocx-{target}.tar.gz"
    return {
        "version": version,
        "channel": channel,
        "tag": f"v{version}",
        "target": target,
        "filename": filename,
        # Realistic-looking and distinct per row, so a tampered value differs.
        "sha256": hashlib.sha256(f"{version}/{target}".encode()).hexdigest(),
        "url": f"https://github.com/ocx-sh/ocx/releases/download/v{version}/{filename}",
    }


def manifest(*versions, channel="stable", latest_channel="stable", latest_next=None):
    """A dist.json-shaped manifest carrying all 8 targets per version."""
    return {
        "schema": 1,
        "latest": {"version": versions[-1], "channel": latest_channel},
        "latest_next": latest_next,
        "releases": [row(v, t, channel) for v in versions for t in TARGETS],
    }


def dies(fn, *args, why="this input"):
    """Calls fn(*args), asserts it die()d, returns the exit message."""
    try:
        fn(*args)
    except SystemExit as e:
        return str(e.code)
    raise AssertionError(f"{fn.__name__} accepted {why}; expected die()")


@contextlib.contextmanager
def served(body):
    """Serves `body` to the next urlopen(); keeps the tests off the network.

    Yields the list of Requests it was handed, so a test can assert on what we
    send as well as on what we do with the answer — the User-Agent among it,
    which setup.ocx.sh 403s without.
    """
    real = urllib.request.urlopen
    seen = []

    def fake_urlopen(req, timeout=None):
        seen.append(req)
        return io.BytesIO(body)

    urllib.request.urlopen = fake_urlopen
    try:
        yield seen
    finally:
        urllib.request.urlopen = real


def module_text(pin, snapshot):
    """A minimal ocx.cmake: the pin, then the snapshot between its markers."""
    body = snapshot if isinstance(snapshot, str) else json.dumps(snapshot)
    return (
        f'set(__OCX_PIN_VERSION "{pin}")\n\n{update_dist.BEGIN}\n'
        f"set(__OCX_DIST_JSON [=[\n{body}\n]=])\n{update_dist.END}\n"
    )


def pin_of(tmp):
    return update_dist.pin_of((tmp / "ocx.cmake").read_text())


def embedded_bytes(tmp):
    """The snapshot as embedded in the sandbox ocx.cmake, as the bytes the
    fetch would have to equal (stripped, newline-terminated)."""
    m = update_dist.SNAPSHOT_RE.search((tmp / "ocx.cmake").read_text())
    return m.group(1).encode()


def written(body):
    """What splice_snapshot() makes of fetched bytes."""
    return body.strip() + b"\n"


@contextlib.contextmanager
def sandbox(pin, committed, argv, ci_pin=None):
    """Runs main() against a throwaway repo: the module, its snapshot, the pin
    and the workflows all live in a tmpdir, so a bump writes nothing real.
    `ci_pin` defaults to `pin`; pass a different one when the test has to tell
    "left alone" apart from "rewritten to the value it already had"."""
    tmp = pathlib.Path(tempfile.mkdtemp())
    update_dist.write(tmp / "ocx.cmake", module_text(pin, committed))
    (tmp / "workflows").mkdir()
    update_dist.write(
        tmp / "workflows" / "ci.yml",
        f'      - uses: ocx-sh/setup-ocx@v1\n        with:\n          version: "{ci_pin or pin}"\n'
    )
    saved = (update_dist.OCX_CMAKE, update_dist.WORKFLOWS, sys.argv)
    update_dist.OCX_CMAKE = tmp / "ocx.cmake"
    update_dist.WORKFLOWS = tmp / "workflows"
    sys.argv = ["update_dist.py", *argv]
    try:
        with contextlib.redirect_stdout(io.StringIO()):  # main()'s report is not the assertion
            yield tmp
    finally:
        update_dist.OCX_CMAKE, update_dist.WORKFLOWS, sys.argv = saved
        shutil.rmtree(tmp, ignore_errors=True)


@contextlib.contextmanager
def recording(*names):
    """Records which of the named module functions actually get called."""
    calls = []
    saved = {n: getattr(update_dist, n) for n in names}

    def spy(name, fn):
        def wrapped(*args, **kw):
            calls.append(name)
            return fn(*args, **kw)

        return wrapped

    for n, fn in saved.items():
        setattr(update_dist, n, spy(n, fn))
    try:
        yield calls
    finally:
        for n, fn in saved.items():
            setattr(update_dist, n, fn)


@contextlib.contextmanager
def snapshot_untouched():
    """Fails if the body of the block writes update_dist.OCX_CMAKE.

    OCX_CMAKE is repointed at a copy: a write-first regression is exactly what
    this guards, so it must not be able to destroy the real module while
    proving the point. The assertions live in `finally` - a body that raises
    still has to answer for the file it left behind, otherwise the regression
    surfaces as some unrelated error instead of "was rewritten".
    """
    tmp = pathlib.Path(tempfile.mkdtemp())
    module = tmp / "ocx.cmake"
    module.write_bytes(update_dist.OCX_CMAKE.read_bytes())
    before, mtime = module.read_bytes(), module.stat().st_mtime_ns
    saved, update_dist.OCX_CMAKE = update_dist.OCX_CMAKE, module
    try:
        try:
            yield
        finally:
            assert module.read_bytes() == before, f"{module} was rewritten"
            assert module.stat().st_mtime_ns == mtime, f"{module} was touched"
    finally:
        update_dist.OCX_CMAKE = saved
        shutil.rmtree(tmp, ignore_errors=True)


# --- the manifest server must not choose the channel we pin -------------


def test_f1_latest_pointer_must_be_stable():
    """Auto-select trusts manifest.latest — a prerelease pointer there
    would silently move the pin onto a beta."""
    update_dist.assert_latest_stable(manifest("0.5.2"))
    for ch in ("beta", "rc", "nightly", "next"):
        dies(update_dist.assert_latest_stable, manifest("0.5.3", latest_channel=ch), why=f"latest.channel={ch}")


def test_f1_latest_pointer_without_a_channel_is_refused():
    """Fail-closed: an absent channel is not evidence of stable."""
    m = manifest("0.5.2")
    del m["latest"]["channel"]
    dies(update_dist.assert_latest_stable, m, why="a latest pointer with no channel")


def test_f1_latest_next_does_not_block_a_stable_latest():
    """Only `latest` feeds auto-select — a prerelease parked in
    latest_next is normal upstream traffic. Refusing it would be an
    over-refusal; *following* it would be the vulnerability, so both halves
    are asserted."""
    m = manifest("0.5.1", "0.5.2", latest_next={"version": "0.6.0", "channel": "beta"})
    update_dist.assert_latest_stable(m)
    assert update_dist.newest_stable(m) == "0.5.2", "auto-select must ignore latest_next"


def test_f1_an_absent_latest_pointer_falls_back_instead_of_dying():
    """With no pointer there is nothing to distrust — newest_stable()
    filters `releases` by channel instead, which is the safer path. Making
    this branch die() would break a manifest that simply has no `latest`."""
    m = manifest("0.5.1", "0.5.2")
    del m["latest"]
    update_dist.assert_latest_stable(m)
    assert update_dist.newest_stable(m) == "0.5.2"


def test_f1_newest_stable_dies_when_there_is_nothing_stable_to_pick():
    """With no `latest` pointer, newest_stable() falls back to filtering
    `releases` by channel — and a manifest that is entirely prerelease leaves
    that filter empty, so there is no version to auto-select at all. It has to
    die() with a message: max() over the empty list raises a bare ValueError,
    and the caller is the unattended update-dist cron, whose whole output would
    then be a traceback."""
    beta_only = manifest("0.6.0", channel="beta")
    del beta_only["latest"]
    msg = dies(update_dist.newest_stable, beta_only, why="a manifest with no stable row and no latest")
    assert "stable" in msg, f"die() must name what was missing; got: {msg}"


def test_f1_validate_refuses_a_non_stable_row():
    """The per-row channel check runs on auto-select, on --version and
    on --check, so it also catches a beta the operator named by hand."""
    good = manifest("0.5.2")
    assert len(update_dist.validate(good, "0.5.2")) == len(TARGETS)

    one_beta = manifest("0.5.2")
    one_beta["releases"][3]["channel"] = "beta"
    dies(update_dist.validate, one_beta, "0.5.2", why="a release with one beta row")

    all_beta = manifest("0.6.0", channel="beta")
    dies(update_dist.validate, all_beta, "0.6.0", why="a wholly beta release")


def test_f1_validate_refuses_a_partial_target_set():
    """The pinned version must be present for
    all 8 targets, or ocx_bootstrap() has no row at all on the hosts that are
    missing. Asserting the *return* length does not pin this: an 8-row fixture
    returns 8 whether the count check runs or not, so the fixture has to be
    short."""
    partial = manifest("0.5.2")
    partial["releases"] = partial["releases"][:3]
    msg = dies(update_dist.validate, partial, "0.5.2", why="3 of the 8 targets")
    assert "got 3" in msg, f"die() must name the count it found; got: {msg}"

    # A version absent altogether is the same failure, and the likelier one:
    # an operator naming a --version that upstream never published.
    dies(update_dist.validate, manifest("0.5.2"), "0.9.9", why="a version with no rows at all")


def test_f1_validate_tolerates_a_target_upstream_adds():
    """The count check is one-sided deliberately. It exists to catch a
    release that is still publishing — *fewer* rows than targets — and
    upstream adding a 9th target (riscv64, loongarch) is a normal release day,
    not an attack. Under an equality check that release turns `task dist:check`
    red for the whole repo, on every PR, with a message telling the operator to
    retry something that will never change. The added row is not trusted for
    being extra: check_row() still runs on it here, assert_additions_only() on
    the refresh path, and --check on every later PR.
    """
    widened = manifest("0.5.2")
    widened["releases"].append(row("0.5.2", "riscv64gc-unknown-linux-gnu"))
    assert len(update_dist.validate(widened, "0.5.2")) == len(TARGETS) + 1, "a new target must not fail the pin"

    poisoned = manifest("0.5.2")
    poisoned["releases"].append(row("0.5.2", "riscv64gc-unknown-linux-gnu", channel="nightly"))
    dies(update_dist.validate, poisoned, "0.5.2", why="a 9th target row on the nightly channel")


def test_f1_validate_refuses_a_version_that_drops_a_committed_target():
    """A row *count* is not target coverage. Nine rows that skip
    aarch64-apple-darwin clear the floor, and the refresh path cannot catch it
    either — a brand-new version has no committed rows for
    assert_additions_only() to compare against — so __ocx_select_release() is left to fail() on the host that lost its row.
    Coverage is what the count was proxying for, measured against the targets
    the *outgoing* pin already covers: self-maintaining, and it does not
    hardcode a target list that upstream renames out from under us.
    """
    incoming = manifest("0.5.2", "0.5.3")
    incoming["releases"] = [
        r for r in incoming["releases"] if r["version"] != "0.5.3" or r["target"] != "aarch64-apple-darwin"
    ]
    for extra in ("riscv64gc-unknown-linux-gnu", "loongarch64-unknown-linux-gnu"):
        incoming["releases"].append(row("0.5.3", extra))
    assert len(update_dist.rows_for(incoming, "0.5.3")) == 9, "the fixture must clear the row-count floor"

    msg = dies(update_dist.validate, incoming, "0.5.3", set(TARGETS), why="9 rows that skip a committed target")
    assert "aarch64-apple-darwin" in msg, f"die() must name the missing target; got: {msg}"

    # A superset is still a normal release day: covering every outgoing target
    # and adding two more must pass, or every new target becomes an outage.
    widened = manifest("0.5.2", "0.5.3")
    for extra in ("riscv64gc-unknown-linux-gnu", "loongarch64-unknown-linux-gnu"):
        widened["releases"].append(row("0.5.3", extra))
    assert len(update_dist.validate(widened, "0.5.3", set(TARGETS))) == len(TARGETS) + 2


def test_f1_validate_refuses_a_sha256_that_is_not_lowercase_hex():
    """A length check is not a hex check — "z"*64 passes it, and a
    64-element list passes it too and then reaches ocx_bootstrap() as a
    non-string."""
    for bad in ("z" * 64, "A" * 64, ["0"] * 64, None, "abc"):
        m = manifest("0.5.2")
        m["releases"][1]["sha256"] = bad
        dies(update_dist.validate, m, "0.5.2", why=f"sha256={bad!r}")


def test_f1_validate_refuses_an_artifact_url_off_the_release_host():
    """A fabricated row must not name an off-host url.

    ocx_bootstrap() uses row["url"] verbatim; mirrors go through
    OCX_INSTALL_MIRROR_URL. startswith() is no host check: github.com
    normalises dot segments server-side, so a traversal under the artifact
    prefix serves another repository's asset under the row's sha256. CRLF,
    tabs, NUL, a query and a fragment must fail too.
    """
    good = f"{update_dist.ARTIFACT_PREFIX}v0.5.2/ocx-x86_64-unknown-linux-gnu.tar.gz"
    assert len(update_dist.validate(manifest("0.5.2"), "0.5.2")) == len(TARGETS), "the real URL shape must pass"
    for bad in (
        "https://evil.example/v0.5.2/ocx.tar.gz",
        # On github.com, over https, no dot segment, no separator trick — just
        # another repository. The path prefix is the only thing refusing it,
        # and anyone can create a repo and cut a release under it.
        "https://github.com/attacker/evil/releases/download/v1/ocx.tar.gz",
        "https://github.com.evil.example/ocx-sh/ocx/releases/download/v0.5.2/ocx.tar.gz",
        "https://github.com@evil.example/ocx-sh/ocx/releases/download/v0.5.2/ocx.tar.gz",
        "https://GITHUB.COM/ocx-sh/ocx/releases/download/v0.5.2/ocx.tar.gz",
        "http://github.com/ocx-sh/ocx/releases/download/v0.5.2/ocx.tar.gz",
        # The PoC: 200 OK, another repository's asset, prefix intact.
        f"{update_dist.ARTIFACT_PREFIX}../../../../attacker/evil/releases/download/v1/ocx.tar.gz",
        f"{update_dist.ARTIFACT_PREFIX}%2e%2e/%2e%2e/%2e%2e/%2e%2e/attacker/evil/releases/download/v1/ocx.tar.gz",
        f"{good}\r\nX-Injected: 1",
        f"{good}\tocx.tar.gz",
        f"{good}\0",
        f"{good}?redirect=https://evil.example/ocx.tar.gz",
        f"{good}#https://evil.example",
        # urlsplit() raises on a malformed IPv6 literal; the guard answers
        # False rather than letting ValueError out into check_row().
        "https://[::1/ocx-sh/ocx/releases/download/v1/ocx.tar.gz",
        None,
        123,
        [good],
    ):
        m = manifest("0.5.2")
        m["releases"][2]["url"] = bad
        dies(update_dist.validate, m, "0.5.2", why=f"url={bad!r}")


def test_f1_url_guard_allowlists_the_asset_shape_instead_of_blocking_separators():
    """Separators are refused by allowlisting the asset shape.

    The url must be `<tag>/<filename>`, one separator-free segment each;
    github.com turns "\\" into "/", so blocklisting separators is an open
    set. A bare ".." clears the charset, so the dot-segment check stays.
    The authority compare is `p.netloc == ARTIFACT_HOST` on the raw netloc:
    `.hostname` drops userinfo and the port and would pass them.
    """
    good = f"{update_dist.ARTIFACT_PREFIX}v0.5.2/ocx-x86_64-unknown-linux-gnu.tar.gz"
    for bad in (
        # Literal backslashes: urlsplit sees one segment, github.com sees four.
        rf"{update_dist.ARTIFACT_PREFIX}..\..\..\..\ATTACKER/REPO/releases/download/v1/ocx.tar.gz",
        f"{update_dist.ARTIFACT_PREFIX}..%5c..%5c..%5c..%5cATTACKER/REPO/releases/download/v1/ocx.tar.gz",
        # The same traversal spelled with *exactly* two slash-separated
        # segments, so the shape check has nothing to say and the charset is
        # the only thing refusing it. Without these two, adding "\" to the
        # character classes passes the whole suite and reopens the bypass.
        rf"{update_dist.ARTIFACT_PREFIX}..\..\..\..\ATTACKER\REPO\releases\download\v0.5.2/ocx-x86_64-unknown-linux-gnu.tar.gz",
        f"{update_dist.ARTIFACT_PREFIX}..%5c..%5c..%5cATTACKER%5cREPO/ocx.tar.gz",
        "https://user@github.com/ocx-sh/ocx/releases/download/v1/ocx.tar.gz",
        "https://github.com@evil.example/ocx-sh/ocx/releases/download/v1/ocx.tar.gz",
        "https://github.com:443/ocx-sh/ocx/releases/download/v1/ocx.tar.gz",
        "https://GitHub.com/ocx-sh/ocx/releases/download/v1/ocx.tar.gz",
        "https://github.com./ocx-sh/ocx/releases/download/v1/ocx.tar.gz",
        # A third path segment is not an asset url whatever it spells.
        f"{update_dist.ARTIFACT_PREFIX}v1/a/b.tar.gz",
        f"{update_dist.ARTIFACT_PREFIX}v1%2fATTACKER%2fREPO%2freleases%2fdownload%2fv1/ocx.tar.gz",
        # The two cases that pin the checks either side of the pattern; neither
        # is exploitable, and each is refused by exactly one of them. ".."
        # clears the charset, so the dot segment check is the only refusal...
        f"{update_dist.ARTIFACT_PREFIX}../ocx.tar.gz",
        # ...and this one's *decoded* path matches the pattern cleanly, so the
        # raw-path startswith() is the only refusal. Delete either line in
        # on_release_host() and one of these two starts passing.
        "https://github.com/ocx-sh/ocx/releases/download%2fv1/ocx.tar.gz",
    ):
        assert not update_dist.on_release_host(bad), f"on_release_host accepted {bad!r}"

    # Every C0 control, DEL and space, not just the four that were once
    # blocklisted: urlsplit() lstrips WHATWG C0-or-space, so a *leading*
    # \x01-\x08, \x0b, \x0c or \x0e-\x20 is dropped during parsing and never
    # seen by any check downstream of it, while staying in the stored url.
    for c in [chr(i) for i in range(0x21)] + ["\x7f"]:
        for injected in (f"{c}{good}", f"{good}{c}"):
            assert not update_dist.on_release_host(injected), f"on_release_host accepted {injected!r}"

    # Every archive shape in the committed snapshot still passes: a guard that
    # refuses the embedded snapshot is not a guard, it is an outage.
    for ok in (
        good,
        f"{update_dist.ARTIFACT_PREFIX}v0.5.2/ocx-aarch64-pc-windows-msvc.zip",
        f"{update_dist.ARTIFACT_PREFIX}v0.4.2/ocx-aarch64-apple-darwin.tar.xz",
    ):
        assert update_dist.on_release_host(ok), f"on_release_host refused the committed shape {ok!r}"


def test_f1_validate_refuses_a_filename_it_cannot_type():
    """An extension ocx_bootstrap() cannot extract
    fails at extraction rather than at download — and a row with no filename
    at all has to die() with a message, not KeyError out of the guard."""
    for bad in ("ocx.tar.bz2", "ocx", None, 7, ["ocx.tar.gz"]):
        m = manifest("0.5.2")
        m["releases"][4]["filename"] = bad
        dies(update_dist.validate, m, "0.5.2", why=f"filename={bad!r}")

    missing = manifest("0.5.2")
    del missing["releases"][4]["filename"]
    dies(update_dist.validate, missing, "0.5.2", why="a row with no filename at all")


def test_f1_validate_refuses_a_tag_or_filename_that_is_not_one_path_segment():
    """The mirror path: tag and filename are single path segments.

    ocx_bootstrap() builds the mirror url as <mirror>/<tag>/<filename>, so
    tag="../../../.." walks out of the release directory of a shared proxy.
    Same charset as the url path, since they are its two segments.
    """
    for field, bad in (
        ("tag", "../../../.."),
        ("tag", "v0.5.2/../../evil"),
        ("tag", r"v0.5.2\..\..\evil"),
        ("tag", None),
        ("tag", ["v0.5.2"]),
        ("filename", "../../../../evil.example/x.tar.gz"),
        # Passes ext_of()'s endswith and is still not one path segment.
        ("filename", "a b.tar.gz"),
        # A dot segment is *inside* the charset, so the fullmatch alone waves
        # it through. One `..` still walks a level out of the release
        # directory in the composed mirror url, which is the whole point of
        # checking these two fields — on_release_host() refuses the same
        # spelling in the url path for the same reason.
        ("tag", ".."),
        ("tag", "."),
        ("filename", ".."),
    ):
        m = manifest("0.5.2")
        m["releases"][5][field] = bad
        dies(update_dist.validate, m, "0.5.2", why=f"{field}={bad!r}")


# --- the pin only ever moves forward -----------------------------------


def test_f1b_pin_only_moves_forward():
    """Comparison is by version_key(), not string order — 0.5.10 is
    newer than 0.5.9, and a lexicographic guard gets both cases wrong."""
    update_dist.assert_forward("0.5.2", "0.5.3")
    update_dist.assert_forward("0.5.9", "0.5.10")
    update_dist.assert_forward("0.6.0", "0.10.0")

    dies(update_dist.assert_forward, "0.5.2", "0.5.2", why="a no-op bump")
    dies(update_dist.assert_forward, "0.5.3", "0.5.2", why="a rollback")
    dies(update_dist.assert_forward, "0.5.10", "0.5.9", why="a rollback string compare would accept")


# --- a refresh may only add rows ----------------------------------------


def test_f2_additions_are_the_only_permitted_change():
    """No change, a new version, and a new target for a known version are
    all legitimate — the guard must not over-refuse a normal upstream day."""
    base = manifest("0.5.1", "0.5.2")
    update_dist.assert_additions_only(base, base)
    update_dist.assert_additions_only(base, manifest("0.5.1", "0.5.2", "0.5.3"))

    new_target = manifest("0.5.1", "0.5.2")
    new_target["releases"].append(row("0.5.2", "riscv64gc-unknown-linux-gnu"))
    update_dist.assert_additions_only(base, new_target)


def test_f2_rewritten_row_is_refused():
    """sha256 is the value ocx_bootstrap() enforces against, but any
    field moving under an already-committed (version, target) is a rewrite."""
    base = manifest("0.5.1", "0.5.2")
    for field in ROW_FIELDS:
        tampered = manifest("0.5.1", "0.5.2")
        tampered["releases"][0][field] = "0" * 64 if field == "sha256" else "rewritten"
        assert tampered["releases"][0][field] != base["releases"][0][field]
        dies(update_dist.assert_additions_only, base, tampered, why=f"a rewritten {field}")

    # A field *removed* from a committed row is the same rewrite, and the half
    # the comparison is easiest to get wrong: iterating the incoming row's
    # fields alone lets a dropped sha256 read as "nothing moved". Hence the
    # union of both field sets. The message must name the field, so this
    # cannot pass on some unrelated guard dying first.
    for field in ROW_FIELDS:
        stripped = manifest("0.5.1", "0.5.2")
        del stripped["releases"][0][field]
        msg = dies(update_dist.assert_additions_only, base, stripped, why=f"a deleted {field}")
        # "sha256: ", not "sha256": the bare field name matches the message's
        # fixed boilerplate ("its sha256 is what...", ".../tag/v0.5.1") and
        # would pass for any rewrite at all. The rendered form is "sha256: 'x'
        # -> None".
        assert f"{field}: " in msg, f"die() must name the dropped field; got: {msg}"


def test_f2_dropped_row_is_refused_and_named():
    """A version disappearing upstream must not silently vanish from our
    snapshot, and the message has to name the rows that went, not just the
    versions — one target of a live release can drop on its own."""
    base = manifest("0.5.1", "0.5.2")
    msg = dies(update_dist.assert_additions_only, base, manifest("0.5.2"), why="a dropped 0.5.1")
    assert "0.5.1" in msg, f"die() message must name the dropped version; got: {msg}"

    partial = manifest("0.5.1", "0.5.2")
    gone = partial["releases"].pop(3)  # one target of 0.5.1, the rest still there
    msg = dies(update_dist.assert_additions_only, base, partial, why="one dropped target")
    assert f"{gone['version']} {gone['target']}" in msg, f"must name the dropped row; got: {msg}"


def test_f2_a_duplicate_row_is_refused_on_both_sides():
    """The bypass: indexing by (version, target) keeps the LAST row per
    key, but __ocx_select_release() returns the FIRST.
    Serve the poisoned row first and the honest row last and a last-wins index
    compares the honest one, passes, and commits both — after which
    ocx_bootstrap() resolves the attacker's host and sha256. .gitattributes marks
    the embedded snapshot linguist-generated, so no reviewer sees the extra row.
    """
    base = manifest("0.5.1", "0.5.2")
    honest = base["releases"][0]
    poison = dict(honest, sha256="d" * 64, url="https://evil.example/v0.5.1/ocx.tar.gz")

    incoming = manifest("0.5.1", "0.5.2")
    incoming["releases"].insert(0, poison)  # poison first, honest still present
    assert incoming["releases"][1] == honest, "the honest row must still be there to shadow"
    msg = dies(update_dist.assert_additions_only, base, incoming, why="a poison-first duplicate row")
    assert "twice" in msg, f"die() must name the duplication; got: {msg}"

    # Committed side too: a duplicate that ever landed compares equal to
    # itself on every later refresh, so it would stay invisible forever.
    dies(update_dist.assert_additions_only, incoming, base, why="a duplicate already committed")


def test_f2_a_new_upstream_column_is_refused():
    """Rows are compared over the union of their fields, so a column
    appearing upstream trips the guard — the likeliest real trigger, and
    deliberate: a new column changes what an already-committed row means."""
    base = manifest("0.5.1", "0.5.2")
    widened = manifest("0.5.1", "0.5.2")
    for r in widened["releases"]:
        r["signature"] = "MEUCIQ..."
    msg = dies(update_dist.assert_additions_only, base, widened, why="a new column on every row")
    assert "signature" in msg, f"die() must name the new field; got: {msg}"


def test_f2_added_rows_face_the_same_per_row_bar():
    """validate() only ever inspects the rows of the version being
    pinned, but the *whole* manifest is written. ocx.download(version = ...)
    lets a consumer select any row in it, and no Starlark checks the host or
    the channel — so a refresh of 0.5.3 must not be able to smuggle in rows
    nobody validated. The count check stays scoped to the pinned version
    (upstream mid-publish is not an attack); everything else is not.
    """
    base = manifest("0.5.1", "0.5.2")
    update_dist.assert_additions_only(base, manifest("0.5.1", "0.5.2", "0.5.3"))  # a clean addition still passes

    for field, bad in (
        ("channel", "nightly"),
        ("sha256", "z" * 64),
        ("url", "https://evil.example/v0.5.3/ocx.tar.gz"),
        ("url", f"{update_dist.ARTIFACT_PREFIX}../../../../attacker/evil/releases/download/v1/ocx.tar.gz"),
        ("filename", "ocx.tar.bz2"),
    ):
        incoming = manifest("0.5.1", "0.5.2", "0.5.3")
        for r in incoming["releases"]:
            if r["version"] == "0.5.3":
                r[field] = bad
        msg = dies(update_dist.assert_additions_only, base, incoming, why=f"an added row with {field}={bad!r}")
        assert "0.5.3" in msg, f"die() must name the offending row; got: {msg}"


def test_f2_a_malformed_manifest_dies_instead_of_tracebacking():
    """setup.ocx.sh serving something only manifest-shaped-ish is a
    failure the operator has to act on, so it exits with a message rather
    than a KeyError/AttributeError out of the guard's internals."""
    base = manifest("0.5.2")
    broken = (
        {"schema": 1},  # no releases at all
        {"releases": {}},  # an object where the list belongs
        {"releases": [{"version": "0.5.2"}]},  # a row with no target
        {"releases": [], "latest": "0.5.2"},  # latest as a bare string
    )
    for m in broken:
        dies(update_dist.assert_additions_only, base, m, why=f"incoming {m!r}")
        dies(update_dist.assert_additions_only, m, base, why=f"committed {m!r}")


def test_an_unsupported_schema_dies_before_any_guard_accepts_it():
    """ocx_bootstrap() rejects every schema but 1 (__ocx_select_release), so a
    manifest that declares another one must fail here, not at the first cold
    bootstrap: it would pass every row guard and be embedded."""
    base = manifest("0.5.2")
    for schema in (2, 0, "1", True, None):
        bad = dict(manifest("0.5.2"), schema=schema)
        dies(update_dist.index_rows, bad, "incoming", why=f"schema {schema!r}")
        dies(update_dist.assert_additions_only, base, bad, why=f"incoming schema {schema!r}")
        dies(update_dist.assert_additions_only, bad, base, why=f"committed schema {schema!r}")
    no_schema = manifest("0.5.2")
    del no_schema["schema"]
    dies(update_dist.index_rows, no_schema, "incoming", why="a manifest without a schema")
    assert update_dist.index_rows(manifest("0.5.2"), "incoming"), "schema 1 must pass"
    with sandbox("0.5.2", dict(manifest("0.5.2"), schema=2), argv=["--check"]):
        msg = dies(update_dist.main, why="a committed schema 2 under --check")
    assert "schema" in msg, f"--check must name the schema; got: {msg}"


# --- nothing is written before the guards have run ----------------------


def test_f3_fetch_snapshot_parses_without_writing():
    """Fetch returns (body, manifest) for the caller to validate; the
    write happens last, after every guard passes."""
    body = json.dumps(manifest("0.5.2")).encode()
    with snapshot_untouched(), served(body):
        got_body, got_manifest = update_dist.fetch_snapshot()
    assert got_body == body, "fetch_snapshot must return the raw bytes to write"
    assert got_manifest["latest"]["version"] == "0.5.2"


def test_f3_unparseable_response_leaves_the_snapshot_intact():
    """The failure that most wants a write-first implementation — an
    error page served in place of the manifest must leave disk untouched."""
    with snapshot_untouched(), served(b"<html>503 Service Unavailable</html>"):
        dies(update_dist.fetch_snapshot, why="an HTML error page")


def test_f3_fetch_identifies_itself_to_the_manifest_host():
    """setup.ocx.sh 403s the default Python-urllib agent, so the User-Agent is
    load-bearing rather than cosmetic: drop it and every refresh — scheduled or
    manual — dies at the fetch, reporting an HTTP error whose actual cause is
    the header we sent. served() yields the Requests it was handed so that can
    be asserted; stubbing urlopen with a lambda that ignored its argument meant
    nothing ever looked."""
    with snapshot_untouched(), served(json.dumps(manifest("0.5.2")).encode()) as seen:
        update_dist.fetch_snapshot()
    assert len(seen) == 1, f"expected exactly one fetch; got {len(seen)}"
    assert seen[0].get_full_url() == update_dist.DIST_URL, seen[0].get_full_url()
    # urllib stores header names capitalised, hence "User-agent".
    assert seen[0].get_header("User-agent") == "find-ocx-update-dist", seen[0].header_items()


# --- wiring: a guard that main() never calls protects nothing ---------------

GUARDS = ("assert_latest_stable", "assert_forward", "assert_additions_only", "validate")


def test_wiring_every_guard_runs_on_the_auto_select_path():
    """The default `task dist:update`-style run is the path the
    scheduled update-dist.yml takes, so every guard has to fire on it."""
    committed = manifest("0.5.1", "0.5.2")
    with sandbox("0.5.2", committed, argv=[]), served(json.dumps(manifest("0.5.1", "0.5.2", "0.5.3")).encode()):
        with recording(*GUARDS) as calls:
            update_dist.main()
    assert set(calls) == set(GUARDS), f"guards not called by main(): {sorted(set(GUARDS) - set(calls))}"


def test_wiring_explicit_version_skips_auto_select_but_keeps_the_row_guards():
    """--version is the operator choosing the version by hand, so both guards
    that only exist to police the *automatic* choice are off: the forward-only
    check and the `latest` channel check. What must stay on is everything that
    inspects the rows themselves — per-row validate() and additions-only."""
    committed = manifest("0.5.1", "0.5.2")
    with sandbox("0.5.2", committed, argv=["--version", "0.5.1"]), served(json.dumps(committed).encode()):
        with recording(*GUARDS) as calls:
            update_dist.main()
    assert "assert_forward" not in calls, "--version must bypass the forward guard"
    assert "assert_latest_stable" not in calls, "--version does not consult the latest pointer"
    assert {"validate", "assert_additions_only"} <= set(calls), f"guards skipped: {calls}"


def test_wiring_check_path_validates_the_committed_snapshot():
    """The --check run is offline and writes nothing, but it is where CI notices
    that a committed row has drifted off the stable channel — or that a
    duplicate got into the file by some route other than a refresh."""
    tainted = manifest("0.5.2")
    tainted["releases"][0]["channel"] = "nightly"
    with sandbox("0.5.2", tainted, argv=["--check"]):
        dies(update_dist.main, why="a committed nightly row under --check")

    dup = manifest("0.5.2")
    dup["releases"].insert(0, dict(dup["releases"][0], sha256="d" * 64))
    with sandbox("0.5.2", dup, argv=["--check"]):
        msg = dies(update_dist.main, why="a duplicate row hand-landed in the committed snapshot")
    assert "twice" in msg, f"--check must name the duplication; got: {msg}"


def test_wiring_check_validates_every_committed_row_not_just_the_pinned_one():
    """--check covers the committed file. It is the only guard a PR that *edits*
    the embedded snapshot ever meets: `task lint` runs it, and the refresh guards
    only run when the script fetches. Scoping check_row() to the pinned
    version left every other row unexamined — a hand-edited row for a version
    nobody pins today is still a url+sha256 pair ocx.download(version = ...)
    selects, and the file is linguist-generated, so GitHub collapses the diff
    that carries it. The next scheduled refresh would trip on the rewrite, but
    blames upstream rather than the commit that made it."""
    for field, bad in (
        ("url", "https://evil.example/ocx.tar.gz"),
        ("url", f"{update_dist.ARTIFACT_PREFIX}../../../../attacker/evil/releases/download/v1/ocx.tar.gz"),
        ("sha256", "d" * 64 + "0"),
        ("channel", "nightly"),
        ("filename", "ocx.tar.bz2"),
    ):
        tainted = manifest("0.4.3", "0.5.2")  # 0.5.2 is pinned; 0.4.3 is not
        tainted["releases"][0][field] = bad
        assert tainted["releases"][0]["version"] == "0.4.3", "the tampered row must not be the pinned one"
        with sandbox("0.5.2", tainted, argv=["--check"]):
            msg = dies(update_dist.main, why=f"a committed non-pinned row with {field}={bad!r}")
        assert "0.4.3" in msg, f"die() must name the offending row; got: {msg}"


def test_wiring_check_on_an_unreadable_snapshot_dies_instead_of_tracebacking():
    """The module docstring promises die(); a truncated or half-merged
    the embedded snapshot is a plausible way to arrive here, and a JSONDecodeError
    traceback gives the operator nothing to do about it."""
    with sandbox("0.5.2", manifest("0.5.2"), argv=["--check"]) as tmp:
        update_dist.write(tmp / "ocx.cmake", module_text("0.5.2", '{"releases": ['))
        msg = dies(update_dist.main, why="a truncated committed snapshot")
    assert "git checkout" in msg, f"must name the way back to a good file; got: {msg}"


def test_wiring_snapshot_only_writes_the_snapshot_and_leaves_the_pin():
    """The write lands after the guards; --snapshot-only is a refresh.

    The pin, the CI pin and the incoming latest are three different versions
    on purpose: with equal values a regression that rewrote the CI pins
    anyway would be invisible. Incoming 0.5.3 is mid-publish (4 of 8
    targets), tolerable only because --snapshot-only validates the *pinned*
    version, not the newest fetched one.
    """
    committed = manifest("0.5.1", "0.5.2")
    mid_publish = manifest("0.5.1", "0.5.2", "0.5.3")
    mid_publish["releases"] = [
        r for r in mid_publish["releases"] if r["version"] != "0.5.3" or r["target"] in TARGETS[:4]
    ]
    incoming = json.dumps(mid_publish).encode()
    with sandbox("0.5.2", committed, argv=["--snapshot-only"], ci_pin="0.4.9") as tmp, served(incoming):
        update_dist.main()
        assert embedded_bytes(tmp) == written(incoming), "--snapshot-only must write the fetched bytes"
        assert pin_of(tmp) == "0.5.2", "--snapshot-only must not move the pin"
        ci = (tmp / "workflows" / "ci.yml").read_text()
        assert '"0.4.9"' in ci, f"--snapshot-only must leave the CI pins alone; got: {ci}"


def test_wiring_a_scheduled_run_with_nothing_new_upstream_exits_clean():
    """The cron's steady state, every day upstream does not release: latest
    equals the pin. That is a no-op refresh, not "refusing to move the pin
    0.5.2 -> 0.5.2" — assert_forward only guards an actual move, so the
    scheduled job must not die on it (a die() here raises SystemExit, which
    this suite counts as a failure)."""
    committed = manifest("0.5.1", "0.5.2")
    with sandbox("0.5.2", committed, argv=[]) as tmp, served(json.dumps(committed).encode()):
        update_dist.main()
        assert pin_of(tmp) == "0.5.2", "the pin must stay put"


def test_wiring_a_poisoned_added_row_blocks_both_write_paths():
    """End to end: 8 rows of a version nobody pins — channel nightly,
    "z"*64, an off-host url — used to land in the committed snapshot on both
    write paths, because validate() only ever inspects the pinned version and
    --check then re-validates only the pin, so they persisted. the embedded snapshot
    is `linguist-generated`, so GitHub collapses the diff that carries them.
    Neither path may write."""
    committed = manifest("0.5.1", "0.5.2")
    poisoned = manifest("0.5.1", "0.5.2", "0.5.3")
    for r in poisoned["releases"]:
        if r["version"] == "0.5.3":
            r.update(channel="nightly", sha256="z" * 64, url="https://evil.example/v0.5.3/ocx.tar.gz")
    body = json.dumps(poisoned).encode()
    for argv in (["--snapshot-only"], []):
        with sandbox("0.5.2", committed, argv=argv) as tmp, served(body):
            before = (tmp / "ocx.cmake").read_bytes()
            dies(update_dist.main, why=f"a poisoned added row under {argv or ['(auto-bump)']}")
            assert (tmp / "ocx.cmake").read_bytes() == before, f"{argv or '(auto-bump)'} wrote the poisoned manifest"


def test_wiring_the_bump_path_measures_coverage_against_the_outgoing_pin():
    """A guard main() never calls protects nothing: validate()'s coverage check
    only bites if the bump path hands it the targets the *committed* pin
    covers. 0.5.3 arrives with 9 rows — clearing the count floor — and still no
    aarch64-apple-darwin, so nothing may be written."""
    committed = manifest("0.5.1", "0.5.2")
    incoming = manifest("0.5.1", "0.5.2", "0.5.3")
    incoming["releases"] = [
        r for r in incoming["releases"] if r["version"] != "0.5.3" or r["target"] != "aarch64-apple-darwin"
    ]
    for extra in ("riscv64gc-unknown-linux-gnu", "loongarch64-unknown-linux-gnu"):
        incoming["releases"].append(row("0.5.3", extra))
    with sandbox("0.5.2", committed, argv=[]) as tmp, served(json.dumps(incoming).encode()):
        before = (tmp / "ocx.cmake").read_bytes()
        msg = dies(update_dist.main, why="a bump to a version missing a committed target")
        assert (tmp / "ocx.cmake").read_bytes() == before, "the write must not land"
    assert "aarch64-apple-darwin" in msg, f"die() must name the missing target; got: {msg}"


def test_wiring_a_validate_failure_also_blocks_the_write():
    """Ordering. Every added row here is clean, so assert_additions_only()
    passes and validate() is the guard that dies — 4 of 8 targets on the
    version `latest` points at, i.e. a normal mid-publish release day. Pinning
    the write against the *poisoned-row* test alone leaves the module write
    free to move above validate(), which would commit a manifest whose pinned
    version cannot resolve on half the hosts."""
    committed = manifest("0.5.1", "0.5.2")
    mid_publish = manifest("0.5.1", "0.5.2", "0.5.3")
    mid_publish["releases"] = [
        r for r in mid_publish["releases"] if r["version"] != "0.5.3" or r["target"] in TARGETS[:4]
    ]
    with sandbox("0.5.2", committed, argv=[]) as tmp, served(json.dumps(mid_publish).encode()):
        before = (tmp / "ocx.cmake").read_bytes()
        dies(update_dist.main, why="a `latest` with 4 of 8 targets published")
        assert (tmp / "ocx.cmake").read_bytes() == before, "the write must land after validate()"
        assert pin_of(tmp) == "0.5.2", "the pin must stay put"


def test_wiring_ci_pins_cover_yaml_and_refuse_to_miss_a_step():
    """Invariant 2 is a lockstep: __OCX_PIN_VERSION and the setup-ocx pins
    move together, and nothing else in the repo cross-checks them. A step this
    cannot rewrite therefore has to be loud — `hits == 0` reads exactly like
    "already current" otherwise, and CI would go on running the old ocx with
    `task verify` green. `.yaml` is a real spelling: .github/workflows already
    holds publish.yaml."""
    committed = manifest("0.5.1", "0.5.2")
    incoming = json.dumps(manifest("0.5.1", "0.5.2", "0.5.3")).encode()

    with sandbox("0.5.2", committed, argv=[]) as tmp, served(incoming):
        update_dist.write(
            tmp / "workflows" / "publish.yaml",
            '      - uses: ocx-sh/setup-ocx@v1\n        with:\n          version: "0.4.9"\n'
        )
        update_dist.main()
        assert '"0.5.3"' in (tmp / "workflows" / "publish.yaml").read_text(), ".yaml workflows must be repinned too"

    for case, body in (
        ("an unquoted pin", '      - uses: ocx-sh/setup-ocx@v1\n        with:\n          version: 0.4.9\n'),
        (
            "a reordered with: block",
            "      - uses: ocx-sh/setup-ocx@v1\n        with:\n          cache: true\n"
            '          token: x\n          version: "0.4.9"\n',
        ),
        ("no version key at all", "      - uses: ocx-sh/setup-ocx@v1\n"),
    ):
        with sandbox("0.5.2", committed, argv=[]) as tmp, served(incoming):
            update_dist.write(tmp / "workflows" / "other.yml", body)
            msg = dies(update_dist.main, why=case)
        assert "setup-ocx" in msg, f"die() must name the step it could not repin ({case}); got: {msg}"


def test_wiring_the_bump_path_writes_the_fetched_bytes_verbatim():
    """The embedded snapshot is 184 rows of security boundary. Re-serialising it
    through json.dumps would reformat every line and make the one diff that
    matters — a changed sha256 — unreadable. Byte-for-byte, on the bump path
    as well as under --snapshot-only."""
    committed = manifest("0.5.1", "0.5.2")
    # Indented and newline-terminated: a json.dumps round-trip loses both.
    incoming = json.dumps(manifest("0.5.1", "0.5.2", "0.5.3"), indent=4).encode() + b"\n"
    with sandbox("0.5.2", committed, argv=[]) as tmp, served(incoming):
        update_dist.main()
        assert embedded_bytes(tmp) == written(incoming), "the bump path must write the fetched bytes"
        assert pin_of(tmp) == "0.5.3", "the bump must move the pin"
        assert '"0.5.3"' in (tmp / "workflows" / "ci.yml").read_text(), "the bump must move the CI pins"


# --- helper: version_key already has a body; these must pass today ----------


def test_version_key_orders_numerically_and_dies_on_junk():
    """The forward-only check relies on it. A non-numeric component exits with a message rather
    than raising a raw ValueError at the caller."""
    assert update_dist.version_key("0.5.2") == (0, 5, 2)
    assert update_dist.version_key("0.5.10") > update_dist.version_key("0.5.9")
    dies(update_dist.version_key, "0.6.0-beta1", why="a non-numeric component")
    dies(update_dist.version_key, "", why="an empty version")


def test_version_key_die_covers_what_isdigit_would_wave_through():
    """The docstring promises die(), so no input may reach a raw exception —
    and none may parse to a number that is not what it looks like. isdigit()
    accepts superscripts (ValueError at int()) and Arabic-Indic digits (which
    parse silently); a non-string arrives from manifest["latest"]["version"]."""
    assert dies(update_dist.version_key, "0.5.²", why="a superscript component")
    assert dies(update_dist.version_key, "٥.٥.٢", why="Arabic-Indic digits")
    assert dies(update_dist.version_key, None, why="a non-string version")
    assert dies(update_dist.version_key, ["0", "5", "2"], why="a list version")
    assert dies(update_dist.version_key, 5, why="an int version")


# --- lockstep ---------------------------------------------------------------


def test_check_requires_ci_pins_to_equal_the_module_pin():
    """--check is where a drifted setup-ocx pin is noticed: Renovate or a hand
    edit can move one workflow without the module, and CI would then test a
    different ocx than the one ocx_bootstrap() ships."""
    committed = manifest("0.5.2")
    with sandbox("0.5.2", committed, argv=["--check"]):
        update_dist.main()
    with sandbox("0.5.2", committed, argv=["--check"], ci_pin="0.5.1") as tmp:
        msg = dies(update_dist.main, why="a CI pin behind the module pin")
    assert "ci.yml" in msg and "0.5.1" in msg, f"die() must name the workflow and pin; got: {msg}"


def test_a_failed_ci_repin_leaves_the_module_untouched():
    """The module is written only after every workflow can be repinned: a step
    the script cannot rewrite must not leave a new snapshot beside an old pin."""
    committed = manifest("0.5.1", "0.5.2")
    incoming = json.dumps(manifest("0.5.1", "0.5.2", "0.5.3")).encode()
    with sandbox("0.5.2", committed, argv=[]) as tmp, served(incoming):
        update_dist.write(tmp / "workflows" / "other.yml", "      - uses: ocx-sh/setup-ocx@v1\n")
        before = (tmp / "ocx.cmake").read_bytes()
        dies(update_dist.main, why="an unrepinnable setup-ocx step")
        assert (tmp / "ocx.cmake").read_bytes() == before, "the module was written before the CI plan passed"


class GuardTests(unittest.TestCase):
    """Every module-level test_* function above, run by unittest."""


for _name, _fn in list(globals().items()):
    if _name.startswith("test_") and callable(_fn):
        setattr(GuardTests, _name, staticmethod(_fn))
del _name, _fn  # a leaked class-typed _fn would be collected a second time


if __name__ == "__main__":
    unittest.main()
