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

#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/hid/IOHIDLib.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hid/IOHIDUsageTables.h>
#import <pthread.h>

#import "HIDController.h"

typedef struct {
	NSMutableDictionary*	info;
	SInt32					value,
							min,
							max;
	BOOL					isRelative;
} ElementInfo;

@interface HIDController ()
- (void) _reconnect;
- (void) _disconnect;
- (void) _processEvents;
@end

static pthread_mutex_t				_hidMutex = PTHREAD_MUTEX_INITIALIZER;
static IONotificationPortRef		_notificationPort;
static io_iterator_t				_notificationAdd;
static io_iterator_t				_notificationRemove;
static CFMutableSetRef				_instanceList;
static NSDictionary*				_usageTables;
static CFRunLoopRef					_hidRunLoop;
static pthread_cond_t				_hidCondition = PTHREAD_COND_INITIALIZER;

@implementation HIDController

static void _SetReconnectFunction(const void* value, void* context)
{
	[(HIDController*)value _reconnect];
}

static void _ServiceMatchingCallback(void* refcon, io_iterator_t iterator)
{
	NSAutoreleasePool*			pool = [NSAutoreleasePool new];
	
	while(IOIteratorNext(iterator))
	;
	
	CFSetApplyFunction(_instanceList, _SetReconnectFunction, NULL);
	
	[[NSNotificationCenter defaultCenter] postNotificationName:HIDControllerDidUpdateDevicesNotification object:nil];
	
	[pool drain];
}

+ (void) initialize
{
	if(_usageTables == nil)
	_usageTables = [[NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"UsageTables" ofType:@"plist"]] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL] retain];
	
	if(_instanceList == NULL)
	_instanceList = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
}

+ (BOOL) useHIDThread
{
	return NO;
}

