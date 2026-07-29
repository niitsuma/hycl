"""Common Lisp on Python, with SBCL as the macroexpander.

Importing this package makes .lisp files importable, the way importing `hy`
makes .hy files importable.
"""

from .loader import install

install()
