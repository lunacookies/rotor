#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <os/log.h>
#import <simd/simd.h>

#include "Base/Base_Include.h"
#include "OS/OS_Include.h"
#include "Rotor_GlyphAtlas.h"
#include "Rotor_MainView.h"

#include "Base/Base_Include.c"
#include "OS/OS_Include.c"
#include "Rotor_GlyphAtlas.m"
#include "Rotor_MainView.m"

function NSString *
AppName(void)
{
	NSBundle *bundle = [NSBundle mainBundle];
	return [bundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey];
}

function NSMenu *
CreateMenu(void)
{
	NSMenu *menu_bar = [[NSMenu alloc] init];

	NSMenuItem *app_menu_item = [[NSMenuItem alloc] init];
	[menu_bar addItem:app_menu_item];

	NSMenu *app_menu = [[NSMenu alloc] init];
	app_menu_item.submenu = app_menu;

	NSString *quit_menu_item_title = [NSString stringWithFormat:@"Quit %@", AppName()];
	NSMenuItem *quit_menu_item = [[NSMenuItem alloc] initWithTitle:quit_menu_item_title
	                                                        action:@selector(terminate:)
	                                                 keyEquivalent:@"q"];

	[app_menu addItem:quit_menu_item];

	return menu_bar;
}

S32
main(S32 argument_count, char **arguments)
{
	@autoreleasepool
	{
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

		NSApp.mainMenu = CreateMenu();

		NSRect rect = NSMakeRect(100, 100, 500, 400);

		NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable |
		                          NSWindowStyleMaskClosable |
		                          NSWindowStyleMaskMiniaturizable;
		NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
		                                               styleMask:style
		                                                 backing:NSBackingStoreBuffered
		                                                   defer:NO];

		MainView *view = [[MainView alloc] initWithFrame:rect];
		window.contentView = view;

		[window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
		[NSApp run];
	}
}
