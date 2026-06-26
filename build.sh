#!/bin/bash

set -ex

ls -al
pushd $1
ls -al
vita-makepkg -C -f -d -L
tar -C $VITASDK/arm-vita-eabi/ -xvf *-arm.tar.xz
popd
