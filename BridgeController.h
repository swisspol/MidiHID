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

#import "HIDController.h"

#define kConfigurationKey_Identifier	@"identifier" //NSString
#define kConfigurationKey_Exclusive		@"exclusive" //NSNumber - BOOL
#define kConfigurationKey_AutoReset		@"autoreset" //NSNumber - BOOL
#define kConfigurationKey_Script		@"script" //NSString
#define kConfigurationKey_EnableMIDI	@"enableMIDI" //NSNumber - BOOL
#define kConfigurationKey_EnableOSC		@"enableOSC" //NSNumber - BOOL

typedef enum {
	kBridgeControllerStatus_Disabled = 0,
	kBridgeControllerStatus_Offline,
	kBridgeControllerStatus_Idle,
	kBridgeControllerStatus_Active,
	kBridgeControllerStatusCount
} BridgeControllerStatus;

@class MidiController, OSCController;

/* Adds KVO compliance to "devicePath", "exclusive" and "enabled" */
@interface BridgeController : HIDController <HIDControllerDelegate>
{
@private
	NSString*					_name;
	BOOL						_autoreset;
	NSString*					_source;
	NSError*					_sourceError;
	void*						_luaState;
	pthread_mutex_t				_luaMutex;
	CFMutableDictionaryRef		_hashTable;
	BOOL						_midiEnabled;
	MidiController*				_midiController;
	unsigned char				_midiChannel;
	BOOL						_oscEnabled;
	OSCController*				_oscController;
	NSString*					_oscAddress;
	unsigned short				_oscPort;
	CFRunLoopTimerRef			_updateTimer;
	NSTimeInterval				_updateDelay;
	BridgeControllerStatus		_status;
}
- (id) initWithMidiEnabled:(BOOL)midiEnabled oscEnabled:(BOOL)oscEnabled;
- (BOOL) isMidiEnabled;
- (BOOL) isOSCEnabled;

- (id) initWithConfiguration:(NSDictionary*)configuration;
- (NSDictionary*) saveConfiguration;

- (id) initWithFile:(NSString*)path;
- (BOOL) writeToFile:(NSString*)path;

- (void) setName:(NSString*)name;
- (NSString*) name; //KVO compliant

- (void) setSource:(NSString*)source;
- (NSString*) source; //KVO compliant
- (NSError*) lastSourceError; //KVO compliant

- (void) setMidiChannel:(unsigned char)channel;
- (unsigned char) midiChannel; //KVO compliant

- (void) setOSCAddress:(NSString*)address;
- (NSString*) OSCAddress; //KVO compliant

- (void) setOSCPort:(unsigned short)port;
- (unsigned short) OSCPort; //KVO compliant

- (void) setAutoReset:(BOOL)flag;
- (BOOL) autoReset; //KVO compliant

- (BridgeControllerStatus) status; //KVO compliant

- (void) setActiveStatusDelay:(NSTimeInterval)delay;
- (NSTimeInterval) activeStatusDelay;

- (NSDictionary*) saveSettings;
- (void) loadSettings:(NSDictionary*)dictionary;

- (void) logMessage:(NSString*)message; //For subclasses (default implementation logs to console)
@end
