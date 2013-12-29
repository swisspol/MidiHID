/*
	This file is part the MidiHID software for Mac OS X.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import "MidiHIDController.h"

#define kTextImageMargin			4.0

static NSComparisonResult _SortFunction(DeviceController* controller1, DeviceController* controller2, void* context)
{
	return [[controller1 name] caseInsensitiveCompare:[controller2 name]];
}

@interface MidiHIDController (Internal)
- (void) _selectDeviceMenu;
- (void) _saveController:(DeviceController*)controller;
- (BOOL) _isNameUnique:(NSString*)name;
@end

@implementation TextImageCell

- (NSRect) drawingRectForBounds:(NSRect)theRect
{
	theRect = [super drawingRectForBounds:theRect];
	theRect.size.width -= theRect.size.height + kTextImageMargin;
	
	return theRect;
}

- (void) drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView*)controlView
{
	NSImage*				image = [self representedObject];
	NSSize					size = [image size];
	
	[image setFlipped:YES];
	[image drawInRect:NSMakeRect(cellFrame.origin.x, cellFrame.origin.y + ceil((cellFrame.size.height - size.height) / 2.0), size.width, size.height) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	[image setFlipped:NO];
	cellFrame.origin.x += cellFrame.size.height + kTextImageMargin;
	
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end

@implementation SourceView

@synthesize undoManager=_undoManager;

- (void) dealloc
{
	[_undoManager removeAllActionsWithTarget:self];
	[_undoManager release];
	
	[super dealloc];
}

- (void) undo:(id)sender
{
	[_undoManager undo];
}

- (void) redo:(id)sender
{
	[_undoManager redo];
}

- (BOOL) validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem
{
	if([anItem action] == @selector(undo:))
	return [_undoManager canUndo];
	if([anItem action] == @selector(redo:))
	return [_undoManager canRedo];
	
	return [super validateUserInterfaceItem:anItem];
}

@end

@implementation DeviceController

@synthesize fileName=_fileName, sourceEdited=_sourceEdited, hasChanges=_hasChanges, undoManager=_undoManager;

+ (NSSet*) keyPathsAffectingChanges
{
	return [NSSet setWithObjects:@"name", @"devicePath", @"exclusive", @"autoReset", @"source", nil];
}

- (id) initWithMidiEnabled:(BOOL)midiEnabled oscEnabled:(BOOL)oscEnabled
{
	NSString*					path;
	
	if((self = [super initWithMidiEnabled:midiEnabled oscEnabled:oscEnabled])) {
		_undoManager = [NSUndoManager new];
		
		for(path in [[self class] keyPathsAffectingChanges])
		[self addObserver:self forKeyPath:path options:0 context:[DeviceController class]];
	}
	
	return self;
}

- (void) dealloc
{
	NSString*					path;
	
	if(_undoManager) {
		for(path in [[self class] keyPathsAffectingChanges])
		[self removeObserver:self forKeyPath:path];
	}
	
	[self setLoggingEnabled:NO];
	
	[_undoManager removeAllActions];
	[_undoManager release];
	[_fileName release];
	
	[super dealloc];
}

- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == [DeviceController class])
	[self setHasChanges:YES];
	else
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (BOOL) validateName:(id*)ioValue error:(NSError**)outError
{
	if(![*ioValue length]) {
		if(outError)
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:[NSDictionary dictionaryWithObject:LOCALIZED_STRING(@"INVALID_NAME") forKey:NSLocalizedDescriptionKey]];
		return NO;
	}
	
	if(![(MidiHIDController*)[NSApp delegate] _isNameUnique:*ioValue]) {
		if(outError)
		*outError = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:[NSDictionary dictionaryWithObject:LOCALIZED_STRING(@"INVALID_NAME") forKey:NSLocalizedDescriptionKey]];
		return NO;
	}
	
	return YES;
}

- (void) setSourceEdited:(BOOL)flag
{
	if(flag != _sourceEdited) {
		[self willChangeValueForKey:@"sourceEdited"];
		_sourceEdited = flag;
		[self didChangeValueForKey:@"sourceEdited"];
	}
}

- (void) setHasChanges:(BOOL)flag
{
	if(flag != _hasChanges) {
		[self willChangeValueForKey:@"hasChanges"];
		_hasChanges = flag;
		[self didChangeValueForKey:@"hasChanges"];
	}
}

- (void) setLoggingEnabled:(BOOL)flag
{
	[self willChangeValueForKey:@"logString"];
	if(flag) {
		if(_log == nil)
		_log = [NSMutableString new];
	}
	else {
		[_log release];
		_log = nil;
	}
	[self didChangeValueForKey:@"logString"];
}

- (BOOL) isLoggingEnabled
{
	return (_log ? YES : NO);
}

- (NSString*) logString
{
	return (_log ? _log : @"");
}

- (void) clearLog
{
	[self willChangeValueForKey:@"logString"];
	[_log setString:@""];
	[self didChangeValueForKey:@"logString"];
}

- (void) _logMessage:(NSString*)message
{
	[self willChangeValueForKey:@"logString"];
	[_log appendString:message];
	[_log appendString:@"\n"];
	[self didChangeValueForKey:@"logString"];
}

/* Override */
- (void) setSource:(NSString*)source
{
	[super setSource:source];
	
	[self setSourceEdited:NO];
}

