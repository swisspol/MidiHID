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

#import <Cocoa/Cocoa.h>

#define kUserDefaultsKey_AppControllerSettings		@"settings"

#define kStatusDelay								0.1 //seconds

#define LOCALIZED_STRING(__STRING__) [[NSBundle mainBundle] localizedStringForKey:(__STRING__) value:(__STRING__) table:nil]

@interface AppController : NSObject
{
@private
	NSMutableArray*				_controllers;
}
+ (BOOL) autoSaveSettings; //NO by default
+ (NSArray*) configurationDirectories; //For subclassing
+ (Class) deviceControllerClass; //BridgeController by default

- (NSMutableArray*) controllers;
@end
