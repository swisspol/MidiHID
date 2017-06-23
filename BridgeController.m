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

#import <pthread.h>

#import "BridgeController.h"
#import "MidiController.h"
#import "OSCController.h"
#import "lualib.h"
#import "lauxlib.h"

#define __USE_HID_THREAD__ 1

#define kLuaFunction_Event				"_event"
#define kLuaFunction_Connect			"_connect"
#define kLuaFunction_Disconnect			"_disconnect"

#define kUpdateTimerInterval			(24 * 3600) //seconds

@interface BridgeController ()
- (MidiController*) _midiController;
- (OSCController*) _oscController;
- (void) _didSendMessage;
- (void) _didConnect;
- (void) _didDisconnect;
- (void) _updateStatus:(NSNumber*)status;
- (void) _resetUpdateTimer;
@end

static inline void _SetUserInfo(lua_State* state, void* key, void* value)
{
	lua_pushlightuserdata(state, key);
	lua_pushlightuserdata(state, value);
	lua_settable(state, LUA_REGISTRYINDEX);
}

static inline const void* _GetUserInfo(lua_State* state, void* key)
{
	lua_pushlightuserdata(state, key);
	lua_gettable(state, LUA_REGISTRYINDEX);
	
	return lua_touserdata(state, -1);
}

static int _midiMessage(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	unsigned char			message = MIDI_CLAMP_VALUE_1(luaL_checkinteger(state, 1));
	lua_Integer				data1 = luaL_optinteger(state, 2, -1),
							data2 = luaL_optinteger(state, 3, -1);
	
	if(data1 >= 0) {
		if(data2 >= 0)
		[[controller _midiController] sendMessage:message data1:MIDI_CLAMP_VALUE_1(data1) data2:MIDI_CLAMP_VALUE_1(data2)];
		else
		[[controller _midiController] sendMessage:message data:MIDI_CLAMP_VALUE_1(data1)];
	}
	else
	[[controller _midiController] sendMessage:message];
	
	[controller _didSendMessage];
	
	return 0;
}

static int _midiNoteOn(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	unsigned char			key = MIDI_CLAMP_VALUE_1(luaL_checkinteger(state, 1)),
							velocity = MIDI_CLAMP_VALUE_1(luaL_optinteger(state, 2, kMidi_Max_1));
	
	[[controller _midiController] sendNoteOnEvent:key velocity:velocity];
	
	[controller _didSendMessage];
	
	return 0;
}

static int _midiNoteOff(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	unsigned char			key = MIDI_CLAMP_VALUE_1(luaL_checkinteger(state, 1)),
							velocity = MIDI_CLAMP_VALUE_1(luaL_optinteger(state, 2, kMidi_Max_1));
	
	[[controller _midiController] sendNoteOffEvent:key velocity:velocity];
	
	[controller _didSendMessage];
	
	return 0;
}

static int _midiControlChange(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	unsigned char			control = MIDI_CLAMP_VALUE_1(luaL_checkinteger(state, 1)),
							value = MIDI_CLAMP_VALUE_1(luaL_checkinteger(state, 2));
	
	[[controller _midiController] sendControlChange:control value:value];
	
	[controller _didSendMessage];
	
	return 0;
}

static int _midiPitchWheelChange(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	unsigned short			value = MIDI_CLAMP_VALUE_2(luaL_checkinteger(state, 1));
	
	[[controller _midiController] sendPitchWheelChange:value];
	
	[controller _didSendMessage];
	
	return 0;
}

static const struct luaL_reg _midiLib[] = {
	{"message", _midiMessage},
	{"noteon", _midiNoteOn},
	{"noteoff", _midiNoteOff},
	{"controlchange", _midiControlChange},
	{"pitchwheelchange", _midiPitchWheelChange},
	{NULL, NULL}
};

static int _oscMessage(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	const char*				address = luaL_checkstring(state, 1);
	OSCMessage*				message;
	int						index;
	
	if(address) {
		message = [[OSCMessage alloc] initWithAddress:[NSString stringWithUTF8String:address]];
		for(index = 1 - lua_gettop(state); index < -1; ++index) {
			switch(lua_type(state, index)) {
				
				case LUA_TNUMBER:
				[message appendFloat:lua_tonumber(state, index)];
				break;
				
				case LUA_TSTRING:
				[message appendUTF8String:lua_tolstring(state, index, NULL)];
				break;
				
				default:
				luaL_argerror(state, lua_gettop(state) + index + 1, "unsupported lua type");
				break;
				
			}
		}
		
		[[controller _oscController] sendMessage:message];
		[message release];
		
		[controller _didSendMessage];
	}
	
	return 0;
}

