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

#import "AppController.h"
#import "BridgeController.h"

@interface AppController ()
- (void) _loadConfigurationsFromDirectory:(NSString*)path;
@end

@implementation AppController

+ (BOOL) autoSaveSettings
{
	return NO;
}

+ (NSArray*) configurationDirectories
{
	return nil;
}

+ (Class) deviceControllerClass
{
	return [BridgeController class];
}

- (NSMutableArray*) controllers
{
	return _controllers;
}

- (void) _loadConfigurationsFromDirectory:(NSString*)path
{
	NSArray*					array = [[NSFileManager defaultManager] directoryContentsAtPath:path];
	NSString*					file;
	unsigned					i;
	BridgeController*			controller;
	
	if(array)
	NSLog(@"Loading configuration files from \"%@\"...", path);
	
	for(i = 0; i < [array count]; ++i) {
		file = [array objectAtIndex:i];
		if([file hasPrefix:@"."])
		continue;
		
		controller = [[[[self class] deviceControllerClass] alloc] initWithFile:[path stringByAppendingPathComponent:file]];
		if(controller) {
			[_controllers addObject:controller];
			[controller release];
			if([[NSUserDefaults standardUserDefaults] boolForKey:@"debug"])
			NSLog(@"Successfully loaded configuration \"%@\" (MIDI = %i | OSC = %i)", file, [controller isMidiEnabled], [controller isOSCEnabled]);
		}
		else
		NSLog(@"Failed loading configuration \"%@\"", file);
	}
}

- (void) applicationDidFinishLaunching:(NSNotification*)notification
{
	NSArray*					array = [[self class] configurationDirectories];
	unsigned					i;
	NSMutableDictionary*		dictionary;
	BridgeController*			controller;
	NSDictionary*				settings;
	
	_controllers = [NSMutableArray new];
	for(i = 0; i < [array count]; ++i)
	[self _loadConfigurationsFromDirectory:[array objectAtIndex:i]];
	
	if([[self class] autoSaveSettings])
	dictionary = [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultsKey_AppControllerSettings];
	else
	dictionary = nil;
	for(i = 0; i < [_controllers count]; ++i) {
		controller = [_controllers objectAtIndex:i];
		if((settings = [dictionary objectForKey:[controller devicePath]]))
		[controller loadSettings:settings];
		
		if(![NSApp isHidden])
		[controller setActiveStatusDelay:kStatusDelay];
	}
}

- (void) applicationWillTerminate:(NSNotification*)notification
{
	NSMutableDictionary*		dictionary;
	BridgeController*			controller;
	unsigned					i;
	
	if([[self class] autoSaveSettings]) {
		dictionary = [NSMutableDictionary dictionary];
		for(i = 0; i < [_controllers count]; ++i) {
			controller = [_controllers objectAtIndex:i];
			[dictionary setObject:[controller saveSettings] forKey:[controller devicePath]];
		}
		
		[[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:kUserDefaultsKey_AppControllerSettings];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
}

- (void) applicationWillHide:(NSNotification*)notification
{
	unsigned					i;
	
	for(i = 0; i < [_controllers count]; ++i)
	[[_controllers objectAtIndex:i] setActiveStatusDelay:0.0];
}

- (void) applicationDidUnhide:(NSNotification*)notification;
{
	unsigned					i;
	
	for(i = 0; i < [_controllers count]; ++i)
	[[_controllers objectAtIndex:i] setActiveStatusDelay:kStatusDelay];
}

@end
