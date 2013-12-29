/*
	This file is part of the PolKit library.
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

#import <CoreMIDI/CoreMIDI.h>

#import "MidiController.h"

@interface MidiController ()
- (void) _sendPackets:(const MIDIPacketList*)packetList;
@end

static MIDIClientRef				_midiClient;
static CFMutableSetRef				_instanceList;

@implementation MidiController

+ (void) initialize
{
	if(_instanceList == NULL)
	_instanceList = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
}

- (id) init
{
	return [self initWithName:nil uniqueID:0];
}

- (id) initWithName:(NSString*)name uniqueID:(UInt32)uniqueID
{
	OSStatus				error;
	NSString*				string;
	
	if((CFSetGetCount(_instanceList) == 0) && (_midiClient == 0)) {
		string = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
		if(string == nil)
		string = [[NSClassFromString(@"NSProcessInfo") processInfo] processName];
		error = MIDIClientCreate((CFStringRef)string, NULL, NULL, (MIDIClientRef*)&_midiClient);
		if(error != noErr) {
			NSLog(@"%s: MIDIClientCreate() failed with error %i", __FUNCTION__, error);
			[self release];
			return nil;
		}
	}
	CFSetAddValue(_instanceList, self);
	
	if((self = [super init])) {
		_name = [name copy];
		_channel = 0;
		
		error = MIDISourceCreate(_midiClient, (CFStringRef)_name, (MIDIEndpointRef*)&_midiEndPoint);
		if(error != noErr) {
			NSLog(@"%s: MIDISourceCreate() failed with error %i", __FUNCTION__, error);
			[self release];
			return nil;
		}
		
		if(uniqueID) {
			error = MIDIObjectSetIntegerProperty(_midiEndPoint, kMIDIPropertyUniqueID, uniqueID);
			if(error != noErr)
			NSLog(@"%s: MIDIObjectSetIntegerProperty() failed with error %i", __FUNCTION__, error);
		}
	}
	
	return self;
}

- (void) _cleanUp_MidiController
{
	if(_midiEndPoint)
	MIDIEndpointDispose(_midiEndPoint);
	
	CFSetRemoveValue(_instanceList, self);
	if((CFSetGetCount(_instanceList) == 0) && (_midiClient != 0)) {
		MIDIClientDispose(_midiClient);
		_midiClient = 0;
	}
}

- (void) finalize
{
	[self _cleanUp_MidiController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_MidiController];
	
	[_name release];
	
	[super dealloc];
}

- (NSString*) name
{
	return _name;
}

- (void) setChannel:(unsigned char)channel
{
	_channel = channel % 16;
}

- (unsigned char) channel
{
	return _channel;
}

- (void) _sendPackets:(const MIDIPacketList*)packetList
{
	OSStatus						error;
	
	error = MIDIReceived(_midiEndPoint, packetList);
	if(error != noErr)
	NSLog(@"%s: MIDIReceived() failed with error %i", __FUNCTION__, error);
}

- (void) sendMessage:(unsigned char)message
{
	MIDIPacketList					packetList;
	
	packetList.numPackets = 1;
	packetList.packet[0].length = 1;
	packetList.packet[0].data[0] = ((message & 0x0F) << 4) | (_channel & 0x0F);
	packetList.packet[0].timeStamp = 0;
	
	[self _sendPackets:&packetList];
}

- (void) sendMessage:(unsigned char)message data:(unsigned char)data
{
	MIDIPacketList					packetList;
	
	packetList.numPackets = 1;
	packetList.packet[0].length = 2;
	packetList.packet[0].data[0] = ((message & 0x0F) << 4) | (_channel & 0x0F);
	packetList.packet[0].data[1] = data & 0x7F;
	packetList.packet[0].timeStamp = 0;
	
	[self _sendPackets:&packetList];
}

- (void) sendMessage:(unsigned char)message data1:(unsigned char)data1 data2:(unsigned char)data2
{
	MIDIPacketList					packetList;
	
	packetList.numPackets = 1;
	packetList.packet[0].length = 3;
	packetList.packet[0].data[0] = ((message & 0x0F) << 4) | (_channel & 0x0F);
	packetList.packet[0].data[1] = data1 & 0x7F;
	packetList.packet[0].data[2] = data2 & 0x7F;
	packetList.packet[0].timeStamp = 0;
	
	[self _sendPackets:&packetList];
}

- (void) sendNoteOnEvent:(unsigned char)key velocity:(unsigned char)velocity
{
	[self sendMessage:0x09 data1:key data2:velocity];
}

- (void) sendNoteOffEvent:(unsigned char)key velocity:(unsigned char)velocity
{
	[self sendMessage:0x08 data1:key data2:velocity];
}

- (void) sendControlChange:(unsigned char)controller value:(unsigned char)value
{
	[self sendMessage:0x0B data1:controller data2:value];
}

- (void) sendPitchWheelChange:(unsigned short)value
{
	[self sendMessage:0x0E data1:(value & 0x7F) data2:((value >> 7) & 0x7F)]; //NOTE: 0x2000 is the middle value
}

@end
