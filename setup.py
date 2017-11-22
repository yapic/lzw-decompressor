from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
  ext_modules = cythonize([
      Extension(
        "bigtiff_lzw_decompress",
        ["lzw_decompress.pyx"],
        language="c++",
        extra_compile_args=['-O3'],
        extra_link_args=['-O2'],
    )]),
)
