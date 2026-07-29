"""Make .lisp files importable from Python.

Registering a loader rather than providing a `load` function is what turns the
system from a tool you run into a language you can add to an existing program:
a Python module says ``import analysis`` and does not need to know that
``analysis.lisp`` is Common Lisp.

Compilation goes through the ordinary source-file machinery, so the result is
cached as bytecode next to the source.  A second run does not start SBCL --
the Lisp is needed to build the module, not to import it.
"""

import importlib
import importlib.machinery as machinery
import sys

import hy
from hy.compiler import hy_compile

from . import api

SUFFIX = ".lisp"


class LispLoader(machinery.SourceFileLoader):
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