static const struct luaL_reg _oscLib[] = {
	{"message", _oscMessage},
	{NULL, NULL}
};

static int _log(lua_State* state)
{
	BridgeController*		controller = (BridgeController*)_GetUserInfo(state, [BridgeController class]);
	NSMutableString*		string = [NSMutableString string];
	int						n = lua_gettop(state),
							i;
	const char*				s;
	
	lua_getglobal(state, "tostring");
	for(i = 1; i <= n - 1; i++) {
		lua_pushvalue(state, -1);
		lua_pushvalue(state, i);
		lua_call(state, 1, 1);
		s = lua_tostring(state, -1);
		if(s == NULL)
		return luaL_error(state, LUA_QL("tostring") " must return a string to " LUA_QL("log"));
		//if(i > 1)
		//[string appendString:@"\t"];
		[string appendFormat:@"%s", s];
		lua_pop(state, 1);
	}
	
	[controller logMessage:string];
	
	return 0;
}

@implementation BridgeController

+ (void) initialize
{
	[super initialize];
	
	if(self == [BridgeController class]) {
		if([[NSUserDefaults standardUserDefaults] boolForKey:@"debug"])
		NSLog(@"\n%@", [HIDController allDevices]);
	}
}

#if __USE_HID_THREAD__

+ (BOOL) useHIDThread
{
	return YES;
}

#endif

+ (BOOL) automaticallyNotifiesObserversForKey:(NSString*)key
{
	return NO;
}

- (id) init
{
	return [self initWithMidiEnabled:NO oscEnabled:NO];
}

- (id) initWithMidiEnabled:(BOOL)midiEnabled oscEnabled:(BOOL)oscEnabled
{
	if((self = [super init])) {
		_midiEnabled = midiEnabled;
		_oscEnabled = oscEnabled;
		_hashTable = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
		_midiChannel = 0;
		_oscAddress = nil;
		_oscPort = 10000;
		
		[self setDelegate:self];
	}
	
	return self;
}

- (id) initWithConfiguration:(NSDictionary*)configuration
{
	if((self = [self initWithMidiEnabled:[[configuration objectForKey:kConfigurationKey_EnableMIDI] boolValue] oscEnabled:[[configuration objectForKey:kConfigurationKey_EnableOSC] boolValue]])) {
		[self setDevicePath:[configuration objectForKey:kConfigurationKey_Identifier]];
		[self setExclusive:[[configuration objectForKey:kConfigurationKey_Exclusive] boolValue]];
		
		[self setAutoReset:[[configuration objectForKey:kConfigurationKey_AutoReset] boolValue]];
		[self setSource:[configuration objectForKey:kConfigurationKey_Script]];
	}
	
	return self;
}

- (id) initWithFile:(NSString*)path
{
	id						result;
	
	if((result = [NSData dataWithContentsOfFile:path]))
	result = [NSPropertyListSerialization propertyListFromData:result mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
	if(result == nil) {
		[self release];
		return nil;
	}
	
	if((self = [self initWithConfiguration:result]))
	[self setName:[[path lastPathComponent] stringByDeletingPathExtension]];
	
	return self;
}

- (void) dealloc
{
	if(_updateTimer) {
		CFRunLoopTimerInvalidate(_updateTimer);
		CFRelease(_updateTimer);
	}
	
	if([self isConnected])
	[self _didDisconnect];
	
	[self setDelegate:nil];
	
	if(_hashTable)
	CFRelease(_hashTable);
	if(_luaState)
	lua_close(_luaState);
	
	[_sourceError release];
	[_source release];
	[_oscAddress release];
	[_name release];
	
	pthread_mutex_destroy(&_luaMutex);
	
	[super dealloc];
}

- (NSDictionary*) saveConfiguration
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	
	if([self isMidiEnabled])
	[dictionary setValue:[NSNumber numberWithBool:YES] forKey:kConfigurationKey_EnableMIDI];
	if([self isOSCEnabled])
	[dictionary setValue:[NSNumber numberWithBool:YES] forKey:kConfigurationKey_EnableOSC];
	
	[dictionary setValue:[self devicePath] forKey:kConfigurationKey_Identifier];
	[dictionary setValue:[NSNumber numberWithBool:[self isExclusive]] forKey:kConfigurationKey_Exclusive];
	[dictionary setValue:[NSNumber numberWithBool:[self autoReset]] forKey:kConfigurationKey_AutoReset];
	[dictionary setValue:[self source] forKey:kConfigurationKey_Script];
	
	return dictionary;
}