/* Override */
- (id) initWithFile:(NSString*)path
{
	if((self = [super initWithFile:path])) {
		_fileName = [[path lastPathComponent] copy];
		
		[self setHasChanges:NO];
	}
	
	return self;
}

- (BOOL) writeToFile:(NSString*)path
{
	if(![super writeToFile:path])
	return NO;
	
	[self willChangeValueForKey:@"fileName"];
	[_fileName release];
	_fileName = [[path lastPathComponent] copy];
	[self didChangeValueForKey:@"fileName"];
	
	[self setHasChanges:NO];
	
	return YES;
}

/* Can be called from HID thread */
- (void) logMessage:(NSString*)message
{
	if(_log)
	[self performSelectorOnMainThread:@selector(_logMessage:) withObject:message waitUntilDone:NO];
}

@end

@implementation MidiHIDController

@synthesize selectedController=_selectedController;

+ (void) initialize
{
	NSMutableDictionary*			defaults;
	
	if(self == [MidiHIDController class]) {
		defaults = [NSMutableDictionary new];
		//[defaults setObject:nil forKey:kDefaultKey_CheckForUpdateOnLaunch];
		[defaults setObject:[NSNumber numberWithBool:NO] forKey:kDefaultKey_ExpandedWindow];
		[defaults setObject:[NSNumber numberWithFloat:800] forKey:kDefaultKey_ExpandedSize];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
		[defaults release];
	}
}

+ (BOOL) autoSaveSettings
{
	return YES;
}

+ (NSString*) configurationDirectory
{
	static NSString*				path = nil;
	
	if(path == nil) {
		path = [[[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:kConfigurationsDirectory] copy];
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:NULL];
	}
	
	return path;
}

+ (NSArray*) configurationDirectories
{
	return [NSArray arrayWithObject:[self configurationDirectory]];
}

+ (Class) deviceControllerClass
{
	return [DeviceController class];
}

- (BOOL) _isNameUnique:(NSString*)name
{
	DeviceController*			controller;
	
	for(controller in [self controllers]) {
		if([name caseInsensitiveCompare:[controller name]] == NSOrderedSame)
		return NO;
		if([name caseInsensitiveCompare:[[[controller fileName] lastPathComponent] stringByDeletingPathExtension]] == NSOrderedSame)
		return NO;
	}
	
	return YES;
}

@end

@implementation MidiHIDController (Actions)

- (IBAction) endModal:(id)sender
{
	if([sender tag])
	[NSApp stopModal];
	else
	[NSApp abortModal];
}

