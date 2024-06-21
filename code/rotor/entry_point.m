@import Cocoa;
@import Metal;
@import QuartzCore;
@import simd;

#include "base/base_include.h"
#include "os/os_include.h"
#include "rotor_app_delegate.h"
#include "rotor_glyph_atlas.h"
#include "rotor_main_view.h"

#include "base/base_include.c"
#include "os/os_include.c"
#include "rotor_app_delegate.m"
#include "rotor_glyph_atlas.m"
#include "rotor_main_view.m"

S32
main(S32 argument_count, char **arguments)
{
	@autoreleasepool
	{
		[NSApplication sharedApplication];
		AppDelegate *app_delegate = [[AppDelegate alloc] init];
		NSApp.delegate = app_delegate;
		[NSApp run];
	}
}