- (BOOL) writeToFile:(NSString*)path
{
	id						result;
	
	result = [self saveConfiguration];
	if(result)
	result = [NSPropertyListSerialization dataFromPropertyList:result format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
	
	return [result writeToFile:path atomically:YES];
}

static inline NSString* _CapitalizedString(NSString* string)
{
	NSRange					range;
	
	range = [string rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]];
	if((range.location != NSNotFound) && (range.location > 0))
	string = [string substringFromIndex:range.location];
	
	range = [string rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if(range.location != NSNotFound)
	string = [[[string substringToIndex:range.location] capitalizedString] stringByAppendingString:[string substringFromIndex:range.location]];
	else
	string = [string capitalizedString];
	
	return string;
}

- (void) setSource:(NSString*)source
{
	NSString*				error;
	NSArray*				array;
	
	if((source && !_source) || (!source && _source) || (source && _source && ![source isEqualToString:_source])) {
		[self willChangeValueForKey:@"source"];
		[_source release];
		_source = [source copy];
		[self didChangeValueForKey:@"source"];
		
		pthread_mutex_lock(&_luaMutex);
		if(_luaState)
		lua_close(_luaState);
		_luaState = lua_open();
		if(_luaState != NULL) {
			luaopen_base(_luaState);
			luaopen_string(_luaState);
			luaopen_table(_luaState);
			luaopen_math(_luaState);
			
			lua_pushcfunction(_luaState, _log);
			lua_setglobal(_luaState, "log");
			
			if(_midiEnabled)
			luaL_openlib(_luaState, "midi", _midiLib, 0);
			if(_oscEnabled)
			luaL_openlib(_luaState, "osc", _oscLib, 0);
			
			_SetUserInfo(_luaState, [BridgeController class], self);
			
			if(luaL_loadstring(_luaState, [source UTF8String])) {
				error = [NSString stringWithUTF8String:lua_tostring(_luaState, -1)];
				lua_pop(_luaState, 1);
				lua_close(_luaState);
				_luaState = NULL;
			}
			else if(lua_pcall(_luaState, 0, 0, 0)) {
				error = [NSString stringWithUTF8String:lua_tostring(_luaState, -1)];
				lua_pop(_luaState, 1);
				lua_close(_luaState);
				_luaState = NULL;
			}
			else
			error = nil;
			
			[self willChangeValueForKey:@"lastSourceError"];
			if(error) {
				array = [error componentsSeparatedByString:@":"];
				_sourceError = [[NSError errorWithDomain:@"LuaErrorDomain" code:[[array objectAtIndex:1] intValue] userInfo:[NSDictionary dictionaryWithObject:_CapitalizedString([array objectAtIndex:2]) forKey:NSLocalizedDescriptionKey]] retain];
			}
			else {
				[_sourceError release];
				_sourceError = nil;
			}
			[self didChangeValueForKey:@"lastSourceError"];
		}
		pthread_mutex_unlock(&_luaMutex);
	}
}

- (NSString*) source
{
	return _source;
}

- (NSError*) lastSourceError
{
	return _sourceError;
}

- (void) setMidiChannel:(unsigned char)channel
{
	[self willChangeValueForKey:@"midiChannel"];
	_midiChannel = channel;
	[_midiController setChannel:_midiChannel];
	[self didChangeValueForKey:@"midiChannel"];
}

- (unsigned char) midiChannel
{
	return _midiChannel;
}

- (void) setOSCAddress:(NSString*)address
{
	if(address != _oscAddress) {
		[self willChangeValueForKey:@"OSCAddress"];
		[_oscAddress release];
		_oscAddress = [address copy];
		[_oscController setDestinationAddress:_oscAddress];
		[self didChangeValueForKey:@"OSCAddress"];
	}
}

- (NSString*) OSCAddress
{
	return _oscAddress;
}

- (void) setOSCPort:(unsigned short)port
{
	[self willChangeValueForKey:@"OSCPort"];
	_oscPort = port;
	[_oscController setDestinationPort:_oscPort];
	[self didChangeValueForKey:@"OSCPort"];
}

- (unsigned short) OSCPort
{
	return _oscPort;
}

- (void) setAutoReset:(BOOL)flag
{
	if(flag != _autoreset) {
		[self willChangeValueForKey:@"autoReset"];
		_autoreset = flag;
		[self didChangeValueForKey:@"autoReset"];
	}
}

- (BOOL) autoReset
{
	return _autoreset;
}

- (void) setName:(NSString*)name
{
	if(name != _name) {
		[self willChangeValueForKey:@"name"];
		[_name release];
		_name = [name copy];
		[self didChangeValueForKey:@"name"];
	}
}

- (NSString*) name
{
	return _name;
}

- (BOOL) isMidiEnabled
{
	return _midiEnabled;
}

- (BOOL) isOSCEnabled
{
	return _oscEnabled;
}

static void _TimerCallBack(CFRunLoopTimerRef timer, void* info)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	
	if([(BridgeController*)info isConnected])
	[(BridgeController*)info _updateStatus:[NSNumber numberWithInt:kBridgeControllerStatus_Idle]];
	
	[pool release];
}

