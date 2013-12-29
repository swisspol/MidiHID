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
#import "SourceTextView.h"

#define kConfigurationsDirectory					@"MidiHID Configurations"
#define kConfigurationExtension						@"plist"

#define kDefaultKey_ExpandedWindow					@"expandedWindow" //BOOL
#define kDefaultKey_ExpandedSize					@"expandedSize" //NSNumber - float
#define kDefaultKey_WindowFrame						@"windowFrame" //NSString

@interface TextImageCell : NSTextFieldCell
@end

@interface SourceView : SourceTextView
{
	NSUndoManager*				_undoManager;
}
@property(nonatomic, retain) NSUndoManager* undoManager;
@end

@interface DeviceController : BridgeController
{
	NSString*					_fileName;
	BOOL						_sourceEdited,
								_hasChanges;
	NSUndoManager*				_undoManager;
	NSMutableString*			_log;
}
@property(nonatomic, readonly) NSString* fileName; //KVO compliant
@property(nonatomic, readonly) NSUndoManager* undoManager;
@property(nonatomic, getter=isLoggingEnabled) BOOL loggingEnabled;
@property(nonatomic, readonly) NSString* logString; //KVO compliant
@property(nonatomic, getter=isSourceEdited) BOOL sourceEdited;
@property(nonatomic) BOOL hasChanges;
- (void) clearLog;
@end

@interface MidiHIDController : AppController
{
	IBOutlet NSWindow*			mainWindow;
	IBOutlet NSOutlineView*		controllerOutlineView;
	IBOutlet NSButton*			expandButton;
	IBOutlet NSView*			expandView;
	IBOutlet SourceView*		sourceView;
	IBOutlet NSTextView*		logTextView;
	IBOutlet NSMenu*			actionMenu;
	IBOutlet NSPopUpButton*		devicePopUpButton;
	
	IBOutlet NSWindow*			aboutWindow;
	IBOutlet NSTextView*		notesTextView;
	IBOutlet NSTextField*		copyrightTextField;
	
	NSImage*					_statusImages[kBridgeControllerStatusCount];
	DeviceController*			_selectedController;
}
@property(nonatomic, retain) DeviceController* selectedController;
@end

@interface MidiHIDController (Actions)
- (IBAction) endModal:(id)sender;
- (IBAction) newConfiguration:(id)sender;
- (IBAction) deleteConfiguration:(id)sender;
- (IBAction) revertConfiguration:(id)sender;
- (IBAction) saveConfiguration:(id)sender;
- (IBAction) selectDevice:(id)sender;
- (IBAction) performAction:(id)sender;
- (IBAction) showActionMenu:(id)sender;
- (IBAction) updateScript:(id)sender;
- (IBAction) clearLog:(id)sender;
- (IBAction) toggleExpand:(id)sender;
@end
