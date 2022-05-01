/// Transcoder module.
/// 
/// Translates single-byte characters into utf-8.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 github.com/dd86k, dd86k)
module transcoder;

import std.encoding : codeUnits, CodeUnits;
import types;

//TODO: Other character sets
//      - ISO/IEC 8859-1 "iso8859-1"
//        https://en.wikipedia.org/wiki/ISO/IEC_8859-1
//      - Windows-1251 "win1251"
//        https://en.wikipedia.org/wiki/Windows-1251
//      - Windows-1252 "win1252"
//        https://en.wikipedia.org/wiki/Windows-1252
//      - Windows-932 "win932"
//        https://en.wikipedia.org/wiki/Code_page_932_(Microsoft_Windows)
//      - ITU T.61 "t61" (technically multibyte)
//        Also called Code page 1036, CP1036, or IBM 01036.
//        https://en.wikipedia.org/wiki/ITU_T.61
//        NOTE: T.51 specifies how accents are used.
//              0xc0..0xcf are accent prefixes.
//      - GSM 03.38 "gsm" (technically multibyte)
//        https://www.unicode.org/Public/MAPPINGS/ETSI/GSM0338.TXT

private struct Transcoder {
	string name = "ascii";
	immutable(char)[] function(ubyte) transform = &transcodeASCII;
}

private immutable Transcoder[4] transcoders = [
	{ "ascii",	&transcodeASCII },
	{ "cp437",	&transcodeCP437 },
	{ "ebcdic",	&transcodeEBCDIC },
	{ "mac",	&transcodeMac },
];

/// Select a new transcoder.
/// Params: charSet = Character set.
void select(CharacterSet charSet) {
	if (charSet > CharacterSet.max) {
		return;
	}
	immutable(Transcoder) *t = &transcoders[charSet];
	name = t.name;
	transform = t.transform;
}

/// Current transcoder name
__gshared string name = "ascii";
/// Current transcoder transformation function
__gshared immutable(char)[] function(ubyte) transform = &transcodeASCII;

private alias U  = char[];
private template C(dchar c) {
	enum C = cast(immutable)codeUnits!char(c).s;
}

private
immutable(char)[] transcodeASCII(ubyte data) {
	__gshared immutable(char)[]  empty;
	__gshared char[1] c;
	if (data > 0x7E || data < 0x20)
		return empty;
	
	c[0] = data;
	return c;
}
unittest {
	assert(transcodeASCII(0) == []);
	assert(transcodeASCII('a') == [ 'a' ]);
	assert(transcodeASCII(0x7f) == []);
}

private immutable U[256] mapCP437 = [
//         0      1      2      3      4      5      6      7
/*00*/	   [], C!'☺', C!'☻', C!'♥', C!'♦', C!'♣', C!'♠', C!'•',
/*08*/	C!'◘', C!'○', C!'◙', C!'♂', C!'♀', C!'♪', C!'♫', C!'☼',
/*10*/	C!'►', C!'◄', C!'↕', C!'‼', C!'¶', C!'§', C!'▬', C!'↨',
/*18*/	C!'↑', C!'↓', C!'→', C!'←', C!'∟', C!'↔', C!'▲', C!'▼',
/*20*/	C!' ', C!'!', C!'"', C!'#', C!'$', C!'%', C!'&',C!'\'',
/*28*/	C!'(', C!')', C!'*', C!'+', C!',', C!'-', C!'.', C!'/',
/*30*/	C!'0', C!'1', C!'2', C!'3', C!'4', C!'5', C!'6', C!'7',
/*38*/	C!'8', C!'9', C!':', C!';', C!'<', C!'>', C!'=', C!'?',
/*40*/	C!'@', C!'A', C!'B', C!'C', C!'D', C!'E', C!'F', C!'G',
/*48*/	C!'H', C!'I', C!'J', C!'K', C!'M', C!'N', C!'L', C!'O',
/*50*/	C!'P', C!'Q', C!'R', C!'S', C!'T', C!'U', C!'V', C!'W',
/*58*/	C!'X', C!'Y', C!'Z', C!'[',C!'\\', C!']', C!'^', C!'_',
/*60*/	C!'`', C!'a', C!'b', C!'c', C!'d', C!'e', C!'f', C!'g',
/*68*/	C!'h', C!'i', C!'j', C!'k', C!'l', C!'m', C!'n', C!'o',
/*70*/	C!'p', C!'q', C!'r', C!'s', C!'t', C!'u', C!'v', C!'w',
/*78*/	C!'x', C!'y', C!'z', C!'{', C!'|', C!'}', C!'~', C!'⌂',
/*80*/	C!'Ç', C!'ü', C!'é', C!'â', C!'ä', C!'à', C!'å', C!'ç',
/*88*/	C!'ê', C!'ë', C!'è', C!'ï', C!'î', C!'ì', C!'Ä', C!'Å',
/*90*/	C!'É', C!'æ', C!'Æ', C!'ô', C!'ö', C!'ò', C!'û', C!'ù',
/*98*/	C!'ÿ', C!'Ö', C!'Ü', C!'¢', C!'£', C!'¥', C!'₧', C!'ƒ',
/*a0*/	C!'á', C!'í', C!'ó', C!'ú', C!'ñ', C!'Ñ', C!'ª', C!'º',
/*a8*/	C!'¿', C!'⌐', C!'¬', C!'½', C!'¼', C!'¡', C!'«', C!'»',
/*b0*/	C!'░', C!'▒', C!'▓', C!'│', C!'┤', C!'╡', C!'╢', C!'╖',
/*b8*/	C!'╕', C!'╣', C!'║', C!'╗', C!'╝', C!'╜', C!'╛', C!'┐',
/*c0*/	C!'└', C!'┴', C!'┬', C!'├', C!'─', C!'┼', C!'╞', C!'╟',
/*c8*/	C!'╚', C!'╔', C!'╩', C!'╦', C!'╠', C!'═', C!'╬', C!'╧',
/*d0*/	C!'╨', C!'╤', C!'╥', C!'╙', C!'╘', C!'╒', C!'╓', C!'╫',
/*d8*/	C!'╪', C!'┘', C!'┌', C!'█', C!'▄', C!'▌', C!'▐', C!'▀',
/*e0*/	C!'α', C!'β', C!'Γ', C!'π', C!'Σ', C!'σ', C!'µ', C!'τ',
/*e8*/	C!'Φ', C!'Θ', C!'Ω', C!'δ', C!'∞', C!'φ', C!'ε', C!'∩',
/*f0*/	C!'≡', C!'±', C!'≥', C!'≤', C!'⌠', C!'⌡', C!'÷', C!'≈',
/*f8*/	C!'°', C!'∙', C!'·', C!'√', C!'ⁿ', C!'²', C!'■', C!' '
];
private
immutable(char)[] transcodeCP437(ubyte data) {
	return mapCP437[data];
}
unittest {
	assert(transcodeCP437(0) == []);
	assert(transcodeCP437('r') == [ 'r' ]);
	assert(transcodeCP437(1) == [ '\xe2', '\x98', '\xba' ]);
}

