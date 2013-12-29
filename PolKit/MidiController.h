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

#import <Foundation/Foundation.h>

#define kMidi_Min_1				0
#define kMidi_Max_1				127 //7bits
#define kMidi_Min_2				0
#define kMidi_Max_2				16383 //14bits

#define MIDI_CLAMP_VALUE_1(_VALUE_) MAX(MIN(_VALUE_, kMidi_Max_1), kMidi_Min_1)
#define MIDI_CLAMP_VALUE_2(_VALUE_) MAX(MIN(_VALUE_, kMidi_Max_2), kMidi_Min_2)

@interface MidiController : NSObject
{
@private
	NSString*					_name;
#if __LP64__
	UInt32						_midiEndPoint;
#else
	void*						_midiEndPoint;
#endif
	unsigned char				_channel;
}
- (id) initWithName:(NSString*)name uniqueID:(UInt32)uniqueID; //uniqueID is ignored if 0
- (NSString*) name;

- (void) setChannel:(unsigned char)channel;
- (unsigned char) channel;

- (void) sendMessage:(unsigned char)message;
- (void) sendMessage:(unsigned char)message data:(unsigned char)data;
- (void) sendMessage:(unsigned char)message data1:(unsigned char)data1 data2:(unsigned char)data2;

- (void) sendNoteOnEvent:(unsigned char)key velocity:(unsigned char)velocity;
- (void) sendNoteOffEvent:(unsigned char)key velocity:(unsigned char)velocity;
- (void) sendControlChange:(unsigned char)controller value:(unsigned char)value;
- (void) sendPitchWheelChange:(unsigned short)value;
@end
