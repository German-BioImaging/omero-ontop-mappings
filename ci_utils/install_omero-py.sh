#! /bin/bash

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod u+x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -u -p ~/miniconda3
source ~/miniconda3/bin/activate
conda install -c nodefaults -c conda-forge -c ome omero-py 'python=3.9'
