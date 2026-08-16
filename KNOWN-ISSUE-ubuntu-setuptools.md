# A `TypeError` seen once while installing on Ubuntu — what it was, and what it was not

Investigated 2026-08-16, Ubuntu 24.04.4, system Python 3.12.3.

**Bottom line: this does not block release, and ordinary `pip install hyclb`
users are not affected.** Recorded because the error message names nothing
useful, so if a user ever reports it we should not have to work it out twice.

## What was seen

A single `pip install --user --break-system-packages -e '.[fast,test]'` failed
with:

```
error: metadata-generation-failed
  File "~/.local/lib/python3.12/site-packages/setuptools/installer.py", line 40, in _present
      return any(_dist_matches_req(dist, req) for dist in metadata.distributions())
  File ".../installer.py", line 64, in _dist_matches_req
      packaging.utils.canonicalize_name(egg_dist.name)
TypeError: expected string or bytes-like object, got 'NoneType'
```

Nothing in the message names hyclb, hy, setuptools' caller, or the real culprit.

## The mechanism (confirmed)

`setuptools.installer._present` scans **every installed distribution** and calls
`canonicalize_name(dist.name)` with no `None` guard. A `.dist-info` directory
that has no `METADATA` yields `dist.name is None`, and the scan dies on it.

Debian and Ubuntu ship exactly such a directory, deliberately:

```
/usr/lib/python3/dist-packages/charset_normalizer-3.3.2.dist-info/     ← real metadata
/usr/lib/python3.12/dist-packages/charset_normalizer-3.3.2.dist-info/
    INSTALLER      ← 7 bytes, "debian". Nothing else.
```

Both paths are listed in `dpkg -L python3-charset-normalizer`; the stub is a
marker telling pip the package is distro-managed. Ubuntu's own setuptools
(68.1.2) has no `_present` at all and is immune; the version in the user site
(84.0.0, pulled in as a dependency of `pip install --user torch`) has it.

Reproduced deterministically with a three-line throwaway package:

```python
setup(name="probe", version="0.0.1", setup_requires=["zzz-not-installed"])
```

`python3 setup.py --version` → `TypeError` with the stub present, normal
"cannot find zzz-not-installed" error with the stub moved aside.

## Why users will not hit it

`_present` is reached only through the legacy `setup_requires` path, and **pip
never takes that path**: it builds in an isolated environment. Every attempt to
reproduce the failure *through pip*, with the stub deliberately restored,
succeeded:

| Attempt (stub present in all cases) | Result |
| --- | --- |
| Fresh venv, `pip install <hyclb source>` | installs fine |
| venv with `--system-site-packages` (stub on `sys.path`, one `None`-named dist visible, `funcparserlib` absent) | installs fine |
| The original command again, `--ignore-installed -e '.[fast,test]'` | installs fine |
| `python3 setup.py` directly, with an uninstalled `setup_requires` | **TypeError** |

Note the third row: hy is relevant here only because it is **sdist-only — no
wheel for any release from 1.0.0 to 1.3.1** — and its `setup.py` declares
`setup_requires=["wheel", "funcparserlib ~= 1.0"]` with no `[build-system]`
table. So installing hyclb *does* build hy from source every time. That build
still goes through pip's isolation, and is fine.

There is no pip configuration on this machine disabling build isolation (no
`pip.conf` anywhere, no `PIP_*` variables, no `.pydistutils.cfg`), so the one
observed failure means isolation was somehow not in effect for that single
invocation. **The reason was not determined**, and the environment has changed
too much since (hy, funcparserlib, pytest, lightning and coverage were all
installed by or after that command) to reconstruct it.

## If a user does report this error

Any one of these clears it:

```bash
# 1. Install into a venv — verified to work even with the stub present
python3 -m venv ~/venvs/hyclb && ~/venvs/hyclb/bin/pip install hyclb

# 2. Pre-install hy's build dependencies, so _present() short-circuits on a
#    match before reaching the bad entry (any() stops at the first True)
pip install --user wheel funcparserlib && pip install --user hyclb

# 3. Move the stub aside (root; apt restores it on package update)
sudo mv /usr/lib/python3.12/dist-packages/charset_normalizer-3.3.2.dist-info{,.disabled}
```

## Where the fault lies

- **Debian**: following the pip spec — a distro-installed package gets an
  `INSTALLER` marker.
- **`importlib.metadata`**: returning `None` for a `.dist-info` without
  `METADATA` is documented behaviour.
- **setuptools**: no `None` guard around `canonicalize_name(egg_dist.name)`.
  This is the only actual defect, and it is upstream of us. Worth reporting if
  still present in current setuptools.
- **hyclb**: not implicated. It is pure PEP 517, has no `setup.py` and no
  `setup_requires`, and builds cleanly on its own.

The one thing worth pushing upstream on our own behalf: **hy publishing a wheel**
would remove a source build from every hy install everywhere, ours included.