- (IBAction) newConfiguration:(id)sender
{
	NSUInteger					i = 0;
	DeviceController*			controller;
	NSString*					name;
	NSDictionary*				configuration;
	
	do {
		name = [NSString stringWithFormat:LOCALIZED_STRING(@"DEFAULT_NAME"), ++i];
	} while(![self _isNameUnique:name]);
	
	configuration = [NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Configuration" ofType:kConfigurationExtension]] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
	controller = [[DeviceController alloc] initWithConfiguration:configuration];
	if(![NSApp isHidden])
	[controller setActiveStatusDelay:kStatusDelay];
	if([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ExpandedWindow])
	[controller setLoggingEnabled:YES];
	[controller setName:name];
	[controller setEnabled:YES];
	
	[[self controllers] addObject:controller];
	[[self controllers] sortUsingFunction:_SortFunction context:NULL];
	[controllerOutlineView reloadData];
	[controllerOutlineView selectRow:[controllerOutlineView rowForItem:controller] byExtendingSelection:NO];
	
	[controller addObserver:self forKeyPath:@"name" options:0 context:[self class]];
	[controller addObserver:self forKeyPath:@"status" options:0 context:[self class]];
	[controller release];
	
	[self outlineViewSelectionDidChange:nil]; //HACK: Force KVO to refresh
	
	if(![[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ExpandedWindow])
	[self toggleExpand:self];
}

- (IBAction) deleteConfiguration:(id)sender
{
	NSAlert*						alert;
	
	alert = [NSAlert alertWithMessageText:LOCALIZED_STRING(@"DELETE_TITLE") defaultButton:LOCALIZED_STRING(@"DELETE_DEFAULT_BUTTON") alternateButton:LOCALIZED_STRING(@"DELETE_ALTERNATE_BUTTON") otherButton:nil informativeTextWithFormat:LOCALIZED_STRING(@"DELETE_MESSAGE")];
	if([alert runModal] == NSAlertAlternateReturn) {
		if([self.selectedController fileName] && ![[NSFileManager defaultManager] removeItemAtPath:[[[self class] configurationDirectory] stringByAppendingPathComponent:[self.selectedController fileName]] error:NULL]) {
			NSLog(@"Failed deleting configuration file \"%@\"", [[[self class] configurationDirectory] stringByAppendingPathComponent:[self.selectedController fileName]]);
			return;
		}
		
		[self.selectedController removeObserver:self forKeyPath:@"name"];
		[self.selectedController removeObserver:self forKeyPath:@"status"];
		[[self controllers] removeObject:self.selectedController];
		[controllerOutlineView reloadData];
		
		[self outlineViewSelectionDidChange:nil]; //HACK: Force KVO to refresh
	}
}

- (IBAction) revertConfiguration:(id)sender
{
	NSString*						path = [[[self class] configurationDirectory] stringByAppendingPathComponent:[self.selectedController fileName]];
	NSDictionary*					settings = [self.selectedController saveSettings];
	DeviceController*				controller;
	
	controller = [[DeviceController alloc] initWithFile:path];
	if(![NSApp isHidden])
	[controller setActiveStatusDelay:kStatusDelay];
	if([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ExpandedWindow])
	[controller setLoggingEnabled:YES];
	[controller loadSettings:settings];
	if(controller == nil) {
		NSLog(@"Failed loading configuration file \"%@\"", path);
		return;
	}
	
	[self.selectedController removeObserver:self forKeyPath:@"name"];
	[self.selectedController removeObserver:self forKeyPath:@"status"];
	[[self controllers] removeObject:self.selectedController];
	[[self controllers] addObject:controller];
	[[self controllers] sortUsingFunction:_SortFunction context:NULL];
	[controllerOutlineView reloadData];
	[controllerOutlineView selectRow:[controllerOutlineView rowForItem:controller] byExtendingSelection:NO];
	
	[controller addObserver:self forKeyPath:@"name" options:0 context:[self class]];
	[controller addObserver:self forKeyPath:@"status" options:0 context:[self class]];
	[controller release];
	
	[self outlineViewSelectionDidChange:nil]; //HACK: Force KVO to refresh
}

- (void) _saveController:(DeviceController*)controller
{
	NSString*						path = [[[self class] configurationDirectory] stringByAppendingPathComponent:([controller fileName] ? [controller fileName] : [[controller name] stringByAppendingPathExtension:kConfigurationExtension])];
	
	if(![controller writeToFile:path])
	NSLog(@"Failed saving configuration to file \"%@\"", path);
}

- (IBAction) saveConfiguration:(id)sender
{
	[self _saveController:self.selectedController];
}

- (IBAction) selectDevice:(id)sender
{
	[self.selectedController setDevicePath:[[devicePopUpButton selectedItem] representedObject]];
}

- (IBAction) performAction:(id)sender
{
	NSInteger				index = [[sender menu] indexOfItem:sender];
	
	if(index) {
		[self.selectedController setEnabled:YES];
		[self.selectedController setMidiChannel:(index - 1)];
	}
	else
	[self.selectedController setEnabled:NO];
}

- (IBAction) showActionMenu:(id)sender
{
	NSMenuItem*				item;
	
	for(item in [actionMenu itemArray])
	[item setState:NSOffState];
	if([self.selectedController isEnabled])
	[[actionMenu itemAtIndex:(1 + [self.selectedController midiChannel])] setState:NSOnState];
	else
	[[actionMenu itemAtIndex:0] setState:NSOnState];
	
	[NSMenu popUpContextMenu:actionMenu withEvent:[NSApp currentEvent] forView:sender];
}

- (IBAction) updateScript:(id)sender
{
	[self.selectedController setSource:[sourceView string]];
	[self.selectedController clearLog];
}

- (IBAction) clearLog:(id)sender
{
	[self.selectedController clearLog];
}

- (IBAction) toggleExpand:(id)sender
{
	NSUserDefaults*			defaults = [NSUserDefaults standardUserDefaults];
	NSRect					frame = [mainWindow frame];
	BOOL					wasExpended = [defaults boolForKey:kDefaultKey_ExpandedWindow];
	DeviceController*		controller;
	
	if(sender)
	[defaults setBool:![defaults boolForKey:kDefaultKey_ExpandedWindow] forKey:kDefaultKey_ExpandedWindow];
	
	if([defaults boolForKey:kDefaultKey_ExpandedWindow]) {
		frame.size.width = [defaults floatForKey:kDefaultKey_ExpandedSize];
		[mainWindow setFrame:frame display:YES animate:YES];
		[mainWindow setMinSize:NSMakeSize(700, 400)];
		[mainWindow setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
		[expandButton setImage:[NSImage imageNamed:NSImageNameLeftFacingTriangleTemplate]];
		[expandView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
		
		for(controller in [self controllers])
		[controller setLoggingEnabled:YES];
	}
	else {
		if(wasExpended)
		[defaults setFloat:frame.size.width forKey:kDefaultKey_ExpandedSize];
		[expandView setAutoresizingMask:NSViewHeightSizable];
		frame.size.width = 200;
		[mainWindow setFrame:frame display:YES animate:YES];
		[mainWindow setMinSize:NSMakeSize(200, 400)];
		[mainWindow setMaxSize:NSMakeSize(200, FLT_MAX)];
		[expandButton setImage:[NSImage imageNamed:NSImageNameRightFacingTriangleTemplate]];
		
		for(controller in [self controllers])
		[controller setLoggingEnabled:NO];
	}
}

@end

@implementation MidiHIDController (NSApplication)

- (void) applicationWillFinishLaunching:(NSNotification*)notification
{
	_statusImages[kBridgeControllerStatus_Disabled] = [[NSImage imageNamed:@"Dot-Gray"] retain];
	_statusImages[kBridgeControllerStatus_Offline] = [[NSImage imageNamed:@"Dot-Red"] retain];
	_statusImages[kBridgeControllerStatus_Idle] = [[NSImage imageNamed:@"Dot-Green"] retain];
	_statusImages[kBridgeControllerStatus_Active] = [[NSImage imageNamed:@"Dot-Orange"] retain];
}

- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == [self class]) {
		if([keyPath isEqualToString:@"name"]) {
			[[self controllers] sortUsingFunction:_SortFunction context:NULL];
			[controllerOutlineView reloadData];
			[controllerOutlineView selectRow:[controllerOutlineView rowForItem:object] byExtendingSelection:NO];
		}
		else if([keyPath isEqualToString:@"status"])
		[controllerOutlineView setNeedsDisplayInRect:[controllerOutlineView rectOfRow:[controllerOutlineView rowForItem:object]]];
		else if([keyPath isEqualToString:@"selectedController.logString"]) {
			if(self.selectedController)
			[logTextView setString:[self.selectedController logString]];
			else
			[logTextView setString:@""];
		}
		else if([keyPath isEqualToString:@"selectedController.lastSourceError"])
		[sourceView setErrorLine:[[self.selectedController lastSourceError] code]];
	}
	else
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) _selectDeviceMenu
{
	NSMenuItem*					item;
	
	for(item in [devicePopUpButton itemArray]) {
		if([[item representedObject] isEqualToString:[self.selectedController devicePath]])
		break;
	}
	[devicePopUpButton selectItem:item];
}

- (void) _updateDeviceMenu:(NSNotification*)notification
{
	NSDictionary*			devices = [HIDController allDevices];
	NSString*				key;
	
	[devicePopUpButton removeAllItems];
	for(key in devices) {
		[devicePopUpButton addItemWithTitle:[NSString stringWithFormat:LOCALIZED_STRING(@"DEVICE_TITLE"), [[devices objectForKey:key] objectForKey:@"Product"], [[devices objectForKey:key] objectForKey:@"PrimaryUsage"]]];
		[[devicePopUpButton lastItem] setRepresentedObject:key];
	}
	
	[self _selectDeviceMenu];
}

- (void) _sourceDidUpdate:(NSNotification*)notification
{
	[self.selectedController setSourceEdited:YES];
}

/* Override */
- (void) applicationDidFinishLaunching:(NSNotification*)notification
{
	NSUserDefaults*			defaults = [NSUserDefaults standardUserDefaults];
	NSColor*				color = [NSColor colorWithDeviceRed:0.54 green:0.07 blue:0.08 alpha:1.0];
	NSMutableDictionary*	keywords = [SourceTextView keywordColorsFromKeywordsPropertyList:[[NSBundle mainBundle] pathForResource:@"SourceTextViewKeywords-Lua" ofType:@"plist"]];
	TextImageCell*			cell;
	DeviceController*		controller;
	
	[super applicationDidFinishLaunching:notification];
	[[self controllers] sortUsingFunction:_SortFunction context:NULL];
	for(controller in [self controllers]) {
		[controller addObserver:self forKeyPath:@"name" options:0 context:[self class]];
		[controller addObserver:self forKeyPath:@"status" options:0 context:[self class]];
	}
	
	[self addObserver:self forKeyPath:@"selectedController.logString" options:0 context:[self class]];
	[self addObserver:self forKeyPath:@"selectedController.lastSourceError" options:0 context:[self class]];
	
	[self _updateDeviceMenu:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateDeviceMenu:) name:HIDControllerDidUpdateDevicesNotification object:nil];
	
	[controllerOutlineView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
	[controllerOutlineView setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
	[controllerOutlineView registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
	[controllerOutlineView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
	[controllerOutlineView setIndentationPerLevel:4];
	cell = [TextImageCell new];
	[cell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[cell setEditable:YES];
	[cell setDrawsBackground:NO];
	[cell setLineBreakMode:NSLineBreakByTruncatingMiddle];
	[[[controllerOutlineView tableColumns] objectAtIndex:0] setDataCell:cell];
	[cell release];
	[controllerOutlineView setIntercellSpacing:NSMakeSize(2, 6)];
	[controllerOutlineView setRowHeight:14];
	[controllerOutlineView expandItem:nil expandChildren:YES];
	[controllerOutlineView reloadData];
	if([[self controllers] count])
	[controllerOutlineView selectRow:0 byExtendingSelection:NO];
	[self outlineViewSelectionDidChange:nil];
	
	[sourceView setLanguage:kSourceTextViewLanguage_Lua];
	[keywords setObject:color forKey:@"_event"];
	[keywords setObject:color forKey:@"_connect"];
	[keywords setObject:color forKey:@"_disconnect"];
	[sourceView setKeywordColors:keywords];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_sourceDidUpdate:) name:NSTextDidChangeNotification object:sourceView];
	
	[logTextView setHorizontallyResizable:YES];
	[logTextView setFont:[NSFont fontWithName:@"Monaco" size:9]];
	[logTextView setTextColor:[NSColor darkGrayColor]];
	[[logTextView layoutManager] setDelegate:self];
	
	[mainWindow setContentBorderThickness:32 forEdge:NSMinYEdge];
	[mainWindow setFrameFromString:[defaults objectForKey:kDefaultKey_WindowFrame]];
	[self toggleExpand:nil];
	[mainWindow makeKeyAndOrderFront:nil];
	
	[copyrightTextField setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleGetInfoString"]];
	[notesTextView readRTFDFromFile:[[NSBundle mainBundle] pathForResource:@"ReleaseNotes" ofType:@"rtf"]];
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication*)sender
{
	DeviceController*			controller;
	NSAlert*					alert;
	
	for(controller in [self controllers]) {
		if([controller hasChanges])
		break;
	}
	
	if(controller) {
		alert = [NSAlert alertWithMessageText:LOCALIZED_STRING(@"CHANGES_TITLE") defaultButton:LOCALIZED_STRING(@"CHANGES_DEFAULT_BUTTON") alternateButton:LOCALIZED_STRING(@"CHANGES_ALTERNATE_BUTTON") otherButton:LOCALIZED_STRING(@"CHANGES_OTHER_BUTTON") informativeTextWithFormat:LOCALIZED_STRING(@"CHANGES_MESSAGE")];
		switch([alert runModal]) {
			
			case NSAlertDefaultReturn:
			for(controller in [self controllers]) {
				if([controller hasChanges])
				[self _saveController:controller];
			}
			break;
			
			case NSAlertOtherReturn:
			return NSTerminateCancel;
			break;
			
		}
	}
	
	return NSTerminateNow;
}

/* Override */
- (void) applicationWillTerminate:(NSNotification*)notification
{
	NSUserDefaults*			defaults = [NSUserDefaults standardUserDefaults];
	NSRect					frame = [mainWindow frame];
	
	[mainWindow orderOut:nil];
	
	if([defaults boolForKey:kDefaultKey_ExpandedWindow])
	[defaults setFloat:frame.size.width forKey:kDefaultKey_ExpandedSize];
	else {
		frame.size.width = [defaults floatForKey:kDefaultKey_ExpandedSize];
		[mainWindow setFrame:frame display:NO];
	}
	
	[defaults setObject:[mainWindow stringWithSavedFrame] forKey:kDefaultKey_WindowFrame];
	[defaults synchronize];
	
	[super applicationWillTerminate:notification];
}

@end

@implementation MidiHIDController (NSLayoutManager)

- (void)layoutManager:(NSLayoutManager*)aLayoutManager didCompleteLayoutForTextContainer:(NSTextContainer*)aTextContainer atEnd:(BOOL)flag
{
	if(flag)
	[logTextView scrollRangeToVisible:NSMakeRange([[logTextView textStorage] length], 0)];
}

@end

@implementation MidiHIDController (NSOutlineView)

- (NSInteger) outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item
{
	if(item == nil)
	return [[self controllers] count];
	
	return 0;
}

- (id) outlineView:(NSOutlineView*)outlineView child:(NSInteger)index ofItem:(id)item
{
	if(item == nil)
	return [[self controllers] objectAtIndex:index];
	
	return nil;
}

- (BOOL) outlineView:(NSOutlineView*)outlineView isItemExpandable:(id)item
{
	return NO;
}

- (id) outlineView:(NSOutlineView*)outlineView objectValueForTableColumn:(NSTableColumn*)tableColumn byItem:(id)item
{	
	if([item isKindOfClass:[DeviceController class]])
	return [item name];
	
	return nil;
}

- (void) outlineView:(NSOutlineView*)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn*)tableColumn item:(id)item
{
	[(TextImageCell*)cell setFont:[NSFont systemFontOfSize:11]];
	[(TextImageCell*)cell setRepresentedObject:_statusImages[[(DeviceController*)item status]]];
}

- (void) outlineViewSelectionDidChange:(NSNotification*)notification
{
	NSInteger					row = [controllerOutlineView selectedRow];
	DeviceController*			controller = (row >= 0 ? [controllerOutlineView itemAtRow:row] : nil);
	
	[sourceView setSource:[controller source]];
	[sourceView setUndoManager:[controller undoManager]];
	
	self.selectedController = controller;
	
	[self _selectDeviceMenu];
}

- (BOOL) outlineView:(NSOutlineView*)outlineView writeItems:(NSArray*)items toPasteboard:(NSPasteboard*)pasteboard
{
	DeviceController*			controller = [items objectAtIndex:0];
	NSPoint						location = [outlineView convertPoint:[[NSApp currentEvent] locationInWindow] fromView:nil];
	
	if([controller hasChanges] || ![controller fileName])
	return NO;
	
	return [outlineView dragPromisedFilesOfTypes:[NSArray arrayWithObject:kConfigurationExtension] fromRect:NSMakeRect(location.x - 16, location.y - 16, 32, 32) source:outlineView slideBack:YES event:[NSApp currentEvent]];
}

- (NSArray*) outlineView:(NSOutlineView*)outlineView namesOfPromisedFilesDroppedAtDestination:(NSURL*)dropDestination forDraggedItems:(NSArray*)items
{
	DeviceController*			controller = [items objectAtIndex:0];
	
	if(![dropDestination isFileURL])
	return nil;
	
	if(![[NSFileManager defaultManager] copyItemAtPath:[[[self class] configurationDirectory] stringByAppendingPathComponent:[controller fileName]] toPath:[[dropDestination path] stringByAppendingPathComponent:[controller fileName]] error:NULL])
	return nil;
	
	return [NSArray arrayWithObject:[controller fileName]];
}

- (NSDragOperation) outlineView:(NSOutlineView*)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
	NSArray*					filenames = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	NSString*					path;
	
	for(path in filenames) {
		if(![[[path pathExtension] lowercaseString] isEqualToString:kConfigurationExtension])
		return NSDragOperationNone;
		if([path hasPrefix:[[self class] configurationDirectory]])
		return NSDragOperationNone;
		if(![self _isNameUnique:[[path lastPathComponent] stringByDeletingPathExtension]])
		return NSDragOperationNone;
	}
	
	return NSDragOperationCopy;
}

- (BOOL) outlineView:(NSOutlineView*)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
	NSArray*					filenames = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	NSString*					path;
	NSString*					file;
	DeviceController*			controller;
	
	for(path in filenames) {
		file = [[[self class] configurationDirectory] stringByAppendingPathComponent:[path lastPathComponent]];
		if(![[NSFileManager defaultManager] copyItemAtPath:path toPath:file error:NULL]) {
			NSLog(@"Failed copying configuration file \"%@\"", path);
			continue;
		}
		
		controller = [[DeviceController alloc] initWithFile:file];
		if(![NSApp isHidden])
		[controller setActiveStatusDelay:kStatusDelay];
		if([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ExpandedWindow])
		[controller setLoggingEnabled:YES];
		[controller setEnabled:YES];
		if(controller == nil) {
			NSLog(@"Failed loading configuration file \"%@\"", file);
			continue;
		}
		
		[[self controllers] addObject:controller];
		[[self controllers] sortUsingFunction:_SortFunction context:NULL];
		[controllerOutlineView reloadData];
		[controllerOutlineView selectRow:[controllerOutlineView rowForItem:controller] byExtendingSelection:NO];
		
		[controller addObserver:self forKeyPath:@"name" options:0 context:[self class]];
		[controller addObserver:self forKeyPath:@"status" options:0 context:[self class]];
		[controller release];
		
		[self outlineViewSelectionDidChange:nil]; //HACK: Force KVO to refresh
	}
	
	return YES;
}

@end

@implementation MidiHIDController (NSWindow)

- (BOOL) windowShouldClose:(NSWindow*)window
{
	[NSApp terminate:nil];
	return NO;
}

@end
