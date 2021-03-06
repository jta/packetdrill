%{
/*
 * Copyright 2013 Google Inc.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */
/*
 * Author: ncardwell@google.com (Neal Cardwell)
 *
 * This is the specification for the lexical scanner for the packetdrill
 * script language. It is processed by the flex lexical scanner
 * generator.
 *
 * For full documentation see: http://flex.sourceforge.net/manual/
 *
 * Here is a quick and dirty tutorial on flex:
 *
 * A flex lexical scanner specification is basically a list of rules,
 * where each rule is a regular expressions for a lexical token to
 * match, followed by a C fragment to execute when the scanner sees
 * that pattern.
 *
 * The lexer feeds a stream of terminal symbols up to this parser,
 * passing up a FOO token for each "return FOO" in the lexer spec. The
 * lexer specifies what value to pass up to the parser by setting a
 * yylval.fooval field, where fooval is a field in the %union in the
 * .y file.
 *
 * TODO: detect overflow in numeric literals.
 */

#include "types.h"

#include <netinet/in.h>
#include <stdlib.h>
#include <stdio.h>
#include "script.h"
#include "tcp_options.h"

/* This include of the bison-generated .h file must go last so that we
 * can first include all of the declarations on which it depends.
 */
#include "parser.h"

/* Suppress flex's generation of an uncalled static input() function, which
 * leads to a compiler warning:
 *    warning: ‘input’ defined but not used
 */
#define YY_NO_INPUT

/* Copy the string name "foo" after the "--" of a "--foo" option. */
static char *option(const char *s)
{
	const int dash_dash_len = 2;
	return strndup(s + dash_dash_len, strlen(s) - dash_dash_len);
}

/* Copy the string inside a quoted string. */
static char *quoted(const char *s)
{
	const int delim_len = 1;
	return strndup(s + delim_len, strlen(s) - 2*delim_len);
}

/* Copy the code inside a code snippet that is enclosed in %{ }% after
 * first stripping the space and tab characters from either end of the
 * snippet. We strip leading and trailing whitespace for Python users
 * to remain sane, since Python is sensitive to whitespace. To summarize,
 * given an input %{<space><code><space>}% we return: <code>
 */
static char *code(const char *s)
{
	const int delim_len = sizeof("%{")-1;

	const char *start = s + delim_len;
	while ((*start == ' ') || (*start == '\t'))
		++start;

	const char *end = s + (strlen(s) - 1) - delim_len;
	while ((*end == ' ') || (*end == '\t'))
		--end;

	const int code_len = end - start + 1;
	return strndup(start, code_len);
}

/* Convert a hex string prefixed by "0x" to an integer value. */
static s64 hextol(const char *s)
{
	return strtol(yytext + 2, NULL, 16);
}

%}

%{
#define YY_USER_ACTION yylloc.first_line = yylloc.last_line = yylineno;
%}
%option yylineno
%option nounput

/* A regexp for C++ comments: */
cpp_comment	\/\/[^\n]*\n

/* Here is a summary of the regexp for C comments:
 *   open-comment
 *   any number of:
 *     (non-stars) or (star then non-slash)
 *   close comment
 */
c_comment	\/\*(([^*])|(\*[^\/]))*\*\/

/* The regexp for code snippets is analogous to that for C comments.
 * Here is a summary of the regexp for code snippets:
 *   %{
 *   any number of:
 *     (non-}) or (} then non-%)
 *   }%
 */
code		\%\{(([^}])|(\}[^\%]))*\}\%

/* A regular experssion for an IP address
 * TODO(ncardwell): IPv6
 */
ip_addr		[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+

%%
sa_family		return SA_FAMILY;
sin_port		return SIN_PORT;
sin_addr		return SIN_ADDR;
msg_name		return MSG_NAME;
msg_iov			return MSG_IOV;
msg_flags		return MSG_FLAGS;
fd			return FD;
events			return EVENTS;
revents			return REVENTS;
onoff			return ONOFF;
linger			return LINGER;
htons			return _HTONS_;
icmp			return ICMP;
udp			return UDP;
inet_addr		return INET_ADDR;
ack			return ACK;
eol			return EOL;
ecr			return ECR;
mss			return MSS;
mtu			return MTU;
nop			return NOP;
sack			return SACK;
sackOK			return SACKOK;
TS			return TIMESTAMP;
FO			return FAST_OPEN;
val			return VAL;
win			return WIN;
wscale			return WSCALE;
ect01			return ECT01;
ect0			return ECT0;
ect1			return ECT1;
noecn			return NO_ECN;
ce			return CE;
[.][.][.]		return ELLIPSIS;
--[a-zA-Z0-9_]+		yylval.string	= option(yytext); return OPTION;
[-]?[0-9]*[.][0-9]+	yylval.floating	= atof(yytext);   return FLOAT;
[-]?[0-9]+		yylval.integer	= atoll(yytext);  return INTEGER;
0x[0-9]+		yylval.integer	= hextol(yytext); return HEX_INTEGER;
[a-zA-Z0-9_]+		yylval.string	= strdup(yytext); return WORD;
\"(\\.|[^"])*\"		yylval.string	= quoted(yytext); return STRING;
\`(\\.|[^`])*\`		yylval.string	= quoted(yytext); return BACK_QUOTED;
[^ \t\n]		return (int) yytext[0];
[ \t\n]+		/* ignore whitespace */;
{cpp_comment}		/* ignore C++-style comment */;
{c_comment}		/* ignore C-style comment */;
{code}			yylval.string = code(yytext);   return CODE;
{ip_addr}		yylval.string = strdup(yytext); return IP_ADDR;
%%