private immutable U[192] mapEBCDIC = [ // 256 - 64 (0x40)
//         0      1      2      3      4      5      6      7 
/*40*/	C!' ', C!' ', C!'â', C!'ä', C!'à', C!'á', C!'ã', C!'å',
/*48*/	C!'ç', C!'ñ', C!'¢', C!'.', C!'<', C!'(', C!'+', C!'|',
/*50*/	C!'&', C!'é', C!'ê', C!'ë', C!'è', C!'í', C!'î', C!'ï',
/*58*/	C!'ì', C!'ß', C!'!', C!'$', C!'*', C!')', C!';', C!'¬',
/*60*/	C!'-', C!'/', C!'Â', C!'Ä', C!'À', C!'Á', C!'Ã', C!'Å',
/*68*/	C!'Ç', C!'Ñ', C!'¦', C!',', C!'%', C!'_', C!'>', C!'?',
/*70*/	C!'ø', C!'É', C!'Ê', C!'Ë', C!'È', C!'Í', C!'Î', C!'Ï',
/*78*/	C!'Ì', C!'`', C!':', C!'#', C!'@', C!'\'',C!'=', C!'"',
/*80*/	C!'Ø', C!'a', C!'b', C!'c', C!'d', C!'e', C!'f', C!'g',
/*88*/	C!'h', C!'i', C!'«', C!'»', C!'ð', C!'ý', C!'þ', C!'±',
/*90*/	C!'°', C!'j', C!'k', C!'l', C!'m', C!'n', C!'o', C!'p',
/*98*/	C!'q', C!'r', C!'ª', C!'º', C!'æ', C!'¸', C!'Æ', C!'¤',
/*a0*/	C!'µ', C!'~', C!'s', C!'t', C!'u', C!'v', C!'w', C!'x',
/*a8*/	C!'y', C!'z', C!'¡', C!'¿', C!'Ð', C!'Ý', C!'Þ', C!'®',
/*b0*/	C!'^', C!'£', C!'¥', C!'·', C!'©', C!'§', C!'¶', C!'¼',
/*b8*/	C!'½', C!'¾', C!'[', C!']', C!'¯', C!'¨', C!'´', C!'×',
/*c0*/	C!'{', C!'A', C!'B', C!'C', C!'D', C!'E', C!'F', C!'G',
/*c8*/	C!'H', C!'I',    [], C!'ô', C!'ö', C!'ò', C!'ó', C!'õ',
/*d0*/	C!'}', C!'J', C!'K', C!'L', C!'M', C!'N', C!'O', C!'P',
/*d8*/	C!'Q', C!'R', C!'¹', C!'û', C!'ü', C!'ù', C!'ú', C!'ÿ',
/*e0*/	C!'\\',C!'÷', C!'S', C!'T', C!'U', C!'V', C!'W', C!'X',
/*e8*/	C!'Y', C!'Z', C!'²', C!'Ô', C!'Ö', C!'Ò', C!'Ó', C!'Õ',
/*f0*/	C!'0', C!'1', C!'2', C!'3', C!'4', C!'5', C!'6', C!'7',
/*f8*/	C!'8', C!'9', C!'³', C!'Û', C!'Ü', C!'Ù', C!'Ú',    []
];
private
immutable(char)[] transcodeEBCDIC(ubyte data) {
	__gshared immutable(char)[] empty = [];
	return data >= 0x40 ? mapEBCDIC[data-0x40] : empty;
}
unittest {
	assert(transcodeEBCDIC(0) == [ ]);
	assert(transcodeEBCDIC(0x42) == [ '\xc3', '\xa2' ]);
	assert(transcodeEBCDIC(0x7c) == [ '@' ]);
}