- (void) _resetUpdateTimer
{
	CFRunLoopTimerContext	context = {0, self, NULL, NULL, NULL};
	
	if([self isConnected] && (_updateDelay > 0.0)) {
		if(_updateTimer == NULL) {
			_updateTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + kUpdateTimerInterval, kUpdateTimerInterval, 0, 0, _TimerCallBack, &context);
			CFRunLoopAddTimer(CFRunLoopGetCurrent(), _updateTimer, kCFRunLoopCommonModes);
#ifdef __DEBUG__
			NSLog(@"%@ Created timer", self);
#endif
		}
	}
	else {
		if(_updateTimer) {
			CFRunLoopTimerInvalidate(_updateTimer);
			CFRelease(_updateTimer);
			_updateTimer = NULL;
#ifdef __DEBUG__
			NSLog(@"%@ Destroyed timer", self);
#endif
		}
	}
}

- (void) setActiveStatusDelay:(NSTimeInterval)delay
{
	_updateDelay = delay;
	
	[self _resetUpdateTimer];
}

- (NSTimeInterval) activeStatusDelay
{
	return _updateDelay;
}

- (void) _updateStatus:(NSNumber*)status
{
	BridgeControllerStatus	newStatus = [status intValue];
	
	if(newStatus != _status) {
		[self willChangeValueForKey:@"status"];
		_status = [status intValue];
		[self didChangeValueForKey:@"status"];
	}
	
	if(_updateTimer && (_status == kBridgeControllerStatus_Active))
	CFRunLoopTimerSetNextFireDate(_updateTimer, CFAbsoluteTimeGetCurrent() + _updateDelay);
}

- (BridgeControllerStatus) status
{
	return _status;
}

- (NSDictionary*) saveSettings
{
	NSMutableDictionary*		dictionary = [NSMutableDictionary new];
	
	[dictionary setObject:[NSNumber numberWithBool:[self isEnabled]] forKey:@"enabled"];
	if(_midiEnabled)
	[dictionary setObject:[NSNumber numberWithUnsignedChar:_midiChannel] forKey:@"midiChannel"];
	if(_oscEnabled) {
		[dictionary setValue:_oscAddress forKey:@"oscAddress"];
		[dictionary setObject:[NSNumber numberWithUnsignedShort:_oscPort] forKey:@"oscPort"];
	}
	
	return [dictionary autorelease];
}

- (void) loadSettings:(NSDictionary*)dictionary
{
	[self setEnabled:[[dictionary objectForKey:@"enabled"] boolValue]];
	if(_midiEnabled)
	[self setMidiChannel:[[dictionary objectForKey:@"midiChannel"] unsignedCharValue]];
	if(_oscEnabled) {
		[self setOSCAddress:[dictionary objectForKey:@"oscAddress"]];
		[self setOSCPort:[[dictionary objectForKey:@"oscPort"] unsignedShortValue]];
	}
}