+ (NSDictionary*) allDevices
{
	NSMutableDictionary*	deviceList = nil;
	io_iterator_t			iterator;
	CFMutableDictionaryRef	dictionary;
	io_object_t				hidDevice;
	NSMutableDictionary*	info;
	IOCFPlugInInterface**	plugInInterface;
	SInt32					score;
	CFArrayRef				elements;
	IOHIDDeviceInterface**	hidDeviceInterface;
	NSArray*				table;
	unsigned short			value;
	NSString*				string;
	kern_return_t			error;
	
	dictionary = IOServiceMatching(kIOHIDDeviceKey);
	error = IOServiceGetMatchingServices(kIOMasterPortDefault, dictionary, &iterator);
	if(error == kIOReturnSuccess) {
		deviceList = [NSMutableDictionary dictionary];
		while((hidDevice = IOIteratorNext(iterator))) {
			elements = NULL;
			error = IOCreatePlugInInterfaceForService(hidDevice, kIOHIDDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
			if(error == kIOReturnSuccess) {
				if((*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID), (LPVOID)&hidDeviceInterface) == S_OK) {
					if((*(IOHIDDeviceInterface122**)hidDeviceInterface)->copyMatchingElements(hidDeviceInterface, NULL, &elements) != kIOReturnSuccess)
					elements = NULL;
					(*hidDeviceInterface)->Release(hidDeviceInterface);
				}
				(*plugInInterface)->Release(plugInInterface);
			}
			else
			NSLog(@"%s: IOCreatePlugInInterfaceForService() failed with error %i", __FUNCTION__, error);
			
			if(elements && (IORegistryEntryCreateCFProperties(hidDevice, &dictionary, kCFAllocatorDefault, 0) == kIOReturnSuccess)) {
				info = [NSMutableDictionary new];
				[info setValue:[(NSDictionary*)dictionary objectForKey:@kIOHIDProductKey] forKey:@kIOHIDProductKey];
				[info setValue:[(NSDictionary*)dictionary objectForKey:@kIOHIDManufacturerKey] forKey:@kIOHIDManufacturerKey];
				table = [_usageTables objectForKey:@"0"];
				value = [[(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsagePageKey] unsignedShortValue];
				string = (value < [table count] ? [table objectAtIndex:value] : nil);
				[info setObject:([string length] ? string : [(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsagePageKey]) forKey:@kIOHIDPrimaryUsagePageKey];
				table = [_usageTables objectForKey:[NSString stringWithFormat:@"%i", value]];
				value = [[(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsageKey] unsignedShortValue];
				string = (value < [table count] ? [table objectAtIndex:value] : nil);
				[info setObject:([string length] ? string : [(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsageKey]) forKey:@kIOHIDPrimaryUsageKey];
				
				if([(NSDictionary*)dictionary objectForKey:@kIOHIDVendorIDKey] && [(NSDictionary*)dictionary objectForKey:@kIOHIDProductIDKey]) {
					string = [NSString stringWithFormat:@"%@%@%@%@%@%@%@", [(NSDictionary*)dictionary objectForKey:@kIOHIDVendorIDKey], kHIDPathSeparator, [(NSDictionary*)dictionary objectForKey:@kIOHIDProductIDKey], kHIDPathSeparator, [(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsagePageKey], kHIDPathSeparator, [(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsageKey]];
					if([deviceList objectForKey:string]) {
						if([[NSUserDefaults standardUserDefaults] boolForKey:@"debug"])
						NSLog(@"Found duplicate identifier '%@' for device \"%@\"", string, [(NSDictionary*)dictionary objectForKey:@kIOHIDProductKey]);
					}
					else
					[deviceList setObject:info forKey:string];
				}
				
				[info release];
				CFRelease(dictionary);
			}
			
			if(elements)
			CFRelease(elements);
			IOObjectRelease(hidDevice);
		}
		IOObjectRelease(iterator);
	}
	else
	NSLog(@"%s: IOServiceGetMatchingServices() failed with error %i", __FUNCTION__, error);
	
	return deviceList;
}

static void _TimerCallBack(CFRunLoopTimerRef timer, void* info)
{
	;
}

- (void) _hidThread:(id)arg
{
	CFRunLoopTimerRef			timer;
	
#ifdef __DEBUG__
	NSLog(@"<HID thread started>");
#endif

	_hidRunLoop = CFRunLoopGetCurrent();
	
	pthread_mutex_lock(&_hidMutex);
	pthread_cond_signal(&_hidCondition);
	pthread_mutex_unlock(&_hidMutex);
	
	timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 365 * 24 * 3600, 0.0, 0, 0, _TimerCallBack, NULL);
	CFRunLoopAddTimer(_hidRunLoop, timer, kCFRunLoopCommonModes);
	
	CFRunLoopRun();
	
	CFRunLoopTimerInvalidate(timer);
	CFRelease(timer);
	
#ifdef __DEBUG__
	NSLog(@"<HID thread terminated>");
#endif
}

- (id) init
{
	kern_return_t				error;
	
	if(CFSetGetCount(_instanceList) == 0) {
		if([[self class] useHIDThread] && (_hidRunLoop == NULL)) {
			pthread_mutex_lock(&_hidMutex);
			[NSThread detachNewThreadSelector:@selector(_hidThread:) toTarget:self withObject:nil];
			pthread_cond_wait(&_hidCondition, &_hidMutex);
			pthread_mutex_unlock(&_hidMutex);
		}
		
		if(_notificationPort == NULL) {
			_notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
			if(_notificationPort) {
				CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopCommonModes);
				
				error = IOServiceAddMatchingNotification(_notificationPort, kIOMatchedNotification, IOServiceMatching(kIOHIDDeviceKey), _ServiceMatchingCallback, NULL, &_notificationAdd);
				if(error != kIOReturnSuccess) {
					NSLog(@"%s: IOServiceAddMatchingNotification() failed with error %i", __FUNCTION__, error);
					_notificationAdd = IO_OBJECT_NULL;
				}
				else {
					while(IOIteratorNext(_notificationAdd))
					;
				}
				
				error = IOServiceAddMatchingNotification(_notificationPort, kIOTerminatedNotification, IOServiceMatching(kIOHIDDeviceKey), _ServiceMatchingCallback, NULL, &_notificationRemove);
				if(error != kIOReturnSuccess) {
					NSLog(@"%s: IOServiceAddMatchingNotification() failed with error %i", __FUNCTION__, error);
					_notificationRemove = IO_OBJECT_NULL;
				}
				else {
					while(IOIteratorNext(_notificationRemove))
					;
				}
			}
			else
			NSLog(@"%s: Failed creating IONotificationPort", __FUNCTION__);
		}
	}
	CFSetAddValue(_instanceList, self);
	
	if((self = [super init]))
	pthread_mutex_init(&_deviceMutex, NULL);
	
	return self;
}

- (void) _cleanUp_HIDController
{
	[self _disconnect];
	
	pthread_mutex_destroy(&_deviceMutex);
	
	CFSetRemoveValue(_instanceList, self);
	if(CFSetGetCount(_instanceList) == 0) {
		if(_notificationPort != NULL) {
			CFRunLoopRemoveSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopCommonModes);
			
			if(_notificationAdd)
			IOObjectRelease(_notificationAdd);
			if(_notificationRemove)
			IOObjectRelease(_notificationRemove);
			
			IONotificationPortDestroy(_notificationPort);
		}
		
		if(_hidRunLoop) {
			CFRunLoopStop(_hidRunLoop);
			_hidRunLoop = NULL;
		}
	}
}

- (void) finalize
{
	[self _cleanUp_HIDController];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_HIDController];
	
	[super dealloc];
}

- (id) initWithVendorID:(unsigned short)vendorID productID:(unsigned short)productID primaryUsagePage:(unsigned short)primaryUsagePage primaryUsage:(unsigned short)primaryUsage exclusive:(BOOL)exclusive
{
	if((self = [self init])) {
		[self setDeviceVendorID:vendorID productID:productID primaryUsagePage:primaryUsagePage primaryUsage:primaryUsage];
		[self setExclusive:exclusive];
	}
	
	return self;
}

- (id) initWithDevicePath:(NSString*)path exclusive:(BOOL)exclusive
{
	if((self = [self init])) {
		[self setDevicePath:path];
		[self setExclusive:exclusive];
	}
	
	return self;
}

- (void) setDeviceVendorID:(unsigned short)vendorID productID:(unsigned short)productID primaryUsagePage:(unsigned short)primaryUsagePage primaryUsage:(unsigned short)primaryUsage
{
	if((vendorID != _vendorID) || (productID != _productID) || (primaryUsagePage != _primaryUsagePage) || (primaryUsage != _primaryUsage)) {
		_vendorID = vendorID;
		_productID = productID;
		_primaryUsagePage = primaryUsagePage;
		_primaryUsage = primaryUsage;
		
		if(_enabled) {
			[self _disconnect];
			[self _reconnect];
		}
	}
}

- (unsigned short) vendorID
{
	return _vendorID;
}

- (unsigned short) productID
{
	return _productID;
}

- (unsigned short) primaryUsagePage
{
	return _primaryUsagePage;
}

- (unsigned short) primaryUsage
{
	return _primaryUsage;
}

- (void) setDevicePath:(NSString*)path
{
	NSArray*			components = [path componentsSeparatedByString:kHIDPathSeparator];
	unsigned short		vendorID = 0,
						productID = 0,
						primaryUsagePage = 0,
						primaryUsage = 0;
	
	if([components count] >= 1) {
		vendorID = [[components objectAtIndex:0] intValue];
		if([components count] >= 2) {
			productID = [[components objectAtIndex:1] intValue];
			if([components count] >= 3) {
				primaryUsagePage = [[components objectAtIndex:2] intValue];
				if([components count] >= 4)
				primaryUsage = [[components objectAtIndex:3] intValue];
			}
		}
	}
	
	[self setDeviceVendorID:vendorID productID:productID primaryUsagePage:primaryUsagePage primaryUsage:primaryUsage];
}

- (NSString*) devicePath
{
	NSMutableString*			string = [NSMutableString stringWithFormat:@"%i%@%i", _vendorID, kHIDPathSeparator, _productID];
	
	if(_primaryUsagePage) {
		[string appendFormat:@"%@%i", kHIDPathSeparator, _primaryUsagePage];
		if(_primaryUsage)
		[string appendFormat:@"%@%i", kHIDPathSeparator, _primaryUsage];
	}
	
	return string;
}

- (void) setExclusive:(BOOL)flag
{
	if(flag != _exclusive) {
		_exclusive = flag;
		
		if(_enabled) {
			[self _disconnect];
			[self _reconnect];
		}
	}
}

- (BOOL) isExclusive
{
	return _exclusive;
}

- (void) setDelegate:(id<HIDControllerDelegate>)delegate
{
	_delegate = delegate;
}

- (id<HIDControllerDelegate>) delegate
{
	return _delegate;
}

- (void) setEnabled:(BOOL)flag
{
	if(flag != _enabled) {
		_enabled = flag;
		
		if(_enabled)
		[self _reconnect];
		else
		[self _disconnect];
	}
}

- (BOOL) isEnabled
{
	return _enabled;
}

- (BOOL) isConnected
{
	return (_hidEventSource ? YES : NO);
}

static void _DictionaryPollFunction(const void* key, const void* value, void* context)
{
	ElementInfo*			info = (ElementInfo*)CFDataGetBytePtr(value);
	IOHIDDeviceInterface**	hidDeviceInterface = (IOHIDDeviceInterface**)context;
	IOHIDEventStruct		hidEvent;
	
	if((*hidDeviceInterface)->getElementValue(hidDeviceInterface, (IOHIDElementCookie)(long)key, &hidEvent) == kIOReturnSuccess) {
		info->value = hidEvent.value;
		
		if((hidEvent.longValueSize != 0) && (hidEvent.longValue != NULL))
		free(hidEvent.longValue);
	}
	else
	info->value = 0;
}

static void _QueueCallbackFunction(void* target, IOReturn result, void* refcon, void* sender)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	
	if(result == kIOReturnSuccess)
	[(HIDController*)refcon _processEvents];
	
	[pool drain];
}

- (void) _reconnect
{
	BOOL					wasConnected = [self isConnected],
							success = NO;
	CFMutableDictionaryRef	dictionary;
	io_iterator_t			iterator;
	io_object_t				hidDevice;
	IOCFPlugInInterface**	plugInInterface;
	SInt32					score;
	CFArrayRef				elements;
	CFIndex					i;
	CFDictionaryRef			element;
	IOHIDElementCookie		cookie;
	CFMutableDataRef		data;
	ElementInfo*			info;
	unsigned short			value;
	NSArray*				table;
	NSString*				string;
	kern_return_t			error;
	
	if(!_enabled)
	return;
	
	pthread_mutex_lock(&_deviceMutex);
	
	dictionary = IOServiceMatching(kIOHIDDeviceKey);
	error = IOServiceGetMatchingServices(kIOMasterPortDefault, dictionary, &iterator);
	if(error == kIOReturnSuccess) {
		while((hidDevice = IOIteratorNext(iterator)) && (success == NO)) {
			if(IORegistryEntryCreateCFProperties(hidDevice, &dictionary, kCFAllocatorDefault, 0) != kIOReturnSuccess)
			continue;
			
			if([(NSDictionary*)dictionary objectForKey:@kIOHIDVendorIDKey] && [(NSDictionary*)dictionary objectForKey:@kIOHIDProductIDKey] && ([[(NSDictionary*)dictionary objectForKey:@kIOHIDVendorIDKey] unsignedShortValue] == _vendorID) && ([[(NSDictionary*)dictionary objectForKey:@kIOHIDProductIDKey] unsignedShortValue] == _productID) && ((_primaryUsagePage == 0) || ([[(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsagePageKey] unsignedShortValue] == _primaryUsagePage)) && ((_primaryUsage == 0) || ([[(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsageKey] unsignedShortValue] == _primaryUsage))) {
				if(_hidEventSource == NULL) {
					error = IOCreatePlugInInterfaceForService(hidDevice, kIOHIDDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
					if(error == kIOReturnSuccess) {
						if((*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID), (LPVOID)&_hidDeviceInterface) == S_OK) {
							if((*(IOHIDDeviceInterface122**)_hidDeviceInterface)->copyMatchingElements((IOHIDDeviceInterface**)_hidDeviceInterface, NULL, &elements) == kIOReturnSuccess) {
								if((*(IOHIDDeviceInterface**)_hidDeviceInterface)->open((IOHIDDeviceInterface**)_hidDeviceInterface, (_exclusive ? kIOHIDOptionsTypeSeizeDevice : 0)) == kIOReturnSuccess) {
									_queueInterface = (*(IOHIDDeviceInterface**)_hidDeviceInterface)->allocQueue((IOHIDDeviceInterface**)_hidDeviceInterface);
									if((IOHIDQueueInterface**)_queueInterface && ((*(IOHIDQueueInterface**)_queueInterface)->create((IOHIDQueueInterface**)_queueInterface, 0, 16) == SEVERITY_SUCCESS)) { //NOTE: Max number of elements in queue
										_info = [NSMutableDictionary new];
										table = [_usageTables objectForKey:@"0"];
										value = [[(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsagePageKey] unsignedShortValue];
										string = (value < [table count] ? [table objectAtIndex:value] : nil);
										[_info setObject:([string length] ? string : [(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsagePageKey]) forKey:@kIOHIDPrimaryUsagePageKey];
										table = [_usageTables objectForKey:[NSString stringWithFormat:@"%i", value]];
										value = [[(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsageKey] unsignedShortValue];
										string = (value < [table count] ? [table objectAtIndex:value] : nil);
										[_info setObject:([string length] ? string : [(NSDictionary*)dictionary objectForKey:@kIOHIDPrimaryUsageKey]) forKey:@kIOHIDPrimaryUsageKey];
										[_info setValue:[(NSDictionary*)dictionary objectForKey:@kIOHIDProductKey] forKey:@kIOHIDProductKey];
										[_info setValue:[(NSDictionary*)dictionary objectForKey:@kIOHIDManufacturerKey] forKey:@kIOHIDManufacturerKey];
										
										_cookies = CFDictionaryCreateMutable(kCFAllocatorDefault, CFArrayGetCount(elements), NULL, &kCFTypeDictionaryValueCallBacks);
										for(i = 0; i < CFArrayGetCount(elements); ++i) {
											element = CFArrayGetValueAtIndex(elements, i);
											cookie = (IOHIDElementCookie)[[(NSDictionary*)element objectForKey:@kIOHIDElementCookieKey] unsignedLongValue];
											
											if(!CFDictionaryContainsKey(_cookies, (const void*)(long)cookie)) {
												data = CFDataCreateMutable(kCFAllocatorDefault, sizeof(ElementInfo));
												CFDataSetLength(data, sizeof(ElementInfo));
												info = (ElementInfo*)CFDataGetMutableBytePtr(data);
												info->info = [NSMutableDictionary new];
												[info->info setValue:[(NSDictionary*)element objectForKey:@kIOHIDElementNameKey] forKey:@kIOHIDElementNameKey];
												[info->info setValue:[(NSDictionary*)element objectForKey:@kIOHIDElementMinKey] forKey:@kIOHIDElementMinKey];
												[info->info setValue:[(NSDictionary*)element objectForKey:@kIOHIDElementMaxKey] forKey:@kIOHIDElementMaxKey];
												[info->info setValue:[(NSDictionary*)element objectForKey:@kIOHIDElementIsRelativeKey] forKey:@kIOHIDElementIsRelativeKey];
												table = [_usageTables objectForKey:@"0"];
												value = [[(NSDictionary*)element objectForKey:@kIOHIDElementUsagePageKey] unsignedShortValue];
												string = (value < [table count] ? [table objectAtIndex:value] : nil);
												[info->info setObject:([string length] ? string : [(NSDictionary*)element objectForKey:@kIOHIDElementUsagePageKey]) forKey:@kIOHIDElementUsagePageKey];
												table = [_usageTables objectForKey:[NSString stringWithFormat:@"%i", value]];
												value = [[(NSDictionary*)element objectForKey:@kIOHIDElementUsageKey] unsignedShortValue];
												string = (value < [table count] ? [table objectAtIndex:value] : nil);
												[info->info setObject:([string length] ? string : [(NSDictionary*)element objectForKey:@kIOHIDElementUsageKey]) forKey:@kIOHIDElementUsageKey];
												info->value = 0;
												info->min = [[(NSDictionary*)element objectForKey:@kIOHIDElementMinKey] intValue];
												info->max = [[(NSDictionary*)element objectForKey:@kIOHIDElementMaxKey] intValue];
												info->isRelative = [[(NSDictionary*)element objectForKey:@kIOHIDElementIsRelativeKey] boolValue];
												CFDictionarySetValue(_cookies, (const void*)(long)cookie, data);
												CFRelease(data);
											
												(*(IOHIDQueueInterface**)_queueInterface)->addElement((IOHIDQueueInterface**)_queueInterface, cookie, 0);
											}
											else if([[NSUserDefaults standardUserDefaults] boolForKey:@"debug"])
											NSLog(@"Found duplicate cookie '%@\' for device \"%@\"", [(NSDictionary*)element objectForKey:@kIOHIDElementCookieKey], [(NSDictionary*)dictionary objectForKey:@kIOHIDProductKey]);
										}
										
										if((*(IOHIDQueueInterface**)_queueInterface)->createAsyncEventSource((IOHIDQueueInterface**)_queueInterface, &_hidEventSource) == kIOReturnSuccess) {
											if((*(IOHIDQueueInterface**)_queueInterface)->setEventCallout((IOHIDQueueInterface**)_queueInterface, _QueueCallbackFunction, NULL, self) == kIOReturnSuccess) {
												CFRunLoopAddSource(_hidRunLoop ? _hidRunLoop : CFRunLoopGetMain(), _hidEventSource, kCFRunLoopCommonModes);
												if((*(IOHIDQueueInterface**)_queueInterface)->start((IOHIDQueueInterface**)_queueInterface) == SEVERITY_SUCCESS)
												success = YES;
											}
										}
									}
								}
								CFRelease(elements);
							}
							if(success == NO)
							[self _disconnect];
						}
						(*plugInInterface)->Release(plugInInterface);
					}
					else
					NSLog(@"%s: IOCreatePlugInInterfaceForService() failed with error %i", __FUNCTION__, error);
					
					CFDictionaryApplyFunction(_cookies, _DictionaryPollFunction, _hidDeviceInterface);
				}
				else
				success = YES;
			}
			CFRelease(dictionary);
		}
		IOObjectRelease(iterator);
	}
	else
	NSLog(@"%s: IOServiceGetMatchingServices() failed with error %i", __FUNCTION__, error);
	
	pthread_mutex_unlock(&_deviceMutex);
	
	if(success == NO)
	[self _disconnect];
	
	if(!wasConnected && [self isConnected])
	[_delegate HIDControllerDidConnect:self];
}

static void _DictionaryReleaseFunction(const void* key, const void* value, void* context)
{
	ElementInfo*			info = (ElementInfo*)CFDataGetBytePtr((CFDataRef)value);
	
	[info->info release];
	info->info = nil;
}

- (void) _disconnect
{
	BOOL					wasConnected = [self isConnected];
	
	pthread_mutex_lock(&_deviceMutex);
	
	if(_hidEventSource) {
		(*(IOHIDQueueInterface**)_queueInterface)->stop((IOHIDQueueInterface**)_queueInterface);
		
		CFRunLoopRemoveSource(_hidRunLoop ? _hidRunLoop : CFRunLoopGetMain(), _hidEventSource, kCFRunLoopCommonModes);
		CFRelease(_hidEventSource);
		_hidEventSource = NULL;
	}
	
	if((IOHIDQueueInterface**)_queueInterface) {
		(*(IOHIDQueueInterface**)_queueInterface)->dispose((IOHIDQueueInterface**)_queueInterface);
		(*(IOHIDQueueInterface**)_queueInterface)->Release((IOHIDQueueInterface**)_queueInterface);
		_queueInterface = NULL;
	}
	
	if(_cookies) {
		CFDictionaryApplyFunction(_cookies, _DictionaryReleaseFunction, NULL);
		CFRelease(_cookies);
		_cookies = NULL;
	}
	
	[_info release];
	_info = nil;
	
	if((IOHIDDeviceInterface**)_hidDeviceInterface) {
		(*(IOHIDDeviceInterface**)_hidDeviceInterface)->close((IOHIDDeviceInterface**)_hidDeviceInterface);
		(*(IOHIDDeviceInterface**)_hidDeviceInterface)->Release((IOHIDDeviceInterface**)_hidDeviceInterface);
		_hidDeviceInterface = NULL;
	}
	
	pthread_mutex_unlock(&_deviceMutex);
	
	if(wasConnected)
	[_delegate HIDControllerDidDisconnect:self];
}

- (void) _didUpdateElement:(NSArray*)arguments
{
	if([self isConnected])
	[_delegate HIDController:self didUpdateElementWithCookie:[[arguments objectAtIndex:0] unsignedLongValue] value:[[arguments objectAtIndex:1] intValue] min:[[arguments objectAtIndex:2] intValue] max:[[arguments objectAtIndex:3] intValue] info:([arguments count] > 4 ? [arguments objectAtIndex:4] : nil)];
}

- (void) didUpdateElementWithCookie:(unsigned long)cookie value:(SInt32)value min:(SInt32)min max:(SInt32)max info:(NSDictionary*)info
{
	if([[self class] useHIDThread])
	[self performSelectorOnMainThread:@selector(_didUpdateElement:) withObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:cookie], [NSNumber numberWithInt:value], [NSNumber numberWithInt:min], [NSNumber numberWithInt:max], info, nil] waitUntilDone:NO];
	else
	[_delegate HIDController:self didUpdateElementWithCookie:cookie value:value min:min max:max info:info];
}

/* May be called from HID thread */
- (void) _processEvents
{
	AbsoluteTime			zeroTime = {0,0};
	IOHIDEventStruct		hidEvent;
	CFDataRef				data;
	ElementInfo*			info;
	
	pthread_mutex_lock(&_deviceMutex);
	while((*(IOHIDQueueInterface**)_queueInterface)->getNextEvent((IOHIDQueueInterface**)_queueInterface, &hidEvent, zeroTime, 0) == kIOReturnSuccess) {
		if((data = CFDictionaryGetValue(_cookies, (const void*)(long)hidEvent.elementCookie))) {
			info = (ElementInfo*)CFDataGetBytePtr(data);
			info->value = hidEvent.value;
			
			[self didUpdateElementWithCookie:(unsigned long)hidEvent.elementCookie value:info->value min:info->min max:info->max info:info->info];
			
			//HACK: Some devices like Logitech mice do not post a new event to "reset" relative elements
			if(info->isRelative)
			info->value = 0.0;
		}
		
		if((hidEvent.longValueSize != 0) && (hidEvent.longValue != NULL))
		free(hidEvent.longValue);
	}
	pthread_mutex_unlock(&_deviceMutex);
}

- (NSDictionary*) info
{
	return _info;
}

static void _DictionaryCookieFunction(const void* key, const void* value, void* context)
{
	ElementInfo*			info = (ElementInfo*)CFDataGetBytePtr((CFDataRef)value);
	
	[(NSMutableDictionary*)context setObject:info->info forKey:[NSNumber numberWithUnsignedLong:(unsigned long)key]];
}

- (NSDictionary*) allElements
{
	NSMutableDictionary*	dictionary;
	
	if(_cookies == NULL)
	return nil;
	
	dictionary = [NSMutableDictionary dictionary];
	CFDictionaryApplyFunction(_cookies, _DictionaryCookieFunction, dictionary);
	
	return dictionary;
}

- (BOOL) fetchElementWithCookie:(unsigned long)cookie value:(SInt32*)value min:(SInt32*)min max:(SInt32*)max
{
	CFDataRef				data;
	ElementInfo*			info;
	
	if((data = CFDictionaryGetValue(_cookies, (void*)cookie))) {
		info = (ElementInfo*)CFDataGetBytePtr(data);
		
		if(value)
		*value = info->value;
		if(min)
		*min = info->min;
		if(max)
		*max = info->max;
		
		return YES;
	}
	
	return NO;
}

@end
