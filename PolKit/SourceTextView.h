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

#import <AppKit/AppKit.h>

typedef enum {
	kSourceTextViewLanguage_Undefined = 0,
	kSourceTextViewLanguage_C,
	kSourceTextViewLanguage_CPP,
	kSourceTextViewLanguage_JavaScript,
	kSourceTextViewLanguage_Lua,
	kSourceTextViewLanguage_ShellScript
} SourceTextViewLanguage;

@interface SourceTextView : NSTextView
{
@private
	SourceTextViewLanguage	_language;
	BOOL					_showLines;
	NSDictionary*			_keywordColors;
	NSColor*				_stringColor;
	NSColor*				_commentColor;
	NSColor*				_preprocessorColor;
	NSColor*				_errorColor;
}
+ (NSMutableDictionary*) keywordColorsFromKeywordsPropertyList:(NSString*)path;

- (void) setLanguage:(SourceTextViewLanguage)language;
- (SourceTextViewLanguage) language;
- (void) setSource:(NSString*)source; //Observe NSTextDidChangeNotification to know when source has been edited
- (NSString*) source;

- (void) setShowLineNumbers:(BOOL)flag; //YES by default (this also controls wrapping)
- (BOOL) showLineNumbers;

- (void) setKeywordColors:(NSDictionary*)keywords; //Maps keywords to NSColors
- (NSDictionary*) keywordColors;
- (void) setStringColor:(NSColor*)color; //Strings are assumed to be '...' or "..."
- (NSColor*) stringColor;
- (void) setCommentColor:(NSColor*)color; //Comments are assumed to be //... or /* ... */
- (NSColor*) commentColor;
- (void) setPreprocessorColor:(NSColor*)color; //Preprocessor is assumed to be #...
- (NSColor*) preprocessorColor;

- (void) setErrorLine:(unsigned)line; //Starts at 1 (automatically cleared on edit or pass 0 to clear manually)
- (void) setErrorHighlightColor:(NSColor*)color;
- (NSColor*) errorHighlightColor;
@end

@interface SourceTextView (Actions)
- (void) shiftLeft:(id)sender;
- (void) shiftRight:(id)sender;
@end
