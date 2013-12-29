/*
	This file is part of the PolKit library.
	Copyright (C) 2008 Pierre-Olivier Latour <info@pol-online.net>
	
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

#import "SourceTextView.h"

typedef enum {
	kSourceToken_Code = 0,
	kSourceToken_SingleQuoteString,
	kSourceToken_DoubleQuoteString,
	kSourceToken_LineComment,
	kSourceToken_BlockComment,
	kSourceToken_Preprocessor
} SourceToken;

#define kTabWidth					4

typedef void (*SourceTokenCallback)(NSString* source, SourceToken token, NSRange range, void* userInfo);

@interface SourceRulerView : NSRulerView
{
@private
	SourceTextView*		_sourceView; //Not retained
}
- (void) setSourceView:(SourceTextView*)view;
@end

static void _SourceColorizeCallback(NSString* source, SourceToken token, NSRange range, void* userInfo)
{
	SourceTextView*					view = (SourceTextView*)userInfo;
	static NSCharacterSet*			characters = nil;
	static NSCharacterSet*			charactersInverted = nil;
	NSRange							subRange;
	NSColor*						color;
	unsigned						start2,
									end2;
	if(characters == nil)
	characters = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789#ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"] retain];
	if(charactersInverted == nil)
	charactersInverted = [[characters invertedSet] retain];
	
	switch(token) {
		
		case kSourceToken_Code:
		if([view keywordColors]) {
			start2 = range.location;
			end2 = range.location + range.length;
			while(1) {
				range = [source rangeOfCharacterFromSet:characters options:0 range:NSMakeRange(start2, end2 - start2)];
				if(range.location != NSNotFound) {
					start2 = range.location;
					if(start2 == end2)
					break;
				}
				
				range = [source rangeOfCharacterFromSet:charactersInverted options:0 range:NSMakeRange(start2, end2 - start2)];
				if(range.location == NSNotFound)
				range.location = end2;
				if(range.location != start2) {
					subRange = NSMakeRange(start2, range.location - start2);
					if((color = [[view keywordColors] objectForKey:[source substringWithRange:subRange]]))
					[view setTextColor:color range:subRange];
					start2 = range.location;
					if(start2 == end2)
					break;
				}
				else
				break;
			}
		}
		break;
		
		case kSourceToken_SingleQuoteString:
		case kSourceToken_DoubleQuoteString:
		if((color = [view stringColor]))
		[view setTextColor:color range:range];
		break;
		
		case kSourceToken_LineComment:
		case kSourceToken_BlockComment:
		if((color = [view commentColor]))
		[view setTextColor:color range:range];
		break;
		
		case kSourceToken_Preprocessor:
		if((color = [view preprocessorColor]))
		[view setTextColor:color range:range];
		break;
		
	}
}

@implementation SourceRulerView

- (float) requiredThickness
{
	return 30;
}

- (void) setSourceView:(SourceTextView*)view
{
	_sourceView = view;
	[self setNeedsDisplay:YES];
}

- (void) drawRect:(NSRect)aRect
{
	static NSDictionary*			attributes = nil;
	static NSColor*					backColor = nil;
	static NSColor*					lineColor = nil;
	NSRect							bounds = [self bounds];
	unsigned						start,
									i;
	NSPoint							point;
	float							offset;
	
	if(backColor == nil)
	backColor = [[NSColor colorWithDeviceRed:0.90 green:0.90 blue:0.90 alpha:1.0] retain];
	if(lineColor == nil)
	lineColor = [[NSColor grayColor] retain];
	if(attributes == nil)
	attributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSColor darkGrayColor], NSForegroundColorAttributeName, [NSFont systemFontOfSize:10], NSFontAttributeName, nil];
	
	[backColor set];
	NSRectFill(aRect);
	[lineColor set];
	NSFrameRect(NSMakeRect(bounds.origin.x + bounds.size.width - 1, aRect.origin.y, 1, aRect.size.height));
	
	start = ([_sourceView visibleRect].origin.y + aRect.origin.y) / 14 + 1;
	offset = fmodf([_sourceView visibleRect].origin.y + aRect.origin.y, 14);
	for(i = 0; i < aRect.size.height / 14 + 1; ++i) {
		point.x = (start + i < 10 ? bounds.origin.x + 17 : (start + i < 100 ? bounds.origin.x + 11 : bounds.origin.x + 5));
		point.y = (aRect.origin.y / 14 + i) * 14 - offset;
		[[NSString stringWithFormat:@"%i", start + i] drawAtPoint:point withAttributes:attributes];
	}
}

@end

@implementation SourceTextView

+ (NSMutableDictionary*) keywordColorsFromKeywordsPropertyList:(NSString*)path
{
	NSMutableDictionary*			dictionary = [NSMutableDictionary dictionary];
	NSArray*						array;
	NSDictionary*					entry;
	NSColor*						color;
	NSScanner*						scanner;
	NSString*						keyword;
	unsigned						i;
	
	//Read the plist file
	array = [NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:path] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
	if(![array isKindOfClass:[NSArray class]])
	return nil;
	
	//Extract colors and keywords
	for(i = 0; i < [array count]; ++i) {
		entry = [array objectAtIndex:i];
		color = [NSColor colorWithDeviceRed:[[entry objectForKey:@"color-red"] floatValue] green:[[entry objectForKey:@"color-green"] floatValue] blue:[[entry objectForKey:@"color-blue"] floatValue] alpha:1.0];
		scanner = [NSScanner scannerWithString:[entry objectForKey:@"keywords"]];
		while(![scanner isAtEnd]) {
			[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
			if([scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&keyword])
			[dictionary setObject:color forKey:keyword];
		}
	}
	
	return dictionary;
}

+ (void) _parseSource:(NSString*)source range:(NSRange)range language:(SourceTextViewLanguage)language callback:(SourceTokenCallback)callback userInfo:(void*)info
{
	unsigned						tokenStart = 0,
									i;
	SourceToken						state = kSourceToken_Code,
									oldState;
	unichar*						buffer;
	NSRange							subRange;
	
	//Safe checks
	if((range.location + range.length > [source length]) || (range.length == 0) || (callback == NULL))
	return;
	
	//Copy string contents into buffer
	buffer = malloc(range.length * sizeof(unichar));
	if(buffer == NULL)
	return;
	[source getCharacters:buffer range:range];
	
	//Scan characters
	for(i = 0; i < range.length; ++i) {
		oldState = state;
		switch(buffer[i]) {
			
			case '#':
			if(state != kSourceToken_Code)
			break;
			if((language == kSourceTextViewLanguage_C) || (language == kSourceTextViewLanguage_CPP))
			state = kSourceToken_Preprocessor;
			else if(language == kSourceTextViewLanguage_ShellScript)
			state = kSourceToken_LineComment;
			break;
			
			case '-':
			if(language == kSourceTextViewLanguage_Lua) {
				if(state != kSourceToken_Code)
				break;
				if(i + 1 == range.length)
				break;
				if(buffer[i + 1] == '-') {
					if((i + 3 < range.length) && (buffer[i + 2] == '[') && (buffer[i + 3] == '[')) {
						state = kSourceToken_BlockComment;
						i += 3;
					}
					else {
						state = kSourceToken_LineComment;
						i += 1;
					}
				}
			}
			break;
			
			case ']':
			if(language == kSourceTextViewLanguage_Lua) {
				if(state != kSourceToken_BlockComment)
				break;
				if(i + 1 == range.length)
				break;
				if(buffer[i + 1] == ']') {
					state = kSourceToken_Code;
					i += 1;
				}
			}
			break;
			
			case '/':
			if((language == kSourceTextViewLanguage_C) || (language == kSourceTextViewLanguage_CPP) || (language == kSourceTextViewLanguage_JavaScript)) {
				if((state != kSourceToken_Code) && (state != kSourceToken_Preprocessor))
				break;
				if(i + 1 == range.length)
				break;
				if(buffer[i + 1] == '/') {
					state = kSourceToken_LineComment;
					i += 1;
				}
				else if(buffer[i + 1] == '*') {
					state = kSourceToken_BlockComment;
					i += 1;
				}
			}
			break;
			
			case '\n':
			if((state == kSourceToken_LineComment) || (state == kSourceToken_Preprocessor))
			state = kSourceToken_Code;
			break;
			
			case '*':
			if((language == kSourceTextViewLanguage_C) || (language == kSourceTextViewLanguage_CPP) || (language == kSourceTextViewLanguage_JavaScript)) {
				if(state != kSourceToken_BlockComment)
				break;
				if(i + 1 == range.length)
				break;
				if(buffer[i + 1] == '/') {
					state = kSourceToken_Code;
					i += 1;
				}
			}
			break;
			
			case '\'':
			if((state != kSourceToken_Code) && (state != kSourceToken_SingleQuoteString))
			break;
			if(i > 0) {
				if(buffer[i - 1] == '\\')
				break;
			}
			if(state == kSourceToken_SingleQuoteString)
			state = kSourceToken_Code;
			else
			state = kSourceToken_SingleQuoteString;
			break;
			
			case '"':
			if((state != kSourceToken_Code) && (state != kSourceToken_DoubleQuoteString))
			break;
			if(i > 0) {
				if(buffer[i - 1] == '\\')
				break;
			}
			if(state == kSourceToken_DoubleQuoteString)
			state = kSourceToken_Code;
			else
			state = kSourceToken_DoubleQuoteString;
			break;
			
		}
		
		if((state != oldState) && (i > 0)) {
			subRange.location = tokenStart;
			if(state == kSourceToken_BlockComment)
			tokenStart = i - (language == kSourceTextViewLanguage_Lua ? 3 : 1);
			else if(state == kSourceToken_LineComment)
			tokenStart = i - 1;
			else if((state == kSourceToken_Code) && (oldState != kSourceToken_LineComment))
			tokenStart = i + 1;
			else
			tokenStart = i;
			subRange.length = tokenStart - subRange.location;
			
			(*callback)(source, oldState, NSMakeRange(range.location + subRange.location, subRange.length), info);
		}
	}
	if(tokenStart < range.length) {
		subRange.location = tokenStart;
		subRange.length = range.length - tokenStart;
		
		(*callback)(source, state, NSMakeRange(range.location + subRange.location, subRange.length), info);
	}
	
	//Release buffer
	free(buffer);
}

- (void) _finishInitialization
{
	NSMutableParagraphStyle*	style;
	NSTextTab*					tabStop;
	NSUInteger					i;
	
	[self setMaxSize:NSMakeSize(10000000, 10000000)];
	[self setAutoresizingMask:NSViewNotSizable];
	
	[self setDelegate:self];
	_language = kSourceTextViewLanguage_Undefined;
	_showLines = YES;
	_stringColor = [[NSColor colorWithDeviceRed:0.6 green:0.3 blue:0.0 alpha:1.0] retain];
	_commentColor = [[NSColor darkGrayColor] retain];
	_preprocessorColor = [[NSColor blueColor] retain];
	_errorColor = [[NSColor colorWithDeviceRed:1.0 green:0.4 blue:0.5 alpha:1.0] retain];
	[self setFont:[NSFont fontWithName:@"Monaco" size:10]];
	[self setSmartInsertDeleteEnabled:NO];
	
	style = [NSMutableParagraphStyle new];
	[style setTabStops:[NSArray array]];
	for(i = 0; i < 128; ++i) {
		tabStop = [[NSTextTab alloc] initWithType:NSLeftTabStopType location:(i * kTabWidth * 6)];
		[style addTabStop:tabStop];
		[tabStop release];
	}
	[[self textStorage] addAttributes:[NSDictionary dictionaryWithObject:style forKey:NSParagraphStyleAttributeName] range:NSMakeRange(0, [[[self textStorage] string] length])];
	[style release];
}

- (id) initWithFrame:(NSRect)frame
{
	if((self = [super initWithFrame:frame]))
	[self _finishInitialization];
	
	return self;
}

- (id) initWithCoder:(NSCoder*)coder
{
	if((self = [super initWithCoder:coder]))
	[self _finishInitialization];
	
	return self;
}

- (void) dealloc
{
	[_keywordColors release];
	[_stringColor release];
	[_commentColor release];
	[_preprocessorColor release];
	[_errorColor release];
	
	[super dealloc];
}

- (BOOL) validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem
{
	if([anItem action] == @selector(paste:))
	return ([self isEditable] && [self preferredPasteboardTypeFromArray:[[NSPasteboard generalPasteboard] types] restrictedToTypesFromArray:[NSArray arrayWithObject:NSStringPboardType]]);
	
	return [super validateUserInterfaceItem:anItem];
}

- (void) paste:(id)sender
{
	[self pasteAsPlainText:sender];
}

//FIXME: This does not work correctly if the text view contains text
- (void) _showLineNumbers:(BOOL)flag
{
	NSScrollView*		scrollView = (NSScrollView*)[[self superview] superview];
	NSTextContainer*	container = [[[self layoutManager] textContainers] objectAtIndex:0];
	SourceRulerView*	rulerView;
	Class				rulerClass;
	
	if([scrollView isKindOfClass:[NSScrollView class]]) {
		if(flag) {
			rulerClass = [NSScrollView rulerViewClass];
			[NSScrollView setRulerViewClass:[SourceRulerView class]];
			[scrollView setHasVerticalRuler:YES];
			[scrollView setRulersVisible:YES];
			[NSScrollView setRulerViewClass:rulerClass];
			rulerView = (SourceRulerView*)[scrollView verticalRulerView];
			[rulerView setSourceView:self];
			[rulerView setRuleThickness:30];
			
			[scrollView setHasHorizontalScroller:YES];
			[container setWidthTracksTextView:NO];
			[container setHeightTracksTextView:NO];
			[container setContainerSize:NSMakeSize(10000000, 10000000)]; //NOTE: This forces a refresh
			[self setHorizontallyResizable:YES];
		}
		else {
			[scrollView setHasVerticalRuler:NO];
			
			[scrollView setHasHorizontalScroller:NO];
			[container setWidthTracksTextView:YES];
			[container setHeightTracksTextView:NO];
			[container setContainerSize:NSMakeSize(10, 10000000)]; //NOTE: This forces a refresh
			[self setHorizontallyResizable:NO];
		}
	}
}

- (void) setShowLineNumbers:(BOOL)flag
{
	if(flag != _showLines) {
		[self _showLineNumbers:flag];
		_showLines = flag;
	}
}

- (BOOL) showLineNumbers
{
	return _showLines;
}

- (void) viewDidMoveToSuperview
{
	NSScrollView*			scrollView = (NSScrollView*)[[self superview] superview];
	
	[self _showLineNumbers:_showLines];
	
	if([scrollView isKindOfClass:[NSScrollView class]])
	[scrollView setLineScroll:14];
}

- (void) insertNewline:(id)sender
{
	NSString*				string = [[self textStorage] mutableString];
	NSRange					range = [self selectedRange],
							subRange,
							subRange2;
	
	[self insertText:@"\n"];
	
	if((range.location != NSNotFound) && (range.location > 0)) {
		subRange = [string rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, range.location)];
		if(subRange.location == NSNotFound)
		subRange.location = 0;
		else
		subRange.location += 1;
		
		subRange2 = [string rangeOfCharacterFromSet:[[NSCharacterSet whitespaceCharacterSet] invertedSet] options:0 range:NSMakeRange(subRange.location, range.location - subRange.location)];
		if(subRange2.location == NSNotFound)
		subRange2.location = range.location;
		
		[self insertText:[string substringWithRange:NSMakeRange(subRange.location, subRange2.location - subRange.location)]];
	}
}

- (void) _highlightLine:(unsigned)line withColor:(NSColor*)color
{
	NSString*				string = [self string];
	unsigned				length = [string length],
							count = 0,
							location = 0;
	NSRange					range;
	
	while(location < length) {
		range = [string rangeOfString:@"\n" options:0 range:NSMakeRange(location, length - location)];
		if(range.location == NSNotFound)
		range.location = length;
		if(line == count) {
			range = NSMakeRange(location, range.location - location);
			if(color)
			[[self textStorage] addAttribute:NSBackgroundColorAttributeName value:color range:range];
			else
			[[self textStorage] removeAttribute:NSBackgroundColorAttributeName range:range];
			break;
		}
		location = range.location + 1;
		++count;
	}
}

- (void) _highlightAllLinesWithColor:(NSColor*)color
{
	NSRange					range = NSMakeRange(0, [[self string] length]);
	
	if(color)
	[[self textStorage] addAttribute:NSBackgroundColorAttributeName value:color range:range];
	else
	[[self textStorage] removeAttribute:NSBackgroundColorAttributeName range:range];
}

- (void) textDidChange:(NSNotification*)notification
{
	NSString*				string = [self string];
	NSRange					range = NSMakeRange(0, [string length]);
	
	[self setTextColor:nil range:range];
	[SourceTextView _parseSource:string range:range language:_language callback:_SourceColorizeCallback userInfo:self];
	
	[self _highlightAllLinesWithColor:nil];
}

- (void) setErrorLine:(unsigned)line
{
	if(line > 0)
	[self _highlightLine:(line - 1) withColor:_errorColor];
	else
	[self _highlightAllLinesWithColor:nil];
}

- (void) setLanguage:(SourceTextViewLanguage)language
{
	_language = language;
	[self textDidChange:nil];
}

- (SourceTextViewLanguage) language
{
	return _language;
}

- (void) setSource:(NSString*)source
{
	if(![source isEqualToString:[self string]]) {
		[self setString:([source length] ? source : @"")];
		[self textDidChange:nil];
	}
}

- (NSString*) source
{
	return [self string];
}

- (void) setKeywordColors:(NSDictionary*)keywords
{
	if(keywords != _keywordColors) {
		[_keywordColors release];
		_keywordColors = [keywords copy];
		
		[self textDidChange:nil];
	}
}

- (NSDictionary*) keywordColors
{
	return _keywordColors;
}

- (void) setStringColor:(NSColor*)color
{
	if(color != _stringColor) {
		[_stringColor release];
		_stringColor = [[color colorUsingColorSpaceName:NSDeviceRGBColorSpace] retain];
		
		[self textDidChange:nil];
	}
}

- (NSColor*) stringColor
{
	return _stringColor;
}

- (void) setCommentColor:(NSColor*)color
{
	if(color != _commentColor) {
		[_commentColor release];
		_commentColor = [[color colorUsingColorSpaceName:NSDeviceRGBColorSpace] retain];
		
		[self textDidChange:nil];
	}
}

- (NSColor*) commentColor
{
	return _commentColor;
}

- (void) setPreprocessorColor:(NSColor*)color
{
	if(color != _preprocessorColor) {
		[_preprocessorColor release];
		_preprocessorColor = [[color colorUsingColorSpaceName:NSDeviceRGBColorSpace] retain];
		
		[self textDidChange:nil];
	}
}

- (NSColor*) preprocessorColor
{
	return _preprocessorColor;
}

- (void) setErrorHighlightColor:(NSColor*)color
{
	if(color != _errorColor) {
		[_errorColor release];
		_errorColor = [[color colorUsingColorSpaceName:NSDeviceRGBColorSpace] retain];
		
		[self textDidChange:nil];
	}
}

- (NSColor*) errorHighlightColor
{
	return _errorColor;
}

@end

@implementation SourceTextView (Actions)

- (NSRange) __shiftLeft:(NSRange)range
{
	NSString*				string = [[self textStorage] mutableString];
	NSRange					newRange = range,
							subRange;
	
	if(![string length])
	return newRange;
	
	subRange = [string rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, range.location)];
	if(subRange.location == NSNotFound) {
		range.length += range.location;
		range.location = 0;
	}
	else {
		range.length += range.location - subRange.location - 1;
		range.location = subRange.location + 1;
	}
	if([string characterAtIndex:range.location] == '\t') {
		if(range.location < newRange.location) {
			newRange.location -= 1;
			newRange.length += 1;
		}
	}
	else if(range.length == 0)
	return newRange;
	
	while(1) {
		if([string characterAtIndex:range.location] == '\t') {
			[self replaceCharactersInRange:NSMakeRange(range.location, 1) withString:@""];
			if(newRange.length > 0)
			newRange.length -= 1;
			if(range.length > 0)
			range.length -= 1;
		}
		
		subRange = [string rangeOfString:@"\n" options:0 range:range];
		if((subRange.location == NSNotFound) || (subRange.location + 1 == range.location + range.length))
		break;
		range.length -= subRange.location - range.location + 1;
		range.location = subRange.location + 1;
	}
	
	[self didChangeText];
	
	return newRange;
}

- (NSRange) __shiftRight:(NSRange)range
{
	NSString*				string = [[self textStorage] mutableString];
	NSRange					newRange = range,
							subRange;
	
	subRange = [string rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, range.location)];
	if(subRange.location == NSNotFound) {
		range.length += range.location;
		range.location = 0;
	}
	else {
		range.length += range.location - subRange.location - 1;
		range.location = subRange.location + 1;
	}
	newRange.location += 1;
	newRange.length -= 1;
	
	while(1) {
		[self replaceCharactersInRange:NSMakeRange(range.location, 0) withString:@"\t"];
		newRange.length += 1;
		range.length += 1;
		
		subRange = [string rangeOfString:@"\n" options:0 range:range];
		if((subRange.location == NSNotFound) || (subRange.location + 1 == range.location + range.length))
		break;
		range.length -= subRange.location - range.location + 1;
		range.location = subRange.location + 1;
	}
	
	[self didChangeText];
	
	return newRange;
}

- (void) _shiftLeft:(NSValue*)valueRange
{
	NSRange					range = [valueRange rangeValue],
							newRange = [self __shiftLeft:range];
	
	if(!NSEqualRanges(newRange, range)) {
		[[self undoManager] registerUndoWithTarget:self selector:@selector(_shiftRight:) object:[NSValue valueWithRange:newRange]];
		[self setSelectedRange:newRange];
	}
}

- (void) shiftLeft:(id)sender
{
	[self _shiftLeft:[NSValue valueWithRange:[self selectedRange]]];
}

- (void) _shiftRight:(NSValue*)valueRange
{
	NSRange					range = [valueRange rangeValue],
							newRange = [self __shiftRight:range];
	
	if(!NSEqualRanges(newRange, range)) {
		[[self undoManager] registerUndoWithTarget:self selector:@selector(_shiftLeft:) object:[NSValue valueWithRange:newRange]];
		[self setSelectedRange:newRange];
	}
}

- (void) shiftRight:(id)sender
{
	[self _shiftRight:[NSValue valueWithRange:[self selectedRange]]];
}

- (BOOL) validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem
{
	if(([anItem action] == @selector(shiftLeft:)) || ([anItem action] == @selector(shiftRight:)))
	return ([[self window] firstResponder] == self);
	
	return [super validateUserInterfaceItem:anItem];
}

@end
