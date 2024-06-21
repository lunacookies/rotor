@implementation AppDelegate
{
	NSWindow *window;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	NSApp.mainMenu = [self createMenu];

	NSRect rect = NSMakeRect(100, 100, 500, 400);

	NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable |
	                          NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
	window = [[NSWindow alloc] initWithContentRect:rect
	                                     styleMask:style
	                                       backing:NSBackingStoreBuffered
	                                         defer:NO];

	MainView *view = [[MainView alloc] initWithFrame:rect];
	window.contentView = view;
	[window makeKeyAndOrderFront:nil];
}

- (NSMenu *)createMenu
{
	NSMenu *menu_bar = [[NSMenu alloc] init];

	NSMenuItem *app_menu_item = [[NSMenuItem alloc] init];
	[menu_bar addItem:app_menu_item];

	NSMenu *app_menu = [[NSMenu alloc] init];
	app_menu_item.submenu = app_menu;

	NSString *quit_menu_item_title = [NSString stringWithFormat:@"Quit %@", [self appName]];
	NSMenuItem *quit_menu_item = [[NSMenuItem alloc] initWithTitle:quit_menu_item_title
	                                                        action:@selector(terminate:)
	                                                 keyEquivalent:@"q"];

	[app_menu addItem:quit_menu_item];

	return menu_bar;
}

- (NSString *)appName
{
	NSBundle *bundle = [NSBundle mainBundle];
	return [bundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey];
}

@end
