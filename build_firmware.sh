git clone git://git.yoctoproject.org/poky -b honister
cd poky; 

#checkout the tested version of the layer Poky
git checkout fd00d74f47ceb57a619c4d0a0553ff0a30bbb7a4

ln -s ../meta-jsdelivr/ meta-jsdelivr


git clone https://github.com/openembedded/meta-openembedded.git -b honister
#checkout the tested version of the layer OpenEmbedded 
cd meta-openembedded ; git checkout 0e6c34f82ca4d43cbca3754c5fe37c5b3bdd0f37 ; cd ..

git clone https://github.com/linux-sunxi/meta-sunxi.git -b honister
#checkout the tested version of the layer Sunxi
cd meta-sunxi; git checkout 8e763ac1c067faedb9f3c7069bd22dc91c833874 ; cd ..

git clone git://git.yoctoproject.org/meta-virtualization.git -b honister
#checkout the tested version of the layer Virtualization
cd meta-virtualization ; git checkout e69e3df88aa56bd05a8c2d5df759fed24072c55a ; cd ..

mkdir build
cp -r meta-jsdelivr/build_conf/ build/conf
source oe-init-build-env
bitbake  core-image-full-cmdline
cd ../..
rm *.sunxi-sdimg
cp  poky/build/tmp/deploy/images/nanopi-neo/core-image-full-cmdline-nanopi-neo-2*.sunxi-sdimg ./



