#!/bin/sh

GIT_DESCRIPTION=$(git describe --dirty)
OUT=src/gitinfo.d

echo // NOTE: This file was generated automatically. > $OUT
echo module gitinfo\; >> $OUT
echo /// Project current version described by git. >> $OUT
echo enum GIT_DESCRIPTION = \"$GIT_DESCRIPTION\"\; >> $OUT