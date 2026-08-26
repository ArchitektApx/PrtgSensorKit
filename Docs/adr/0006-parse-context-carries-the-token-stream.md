# The parse context carries the token stream

`Get-PrtgDoctorAst` puts a `Tokens` field on the parse context, filled from the
`[ref]$tokens` output of `Parser::ParseFile`. No check reads it. It stays.

## Why it stays unread

The parse context exists so that a run walks the script once and every check
reads from the same answer, rather than each check parsing for itself. The token
stream is that rule applied to one field. It arrives for free from the same
`ParseFile` call that produces the AST, and a check that later needs raw tokens
finds it there instead of paying for a second pass over the script, or worse,
parsing to a second answer.

The AST does not make the token stream redundant. Comments, here-string
delimiters and the exact spelling of an operator are tokens and not nodes, so a
check about surface text has nowhere else to read from.

## Why the reason is only here

Nothing in the source says any of this. A note about what a future check might
need is a claim about the test and check roadmap, not a constraint the code
cannot show, and 0004 already settled that such notes live in these records
rather than as comments at the site.

## Consequence

A reader who greps for readers of `Tokens`, finds none, and proposes deleting the
field is answered by this file. The field is deleted only when the reason above
stops holding, which means `ParseFile` no longer yielding tokens alongside the
AST, not merely another release passing with no check reading it.
