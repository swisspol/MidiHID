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

@class MiniUDPSocket;

/*
http://opensoundcontrol.org/spec-1_0
*/
@interface OSCMessage : NSObject
{
@private
	NSString*					_address;
	NSMutableString*			_typeTags;
	NSMutableData*				_arguments;
}
+ (OSCMessage*) messageWithAddress:(NSString*)address arguments:(char)firstTag, ...; //Supports i(int), f(float), s(char*), b(NSData*) and @(id) - Terminate the list with a 0 tag

- (id) initWithAddress:(NSString*)address;

- (void) appendInt:(int)value;
- (void) appendFloat:(float)value;
- (void) appendString:(NSString*)string;
- (void) appendUTF8String:(const char*)string;
- (void) appendBlobData:(NSData*)data;
- (void) appendBlobBytes:(const void*)bytes length:(unsigned)length;
@end

@interface OSCController : NSObject
{
@private
	MiniUDPSocket*				_udpSocket;
	struct sockaddr*			_cachedAddress;
	NSString*					_address;
	unsigned short				_port;
}
- (void) setDestinationAddress:(NSString*)address;
- (NSString*) destinationAddress;

- (void) setDestinationPort:(unsigned short)port;
- (unsigned short) destinationPort;

- (void) sendMessage:(OSCMessage*)message;
@end