- (void) logMessage:(NSString*)message
{
	NSLog(@"Lua message:\n%@", message);
}

- (MidiController*) _midiController
{
	return _midiController;
}

- (OSCController*) _oscController
{
	return _oscController;
}

/* Override */
- (void) setDeviceVendorID:(unsigned short)vendorID productID:(unsigned short)productID primaryUsagePage:(unsigned short)primaryUsagePage primaryUsage:(unsigned short)primaryUsage
{
	[self willChangeValueForKey:@"devicePath"];
	[super setDeviceVendorID:vendorID productID:productID primaryUsagePage:primaryUsagePage primaryUsage:primaryUsage];
	[self didChangeValueForKey:@"devicePath"];
}

/* Override */
- (void) setDevicePath:(NSString*)path
{
	[self willChangeValueForKey:@"devicePath"];
	[super setDevicePath:path];
	[self didChangeValueForKey:@"devicePath"];
}

/* Override */
- (void) setExclusive:(BOOL)flag
{
	[self willChangeValueForKey:@"exclusive"];
	[super setExclusive:flag];
	[self didChangeValueForKey:@"exclusive"];
}

/* Override */
- (void) setEnabled:(BOOL)flag
{
	[self willChangeValueForKey:@"enabled"];
	[super setEnabled:flag];
	[self didChangeValueForKey:@"enabled"];
	
	if([self isEnabled])
	[self _updateStatus:[NSNumber numberWithInt:([self isConnected] ? kBridgeControllerStatus_Idle : kBridgeControllerStatus_Offline)]];
	else
	[self _updateStatus:[NSNumber numberWithInt:kBridgeControllerStatus_Disabled]];
}

- (void) _didConnect
{
	NSEnumerator*			enumerator;
	NSDictionary*			elements;
	NSNumber*				cookie;
	SInt32					value,
							min,
							max;
							
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"debug"])
	NSLog(@"Connected device \"%@\":\n%@", [self devicePath], [self info]);
	
	if(_midiEnabled) {
		_midiController = [[MidiController alloc] initWithName:_name uniqueID:([self vendorID] << 16 | [self productID])];
		[_midiController setChannel:_midiChannel];
	}
	
	if(_oscEnabled) {
		_oscController = [OSCController new];
		[_oscController setDestinationAddress:_oscAddress];
		[_oscController setDestinationPort:_oscPort];
	}
	
	pthread_mutex_lock(&_luaMutex);
	if(_luaState) {
		lua_getglobal(_luaState, kLuaFunction_Connect);
		if(lua_isfunction(_luaState, -1)) {
			if(lua_pcall(_luaState, 0, 0, 0)) {
				[self logMessage:[NSString stringWithFormat:@"Execution of function %s() failed: %s", kLuaFunction_Connect, lua_tostring(_luaState, -1)]];
				lua_pop(_luaState, 1);
			}
		}
		else
		lua_pop(_luaState, 1);
	}
	pthread_mutex_unlock(&_luaMutex);
	
	[self _updateStatus:[NSNumber numberWithInt:kBridgeControllerStatus_Idle]];
	
	if(_autoreset) {
		elements = [self allElements];
		enumerator = [elements keyEnumerator];
		while((cookie = [enumerator nextObject])) {
			if([self fetchElementWithCookie:[cookie unsignedLongValue] value:&value min:&min max:&max])
			[self didUpdateElementWithCookie:[cookie unsignedLongValue] value:value min:min max:max info:[elements objectForKey:cookie]];
		}
	}
	
	[self _resetUpdateTimer];
}

- (void) _didDisconnect
{
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"debug"])
	NSLog(@"Disconnected device \"%@\"", [self devicePath]);
	
	[self _resetUpdateTimer];
	
	pthread_mutex_lock(&_luaMutex);
	if(_luaState) {
		lua_getglobal(_luaState, kLuaFunction_Disconnect);
		if(lua_isfunction(_luaState, -1)) {
			if(lua_pcall(_luaState, 0, 0, 0)) {
				[self logMessage:[NSString stringWithFormat:@"Execution of function %s() failed: %s", kLuaFunction_Disconnect, lua_tostring(_luaState, -1)]];
				lua_pop(_luaState, 1);
			}
		}
		else
		lua_pop(_luaState, 1);
	}
	pthread_mutex_unlock(&_luaMutex);
	
	if(_midiEnabled) {
		[_midiController release];
		_midiController = nil;
	}
	
	if(_oscEnabled) {
		[_oscController release];
		_oscController = nil;
	}
	
	[self _updateStatus:[NSNumber numberWithInt:kBridgeControllerStatus_Offline]];
}

