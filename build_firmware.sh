git clone git://git.yoctoproject.org/poky -b honister
cd poky
ln -s ../meta-jsdelivr/ meta-jsdelivr
git clone https://github.com/openembedded/meta-openembedded.git -b honister
git clone https://github.com/linux-sunxi/meta-sunxi.git -b honister
git clone git://git.yoctoproject.org/meta-virtualization -b honister
mkdir build
cp -r meta-jsdelivr/build_conf/ build/conf
source oe-init-build-env
bitbake  core-image-full-cmdline
cd ../..
rm *.sunxi-sdimg
cp  poky/build/tmp/deploy/images/nanopi-neo/core-image-full-cmdline-nanopi-neo-2*.sunxi-sdimg ./



