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

#import "MiniUDPSocket.h"

@implementation MiniUDPSocket

- (id) init
{
	int					value = 1;
	
	if((self = [super init])) {
		_socket = CFSocketCreate(kCFAllocatorDefault, AF_INET, SOCK_DGRAM, IPPROTO_IP, kCFSocketNoCallBack, NULL, NULL);
		if(_socket == NULL) {
			[self release];
			return nil;
		}
		
		if(setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_BROADCAST, &value, sizeof(value)) < 0) {
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) finalize
{
	[self invalidate];
	
	[super finalize];
}

- (void) dealloc
{
	[self invalidate];
	
	[super dealloc];
}

- (BOOL) isValid
{
	return !_invalidating;
}

- (void) invalidate
{
	if(_invalidating == NO) {
		_invalidating = YES;
		
		if(_socket) {
			CFSocketInvalidate(_socket); //NOTE: This also calls CFRunLoopSourceInvalidate()
			CFRelease(_socket);
			_socket = NULL;
		}
	}
}

- (BOOL) broadcastData:(NSData*)data toPort:(UInt16)port
{
	return [self sendData:data toRemoteIPv4Address:INADDR_BROADCAST port:port];
}

- (BOOL) sendData:(NSData*)data toRemoteAddress:(const struct sockaddr*)address
{
	return (address && data && (CFSocketSendData(_socket, (CFDataRef)[NSData dataWithBytes:(void*)address length:address->sa_len], (CFDataRef)data, 0.0) == kCFSocketSuccess) ? YES : NO);
}

- (BOOL) sendData:(NSData*)data toRemoteIPv4Address:(UInt32)address port:(UInt16)port
{
	struct sockaddr_in		ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin_len = sizeof(ipAddress);
	ipAddress.sin_family = AF_INET;
	ipAddress.sin_port = htons(port);
	ipAddress.sin_addr.s_addr = htonl(address);
	
	return [self sendData:data toRemoteAddress:(struct sockaddr*)&ipAddress];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08X | valid = %i>", [self class], (long)self, [self isValid]];
}

@end
