#!/bin/sh

set -e

clang-format -i code/**/*.c code/**/*.h code/**/*.m code/**/*.metal

rm -rf build
mkdir -p build/Rotor.app/Contents
mkdir build/Rotor.app/Contents/MacOS
mkdir build/Rotor.app/Contents/Resources

cp data/Rotor-Info.plist build/Rotor.app/Contents/Info.plist
plutil -convert binary1 build/Rotor.app/Contents/Info.plist

clang -o build/Rotor.app/Contents/MacOS/Rotor \
	-I code \
	-fmodules -fobjc-arc \
	-g3 \
	-ftrivial-auto-var-init=zero -fwrapv -fsanitize=undefined \
	-W \
	-Wall \
	-Wextra \
	-Wpedantic \
	-Wconversion \
	-Wimplicit-fallthrough \
	-Wmissing-prototypes \
	-Wshadow \
	-Wstrict-prototypes \
	-Wno-unused-parameter \
	code/rotor/entry_point.m

xcrun metal \
	-o build/Rotor.app/Contents/Resources/shaders.metallib \
	-gline-tables-only -frecord-sources \
	code/rotor/shaders.metal

cp data/Rotor.entitlements build/Rotor.entitlements
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool YES' \
	build/Rotor.entitlements
codesign \
	--sign - \
	--entitlements build/Rotor.entitlements \
	--options runtime build/Rotor.app/Contents/MacOS/Rotor
