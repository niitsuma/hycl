"""Marks tests as a package so that pytest does not put this directory on
sys.path -- a .lisp file here would otherwise shadow an installed package of
the same name, since the loader claims that extension."""
