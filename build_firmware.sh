git clone git://git.yoctoproject.org/poky -b kirkstone
cd poky; 

#checkout the tested version of the layer Poky
git checkout 72ddfbc89aa94c2a4adfe2b8545c52fc2a0065ab

ln -s ../meta-jsdelivr/ meta-jsdelivr


git clone https://github.com/openembedded/meta-openembedded.git -b kirkstone
#checkout the tested version of the layer OpenEmbedded 
cd meta-openembedded ; git checkout 79a6f60dabad9e5b0e041efa91379447ef030482 ; cd ..

git clone https://github.com/linux-sunxi/meta-sunxi.git -b kirkstone
#checkout the tested version of the layer Sunxi
cd meta-sunxi; git checkout 3fce491bba0a93337a35534de0913a0f5b4b4c39 ; cd ..

git clone git://git.yoctoproject.org/meta-virtualization.git -b kirkstone
#checkout the tested version of the layer Virtualization
cd meta-virtualization ; git checkout 2d8b3cba8ff27c9ec2187a52b6a551fe1dcfaa07 ; cd ..

mkdir build
cp -r meta-jsdelivr/build_conf/ build/conf
source oe-init-build-env
bitbake  core-image-full-cmdline
cd ../..
rm *.sunxi-sdimg
cp  poky/build/tmp/deploy/images/nanopi-neo/core-image-full-cmdline-nanopi-neo-2*.sunxi-sdimg ./



