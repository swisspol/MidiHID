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

#import <netinet/in.h>

#import "OSCController.h"
#import "MiniUDPSocket.h"

@interface OSCMessage ()
- (NSData*) serializedData;
@end

@interface NSMutableData (OSCController)
- (void) _appendPaddedBytes:(const void*)bytes length:(unsigned)length;
@end

@implementation NSMutableData (OSCController)

- (void) _appendPaddedBytes:(const void*)bytes length:(unsigned)length
{
	uint32_t					zero = 0;
	
	[self appendBytes:bytes length:length];
	if(length % 4)
	[self appendBytes:&zero length:(4 - length % 4)];
}

@end

@implementation OSCMessage

+ (OSCMessage*) messageWithAddress:(NSString*)address arguments:(char)firstTag, ...
{
	OSCMessage*					message = [[OSCMessage alloc] initWithAddress:address];
	va_list						list;
	
	va_start(list, firstTag);
	while(firstTag) {
		switch(firstTag) {
			
			case 'i':
			[message appendInt:va_arg(list, int)];
			break;

			case 'f':
			[message appendFloat:va_arg(list, double)];
			break;
			
			case 's':
			[message appendUTF8String:va_arg(list, char*)];
			break;
			
			case 'b':
			[message appendBlobData:va_arg(list, NSData*)];
			break;
			
			case '@':
			[message appendString:[va_arg(list, id) description]];
			break;
			
			default:
			[NSException raise:NSInternalInconsistencyException format:@"Unsupported OSC type '%c'", firstTag];
			break;
			
		}
		firstTag = va_arg(list, int);
	}
	va_end(list);
	
	return [message autorelease];
}

- (id) initWithAddress:(NSString*)address
{
	if(![address hasPrefix:@"/"]) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_address = [address copy];
		_typeTags = [[NSMutableString alloc] initWithString:@","];
		_arguments = [NSMutableData new];
	}
	
	return self;
}

- (void) dealloc
{
	[_arguments release];
	[_typeTags release];
	[_address release];
	
	[super dealloc];
}

- (void) appendInt:(int)value
{
	uint32_t					intValue = value;
	
	[_typeTags appendString:@"i"];
	intValue = CFSwapInt32HostToBig(intValue);
	[_arguments appendBytes:&intValue length:4];
}

- (void) appendFloat:(float)value
{
	uint32_t					intValue = *((uint32_t*)&value);
	
	[_typeTags appendString:@"f"];
	intValue = CFSwapInt32HostToBig(intValue);
	[_arguments appendBytes:&intValue length:4];
}

- (void) appendString:(NSString*)string
{
	[self appendUTF8String:[string UTF8String]];
}

- (void) appendUTF8String:(const char*)string
{
	[_typeTags appendString:@"s"];
	[_arguments _appendPaddedBytes:string length:(string ? strlen(string) + 1 : 0)];
}

- (void) appendBlobData:(NSData*)data
{
	[self appendBlobBytes:[data bytes] length:[data length]];
}

- (void) appendBlobBytes:(const void*)bytes length:(unsigned)length
{
	uint32_t					intValue = length;
	
	[_typeTags appendString:@"b"];
	intValue = CFSwapInt32HostToBig(intValue);
	[_arguments appendBytes:&intValue length:4];
	[_arguments _appendPaddedBytes:bytes length:length];
}

- (NSData*) serializedData
{
	NSMutableData*				data = [NSMutableData new];
	const char*					string;
	
	string = [_address UTF8String];
	[data _appendPaddedBytes:string length:(strlen(string) + 1)];
	string = [_typeTags UTF8String];
	[data _appendPaddedBytes:string length:(strlen(string) + 1)];
	[data appendData:_arguments];
	
	return [data autorelease];
}

@end

@implementation OSCController

- (id) init
{
	if((self = [super init])) {
		_address = nil;
		_port = 10000;
		
		_udpSocket = [MiniUDPSocket new];
		if(_udpSocket == nil) {
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) _cleanUp_OSCController
{
	[_udpSocket invalidate];
	
	if(_cachedAddress)
	free(_cachedAddress);
}

- (void) finalize
{
	[self _cleanUp_OSCController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_OSCController];
	
	[_udpSocket release];
	[_address release];
	
	[super dealloc];
}

- (void) setDestinationAddress:(NSString*)address
{
	CFHostRef					host;
	Boolean						resolved;
	NSArray*					array;
	NSUInteger					i;
	const struct sockaddr*		ipAddress;
	
	if(address != _address) {
		[_address release];
		_address = [address copy];
		
		if(_cachedAddress) {
			free(_cachedAddress);
			_cachedAddress = NULL;
		}
		if(_address) {
			if((host = CFHostCreateWithName(kCFAllocatorDefault, (CFStringRef)_address))) {
				if(CFHostStartInfoResolution(host, kCFHostAddresses, NULL) && ((array = (NSArray*)CFHostGetAddressing(host, &resolved)))) {
					for(i = 0; i < [array count]; ++i) {
						ipAddress = [[array objectAtIndex:i] bytes];
						if(ipAddress->sa_family == AF_INET) {
							_cachedAddress = malloc(ipAddress->sa_len);
							bcopy(ipAddress, _cachedAddress, ipAddress->sa_len);
#ifdef __DEBUG__
							NSLog(@"Resolved '%@' to '%i.%i.%i.%i'", _address, (((struct sockaddr_in*)_cachedAddress)->sin_addr.s_addr >> 0) & 0xFF, (((struct sockaddr_in*)_cachedAddress)->sin_addr.s_addr >> 8) & 0xFF, (((struct sockaddr_in*)_cachedAddress)->sin_addr.s_addr >> 16) & 0xFF, (((struct sockaddr_in*)_cachedAddress)->sin_addr.s_addr >> 24) & 0xFF);
#endif
							break;
						}
					}
				}
				CFRelease(host);
			}
			if(_cachedAddress == NULL)
			NSLog(@"%s: Failed resolving '%@'", __FUNCTION__, _address);
		}
	}
}

- (NSString*) destinationAddress
{
	return _address;
}

- (void) setDestinationPort:(unsigned short)port
{
	_port = port;
}

- (unsigned short) destinationPort
{
	return _port;
}

- (void) sendMessage:(OSCMessage*)message
{
	if(_address) {
		if(_cachedAddress)
		((struct sockaddr_in*)_cachedAddress)->sin_port = _port;
		if(![_udpSocket sendData:[message serializedData] toRemoteAddress:_cachedAddress])
		NSLog(@"%s: Failed sending UDP datagram to '%@'", __FUNCTION__, _address);
	}
	else {
		if(![_udpSocket broadcastData:[message serializedData] toPort:_port])
		NSLog(@"%s: Failed broadcasting UDP datagram", __FUNCTION__);
	}
}

@end
