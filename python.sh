package: Python
version: v2.7.10
requires:
 - AliEn-Runtime
 - zlib
 - FreeType
 - libpng
---
#!/bin/bash -ex
# Note: depends on AliEn-Runtime for OpenSSL.

URL="https://www.python.org/ftp/python/${PKGVERSION:1}/Python-${PKGVERSION:1}.tgz"
curl -L -o python.tgz $URL
tar xzf python.tgz
rm -f python.tgz

cd Python-${PKGVERSION:1}

# The only way to pass externals to Python
LDFLAGS=
CPPFLAGS=
for ext in $ALIEN_RUNTIME_ROOT $ALIEN_RUNTIME_ROOT/api $ZLIB_ROOT $FREETYPE_ROOT $LIBPNG_ROOT; do
  [[ -e $ext/include && $ext/lib ]]
  LDFLAGS="-L $ext/lib $LDFLAGS"
  CPPFLAGS="-I $ext/include $CPPFLAGS"
done
export LDFLAGS
export CPPFLAGS

./configure --prefix=$INSTALLROOT \
            --enable-shared \
            --with-system-expat \
            --with-system-ffi \
            --enable-unicode=ucs4
make -j ${JOBS:+-j$JOBS}
make install

# Install pip
cd $BUILDDIR
export PATH=$INSTALLROOT/bin:$PATH
export LD_LIBRARY_PATH=$INSTALLROOT/lib:$LD_LIBRARY_PATH
export DYLD_LIBRARY_PATH=$INSTALLROOT/lib:$DYLD_LIBRARY_PATH
curl -kSsL -o get-pip.py https://bootstrap.pypa.io/get-pip.py
python get-pip.py

# Install extra packages with pip
pip install "numpy==1.9.2"

# Install matplotlib (very tricky)
MATPLOTLIB_VER="1.4.3"
MATPLOTLIB_URL="http://downloads.sourceforge.net/project/matplotlib/matplotlib/matplotlib-${MATPLOTLIB_VER}/matplotlib-${MATPLOTLIB_VER}.tar.gz"
curl -Lo matplotlib.tgz $MATPLOTLIB_URL
tar xzf matplotlib.tgz
cd matplotlib-$MATPLOTLIB_VER
cat > setup.cfg <<EOF
[directories]
basedirlist  = $PWD/fake_freetype_root,$FREETYPE_ROOT,$LIBPNG_ROOT,$ZLIB_ROOT,/usr/X11R6

[gui_support]
gtk = False
gtkagg = False
tkagg = False
wxagg = False
macosx = False
EOF

# Disable pkg-config: it messes with FreeType detection
cat > pkg-config <<EOF
#!/bin/bash
exit 1
EOF
chmod +x pkg-config
export PATH=$PWD:$PATH

# matplotlib wants include files in <PackageRoot>/include, but this is not the
# case for FreeType: let's fix it
mkdir fake_freetype_root
ln -nfs $FREETYPE_ROOT/include/freetype2 fake_freetype_root/include

python setup.py build
python setup.py install

# Remove useless stuff
rm -rvf $INSTALLROOT/share \
       $INSTALLROOT/lib/python*/test
find $INSTALLROOT/lib/python* \
     -mindepth 2 -maxdepth 2 -type d -and \( -name test -or -name tests \) \
     -exec rm -rvf '{}' \;

# Modulefile
MODULEDIR="$INSTALLROOT/etc/modulefiles"
MODULEFILE="$MODULEDIR/$PKGNAME"
mkdir -p "$MODULEDIR"
cat > "$MODULEFILE" <<EoF
#%Module1.0
proc ModulesHelp { } {
  global version
  puts stderr "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
}
set version $PKGVERSION-@@PKGREVISION@$PKGHASH@@
module-whatis "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
# Dependencies
module load BASE/1.0 AliEn-Runtime/$ALIEN_RUNTIME_VERSION-$ALIEN_RUNTIME_REVISION zlib/$ZLIB_VERSION-$ZLIB_REVISION
# Our environment
setenv PYTHON_ROOT \$::env(BASEDIR)/$PKGNAME/\$version
prepend-path PATH $::env(PYTHON_ROOT)/bin
prepend-path LD_LIBRARY_PATH $::env(PYTHON_ROOT)/lib
EoF