- (void) HIDControllerDidConnect:(HIDController*)controller
{
	NSDictionary*			elements = [self allElements];
	NSEnumerator*			enumerator = [elements keyEnumerator];
	NSNumber*				cookie;
	NSString*				name;
	const char*				string;
	
	CFDictionaryRemoveAllValues(_hashTable);
	while((cookie = [enumerator nextObject])) {
		name = [[elements objectForKey:cookie] objectForKey:@"Name"];
		if(name == nil) {
			name = [[elements objectForKey:cookie] objectForKey:@"Usage"];
			if([name isKindOfClass:[NSNumber class]])
			name = [NSString stringWithFormat:@"_%04X", [(NSNumber*)name unsignedShortValue]];
		}
		if(name == nil)
		continue;
		
		name = [NSMutableString stringWithString:name];
		[(NSMutableString*)name replaceOccurrencesOfString:@" " withString:@"_" options:0 range:NSMakeRange(0, [name length])];
		
		string = [name UTF8String];
		CFDictionarySetValue(_hashTable, (void*)[cookie unsignedLongValue], [NSData dataWithBytes:string length:(strlen(string) + 1)]);
	}
	
	[self _didConnect];
}

- (void) HIDControllerDidDisconnect:(HIDController*)controller
{
	[self _didDisconnect];
}

- (void) HIDController:(HIDController*)controller didUpdateElementWithCookie:(unsigned long)cookie value:(SInt32)value min:(SInt32)min max:(SInt32)max info:(NSDictionary*)info
{
	[self doesNotRecognizeSelector:_cmd];
}

/* Override completely */
- (void) didUpdateElementWithCookie:(unsigned long)cookie value:(SInt32)value min:(SInt32)min max:(SInt32)max info:(NSDictionary*)info
{
	NSData*					data;
	
	pthread_mutex_lock(&_luaMutex);
	if(_luaState) {
		data = (NSData*)CFDictionaryGetValue(_hashTable, (void*)cookie);
		if(data) {
			lua_getglobal(_luaState, [data bytes]);
			if(lua_isfunction(_luaState, -1)) {
				lua_pushinteger(_luaState, value);
				lua_pushinteger(_luaState, min);
				lua_pushinteger(_luaState, max);
				if(lua_pcall(_luaState, 3, 0, 0)) {
					[self logMessage:[NSString stringWithFormat:@"Execution of function %s() failed: %s", [data bytes], lua_tostring(_luaState, -1)]];
					lua_pop(_luaState, 1);
				}
				return;
			}
			else
			lua_pop(_luaState, 1);
		}
		
		lua_getglobal(_luaState, kLuaFunction_Event);
		if(lua_isfunction(_luaState, -1)) {
			if(data)
			lua_pushstring(_luaState, [data bytes]);
			else
			lua_pushnil(_luaState);
			lua_pushinteger(_luaState, value);
			lua_pushinteger(_luaState, min);
			lua_pushinteger(_luaState, max);
			if(lua_pcall(_luaState, 4, 0, 0)) {
				[self logMessage:[NSString stringWithFormat:@"Execution of function %s() failed: %s", kLuaFunction_Event, lua_tostring(_luaState, -1)]];
				lua_pop(_luaState, 1);
			}
		}
		else
		lua_pop(_luaState, 1);
	}
	pthread_mutex_unlock(&_luaMutex);
}

- (void) _didSendMessage
{
#if __USE_HID_THREAD__
	[self performSelectorOnMainThread:@selector(_updateStatus:) withObject:[NSNumber numberWithInt:kBridgeControllerStatus_Active] waitUntilDone:NO];
#else
	[self _updateStatus:[NSNumber numberWithInt:kBridgeControllerStatus_Active]];
#endif
}

@end
