"""Persistent SBCL subprocess used as reader and macroexpander.

SBCL is a build-time dependency: it runs while a .lisp file is being compiled
and takes no part in running the resulting Python.
"""

import atexit
import os
import subprocess
import sys
import threading

from . import reader

SENTINEL = "#<<HYCLB-END>>"
_BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bridge.lisp")


class LispError(RuntimeError):
    pass


class Sbcl:
    def __init__(self, command=("sbcl", "--script"), bridge=_BRIDGE):
        self.proc = subprocess.Popen(
            list(command) + [bridge],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        # The expander reports things worth hearing -- a spec it could not
        # check, a library that failed to load.  Swallowing them means
        # believing a check ran when it did not.
        threading.Thread(target=self._relay_diagnostics, daemon=True).start()

    def _relay_diagnostics(self):
        for line in self.proc.stderr:
            if line.startswith(";"):
                sys.stderr.write("hyclb" + line.rstrip() + "\n")

    # -- plumbing ----------------------------------------------------------

    def _request(self, text):
        if self.proc.poll() is not None:
            raise LispError("SBCL exited; see the diagnostics above")
        self.proc.stdin.write(text + "\n")
        self.proc.stdin.flush()
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise LispError("SBCL closed the connection; see the diagnostics above")
            if line.rstrip("\n") == SENTINEL:
                break
            lines.append(line)
        form = reader.read("".join(lines))
        _check(form)
        return form

    # -- API ---------------------------------------------------------------

    def set_case(self, mode):
        """Readtable case for user source: "invert" or "upcase"."""
        self._request(f":set-case :{mode}")

    def set_stop(self, names):
        """Set the expansion frontier: operators we translate ourselves."""
        self._request(":set-stop (" + " ".join(names) + ")")

    def expand(self, source):
        """Read one form from SOURCE and macroexpand it completely."""
        return self._request(":expand " + source)

    def eval(self, source):
        return self._request(":eval " + source)

    def close(self):
        try:
            self.proc.stdin.write(":quit\n")
            self.proc.stdin.flush()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def _check(form):
    from .runtime import Cons, Keyword

    if isinstance(form, Cons) and isinstance(form.car, Keyword) and form.car.name in ("error", "ERROR"):
        raise LispError(form.cdr.car)


_shared = None


def shared():
    """One SBCL per process, started on first use and closed on exit.

    Without the atexit hook the expander -- and the Maxima it may have
    started -- outlives every compilation.
    """
    global _shared
    if _shared is None:
        _shared = Sbcl()
        atexit.register(_close_shared)
    return _shared


def _close_shared():
    global _shared
    if _shared is not None:
        _shared.close()
        _shared = None
