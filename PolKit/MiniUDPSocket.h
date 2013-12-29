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
#if TARGET_OS_IPHONE
#import <CFNetwork/CFNetwork.h>
#else
#import <CoreServices/CoreServices.h>
#endif
#import <sys/socket.h>

@interface MiniUDPSocket : NSObject
{
@private
	CFSocketRef					_socket;
	BOOL						_invalidating;
}
- (void) invalidate;
- (BOOL) isValid;

- (BOOL) broadcastData:(NSData*)data toPort:(UInt16)port; //Blocking
- (BOOL) sendData:(NSData*)data toRemoteAddress:(const struct sockaddr*)address; //Blocking
- (BOOL) sendData:(NSData*)data toRemoteIPv4Address:(UInt32)address port:(UInt16)port; //Blocking - The "address" is assumed to be in host-endian
@end
