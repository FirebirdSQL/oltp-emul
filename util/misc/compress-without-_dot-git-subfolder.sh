#!/bin/bash

rm -f ./oltp-emul.7z
set -x
7za u -mx9 -mfb273 -stl -xr'!'.* ./oltp-emul.7z .
7za l ./oltp-emul.7z
set +x