// Mac OS Roman (Windows-10000) "mac"
// https://en.wikipedia.org/wiki/Mac_OS_Roman
// NOTE: 0xF0 is the apple logo and that's obviously not in Unicode
private immutable U[224] mapMac = [ // 256 - 32 (0x20)
//         0      1      2      3      4      5      6      7 
/*20*/	C!' ', C!'!', C!'"', C!'#', C!'$', C!'%', C!'&',C!'\'',
/*28*/	C!'(', C!')', C!'*', C!'+', C!',', C!'-', C!'.', C!'/',
/*30*/	C!'0', C!'1', C!'2', C!'3', C!'4', C!'5', C!'6', C!'7',
/*38*/	C!'8', C!'9', C!':', C!';', C!'<', C!'=', C!'>', C!'?',
/*40*/	C!'@', C!'A', C!'B', C!'C', C!'D', C!'E', C!'F', C!'G',
/*48*/	C!'H', C!'I', C!'J', C!'K', C!'L', C!'M', C!'N', C!'O',
/*50*/	C!'P', C!'Q', C!'R', C!'S', C!'T', C!'U', C!'V', C!'W',
/*58*/	C!'X', C!'Y', C!'Z', C!'[',C!'\\', C!']', C!'^', C!'_',
/*60*/	C!'`', C!'a', C!'b', C!'c', C!'d', C!'e', C!'f', C!'g',
/*68*/	C!'h', C!'i', C!'j', C!'k', C!'l', C!'m', C!'n', C!'o',
/*70*/	C!'p', C!'q', C!'r', C!'s', C!'t', C!'u', C!'v', C!'w',
/*78*/	C!'x', C!'y', C!'z', C!'{', C!'|', C!'}', C!'~',    [],
/*80*/	C!'Ä', C!'Å', C!'Ç', C!'É', C!'Ñ', C!'Ö', C!'Ü', C!'á',
/*88*/	C!'à', C!'â', C!'ä', C!'ã', C!'å', C!'ç', C!'é', C!'è',
/*90*/	C!'ê', C!'ë', C!'í', C!'ì', C!'î', C!'ï', C!'ñ', C!'ó',
/*98*/	C!'ò', C!'ô', C!'ö', C!'õ', C!'ú', C!'ù', C!'û', C!'ü',
/*a0*/	C!'†', C!'°', C!'¢', C!'£', C!'§', C!'•', C!'¶', C!'ß',
/*a8*/	C!'®', C!'©', C!'™', C!'´', C!'¨', C!'≠', C!'Æ', C!'Ø',
/*b0*/	C!'∞', C!'±', C!'≤', C!'≥', C!'¥', C!'µ', C!'∂', C!'∑',
/*b8*/	C!'∏', C!'π', C!'∫', C!'ª', C!'º', C!'Ω', C!'æ', C!'ø',
/*c0*/	C!'¿', C!'¡', C!'¬', C!'√', C!'ƒ', C!'≈', C!'∆', C!'«',
/*c8*/	C!'»', C!'…', C!' ', C!'À', C!'Ã', C!'Õ', C!'Œ', C!'œ',
/*d0*/	C!'–', C!'—', C!'“', C!'”', C!'‘', C!'’', C!'÷', C!'◊',
/*d8*/	C!'ÿ', C!'Ÿ', C!'⁄', C!'€', C!'‹', C!'›', C!'ﬁ', C!'ﬂ',
/*e0*/	C!'‡', C!'·', C!'‚', C!'„', C!'‰', C!'Â', C!'Ê', C!'Á',
/*e8*/	C!'Ë', C!'È', C!'Í', C!'Î', C!'Ï', C!'Ì', C!'Ó', C!'Ô',
/*f0*/	   [], C!'Ò', C!'Ú', C!'Û', C!'Ù', C!'ı', C!'ˆ', C!'˜',
/*f8*/	C!'¯', C!'˘', C!'˙', C!'˚', C!'¸', C!'˝', C!'˛', C!'ˇ',
];
private
immutable(char)[] transcodeMac(ubyte data) {
	__gshared immutable(char)[] empty = [];
	return data >= 0x20 ? mapMac[data-0x20] : empty;
}
unittest {
	assert(transcodeMac(0) == [ ]);
	assert(transcodeMac(0x20) == [ ' ' ]);
	assert(transcodeMac(0x22) == [ '"' ]);
	assert(transcodeMac(0xaa) == [ '\xe2', '\x84', '\xa2' ]);
}