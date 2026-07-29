"""Make .lisp files importable from Python.

Registering a loader rather than providing a `load` function is what turns the
system from a tool you run into a language you can add to an existing program:
a Python module says ``import analysis`` and does not need to know that
``analysis.lisp`` is Common Lisp.

Compilation goes through the ordinary source-file machinery, so the result is
cached as bytecode next to the source.  A second run does not start SBCL --
the Lisp is needed to build the module, not to import it.
"""

import hashlib
import importlib
import importlib.machinery as machinery
import pathlib
import sys

import hy
from hy.compiler import hy_compile

from . import api

SUFFIX = ".lisp"


def _self_stamp():
    """A number that changes whenever hyclb's own translation changes.

    The bytecode cache is invalidated by the source file's mtime and size, so
    on its own it survives an upgrade of the translator: a module imported
    yesterday keeps running yesterday's compilation.  Folding this stamp into
    the reported mtime makes a change to hyclb (or to Hy) look like a change
    to every .lisp source.
    """
    h = hashlib.sha256()
    here = pathlib.Path(__file__).parent
    for name in sorted(p.name for p in here.iterdir()
                       if p.suffix in (".py", ".hy", ".lisp")):
        h.update((here / name).read_bytes())
    h.update(getattr(hy, "__version__", "?").encode())
    return int.from_bytes(h.digest()[:4], "little")


_STAMP = None


class LispLoader(machinery.SourceFileLoader):
    def path_stats(self, path):
        global _STAMP
        if _STAMP is None:
            _STAMP = _self_stamp()
        st = dict(super().path_stats(path))
        st["mtime"] = (int(st["mtime"]) ^ _STAMP) & 0xFFFFFFFF
        return st

    def source_to_code(self, data, path, *, _optimize=-1):
        # Not super(): Hy replaces SourceFileLoader.source_to_code with its
        # own, which expects the bytes of a .hy file.
        source = data.decode("utf-8")
        tree = hy.models.Lazy(iter(api.PRELUDE + api.to_models(source)))
        return compile(
            hy_compile(tree, self.name, filename=path, source=source),
            path,
            "exec",
            dont_inherit=True,
            optimize=_optimize,
        )


_installed = False


def install():
    """Teach Python's import system about .lisp files."""
    global _installed
    if _installed:
        return
    hook = machinery.FileFinder.path_hook(
        (LispLoader, [SUFFIX]),
        (machinery.ExtensionFileLoader, machinery.EXTENSION_SUFFIXES),
        (machinery.SourceFileLoader, machinery.SOURCE_SUFFIXES),
        (machinery.SourcelessFileLoader, machinery.BYTECODE_SUFFIXES),
    )
    sys.path_hooks.insert(0, hook)
    sys.path_importer_cache.clear()
    importlib.invalidate_caches()
    _installed = True
