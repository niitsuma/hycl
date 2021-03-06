# -*- coding: utf-8 -*-
import sys
import os
from os import path
from setuptools import find_packages, setup


here = os.path.dirname(os.path.abspath(__file__))
version = next((line.split('=')[1].strip().replace("'", '')
                for line in open(os.path.join(here,
                                              'hyclb',
                                              '__init__.py'))
                if line.startswith('__version__ = ')),
               '0.0.dev0')

setup(
    name='hyclb',
    version=version,
    description='hyclb : common-lisp interface and common-lisp-like functions for hylang',
    url='https://github.com/niitsuma/hycl/',
    author='Hirotaka Niitsuma, Riku Togashi',
    author_email='hirotaka.niitsuma@gmail.com',
    license='MIT License',
    classifiers=[
	'License :: OSI Approved :: MIT License',
        'Operating System :: OS Independent',
        'Programming Language :: Python :: 3.6',
    ],
    keywords='hy lisp common-lisp',
    install_requires=['cl4py','gasync'], #'hy>=0.15' was removed because gentoo linux hy package bug
    packages=['hyclb'],
    package_data={'hyclb': ['*.hy','*.lisp'],},
    test_suite='nose.collector',
    tests_require=['nose'],
    platforms='any',
)
