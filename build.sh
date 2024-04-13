#!/bin/sh

set -e

clang-format -i Source/**/*.h Source/**/*.m Source/**/*.metal

rm -rf Products
mkdir -p Products/Rotor.app/Contents
mkdir Products/Rotor.app/Contents/MacOS
mkdir Products/Rotor.app/Contents/Resources

cp Source/Rotor/Rotor-Info.plist Products/Rotor.app/Contents/Info.plist
plutil -convert binary1 Products/Rotor.app/Contents/Info.plist

clang -o Products/Rotor.app/Contents/MacOS/Rotor \
	-I Source \
	-fobjc-arc -framework Cocoa -framework Metal -framework QuartzCore \
	-Os \
	-g3 \
	-ftrivial-auto-var-init=zero -fwrapv -fsanitize=address,undefined -fshort-enums \
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
	Source/Rotor/EntryPoint.m

xcrun metal \
	-o Products/Rotor.app/Contents/Resources/Shaders.metallib \
	Source/Rotor/Shaders.metal

cp Source/Rotor/Rotor.entitlements Products/Rotor.entitlements
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool YES' \
	Products/Rotor.entitlements
codesign \
	--sign - \
	--entitlements Products/Rotor.entitlements \
	--options runtime Products/Rotor.app/Contents/MacOS/Rotor
