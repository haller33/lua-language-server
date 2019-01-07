local re = require 'parser.relabel'
local m = require 'lpeglabel'


local scriptBuf = ''
local compiled = {}
local parser

local RESERVED = {
    ['and']      = true,
    ['break']    = true,
    ['do']       = true,
    ['else']     = true,
    ['elseif']   = true,
    ['end']      = true,
    ['false']    = true,
    ['for']      = true,
    ['function'] = true,
    ['goto']     = true,
    ['if']       = true,
    ['in']       = true,
    ['local']    = true,
    ['nil']      = true,
    ['not']      = true,
    ['or']       = true,
    ['repeat']   = true,
    ['return']   = true,
    ['then']     = true,
    ['true']     = true,
    ['until']    = true,
    ['while']    = true,
}

local defs = setmetatable({}, {__index = function (self, key)
    self[key] = function (...)
        if parser[key] then
            return parser[key](...)
        end
    end
    return self[key]
end})

defs.nl = (m.P'\r\n' + m.S'\r\n') / function ()
    if parser.nl then
        return parser.nl()
    end
end
defs.s  = m.S' \t'
defs.S  = - defs.s
defs.ea = '\a'
defs.eb = '\b'
defs.ef = '\f'
defs.en = '\n'
defs.er = '\r'
defs.et = '\t'
defs.ev = '\v'
defs['nil'] = m.Cp() / function () return nil end
defs.NotReserved = function (_, _, str)
    if RESERVED[str] then
        return false
    end
    return true, str
end
defs.Reserved = function (_, _, str)
    if RESERVED[str] then
        return true
    end
    return false
end
defs.np = m.Cp() / function (n) return n+1 end

local eof = re.compile '!. / %{SYNTAX_ERROR}'

local function grammar(tag)
    return function (script)
        scriptBuf = script .. '\r\n' .. scriptBuf
        compiled[tag] = re.compile(scriptBuf, defs) * eof
    end
end

local function errorpos(pos, err)
    return {
        type = 'UNKNOWN',
        start = pos or 0,
        finish = pos or 0,
        err = err,
    }
end

grammar 'Comment' [[
Comment         <-  '--' (LongComment / ShortComment)
LongComment     <-  '[' {:eq: '='* :} '[' CommentClose
CommentClose    <-  ']' =eq ']' / . CommentClose
ShortComment    <-  (!%nl .)*
]]

grammar 'Sp' [[
Sp  <-  (Comment / %nl / %s)*
Sps <-  (Comment / %nl / %s)+
]]

grammar 'Common' [[
Word        <-  [a-zA-Z0-9_]
Cut         <-  !Word
X16         <-  [a-fA-F0-9]
Rest        <-  (!%nl .)*

AND         <-  Sp {'and'}    Cut
BREAK       <-  Sp 'break'    Cut
DO          <-  Sp 'do'       Cut
ELSE        <-  Sp 'else'     Cut
ELSEIF      <-  Sp 'elseif'   Cut
END         <-  Sp 'end'      Cut
FALSE       <-  Sp 'false'    Cut
FOR         <-  Sp 'for'      Cut
FUNCTION    <-  Sp 'function' Cut
GOTO        <-  Sp 'goto'     Cut
IF          <-  Sp 'if'       Cut
IN          <-  Sp 'in'       Cut
LOCAL       <-  Sp 'local'    Cut
NIL         <-  Sp 'nil'      Cut
NOT         <-  Sp 'not'      Cut
OR          <-  Sp {'or'}     Cut
REPEAT      <-  Sp 'repeat'   Cut
RETURN      <-  Sp 'return'   Cut
THEN        <-  Sp 'then'     Cut
TRUE        <-  Sp 'true'     Cut
UNTIL       <-  Sp 'until'    Cut
WHILE       <-  Sp 'while'    Cut

Esc         <-  '\' -> ''
                EChar
EChar       <-  'a' -> ea
            /   'b' -> eb
            /   'f' -> ef
            /   'n' -> en
            /   'r' -> er
            /   't' -> et
            /   'v' -> ev
            /   '\'
            /   '"'
            /   "'"
            /   %nl
            /   ('z' (%nl / %s)*)       -> ''
            /   ('x' {X16 X16})         -> Char16
            /   ([0-9] [0-9]? [0-9]?)   -> Char10
            /   ('u{' {} {Word*} '}')   -> CharUtf8
            -- 错误处理
            /   'x' {}                  -> MissEscX
            /   'u' !'{' {}             -> MissTL
            /   'u{' Word* !'}' {}      -> MissTR
            /   {}                      -> ErrEsc

Comp        <-  Sp {CompList}
CompList    <-  '<='
            /   '>='
            /   '<'
            /   '>'
            /   '~='
            /   '=='
BOR         <-  Sp {'|'}
BXOR        <-  Sp {'~'} !'='
BAND        <-  Sp {'&'}
Bshift      <-  Sp {BshiftList}
BshiftList  <-  '<<'
            /   '>>'
Concat      <-  Sp {'..'}
Adds        <-  Sp {AddsList}
AddsList    <-  '+'
            /   '-'
Muls        <-  Sp {MulsList}
MulsList    <-  '*'
            /   '//'
            /   '/'
            /   '%'
Unary       <-  Sp {} {UnaryList}
UnaryList   <-  NOT
            /   '#'
            /   '-'
            /   '~' !'='
POWER       <-  Sp {'^'}

PL          <-  Sp '('
PR          <-  Sp ')'
BL          <-  Sp '['
BR          <-  Sp ']'
TL          <-  Sp '{'
TR          <-  Sp '}'
COMMA       <-  Sp ','
SEMICOLON   <-  Sp ';'
DOTS        <-  Sp ({} '...') -> DOTS
DOT         <-  Sp ({} '.' !'.') -> DOT
COLON       <-  Sp ({} ':' !':') -> COLON
LABEL       <-  Sp '::'
ASSIGN      <-  Sp '='

Nothing     <-  {} -> Nothing

TOCLOSE     <-  Sp '*toclose'

DirtyAssign <-  ASSIGN / {} -> MissAssign
DirtyBR     <-  BR {} / {} -> MissBR
DirtyTR     <-  TR {} / {} -> MissTR
DirtyPR     <-  PR {} / {} -> DirtyPR
DirtyLabel  <-  LABEL / {} -> MissLabel
MaybePR     <-  PR    / {} -> MissPR
MaybeEnd    <-  END   / {} -> MissEnd
]]

grammar 'Nil' [[
Nil         <-  Sp ({} -> Nil) NIL
]]

grammar 'Boolean' [[
Boolean     <-  Sp ({} -> True)  TRUE
            /   Sp ({} -> False) FALSE
]]

grammar 'String' [[
String      <-  Sp ({} StringDef {})
            ->  String
StringDef   <-  '"'
                {~(Esc / !%nl !'"' .)*~} -> 1
                ('"' / {} -> MissQuote1)
            /   "'"
                {~(Esc / !%nl !"'" .)*~} -> 1
                ("'" / {} -> MissQuote2)
            /   ('[' {} {:eq: '='* :} {} '['
                {(!StringClose .)*} -> 1
                (StringClose / {}))
            ->  LongString
StringClose <-  ']' =eq ']'
]]

grammar 'Number' [[
Number      <-  Sp ({} {NumberDef} {}) -> Number
                ErrNumber?
NumberDef   <-  Number16 / Number10
ErrNumber   <-  ({} {([0-9a-zA-Z] / '.')+})
            ->  UnknownSymbol

Number10    <-  Float10 Float10Exp?
            /   Integer10 Float10? Float10Exp?
Integer10   <-  [0-9]+ '.'? [0-9]*
Float10     <-  '.' [0-9]+
Float10Exp  <-  [eE] [+-]? [0-9]+
            /   ({} [eE] [+-]? {}) -> MissExponent

Number16    <-  '0' [xX] Float16 Float16Exp?
            /   '0' [xX] Integer16 Float16? Float16Exp?
Integer16   <-  X16+ '.'? X16*
            /   ({} {Word*}) -> MustX16
Float16     <-  '.' X16+
            /   '.' ({} {Word*}) -> MustX16
Float16Exp  <-  [pP] [+-]? [0-9]+
            /   ({} [pP] [+-]? {}) -> MissExponent
]]

grammar 'Name' [[
Name        <-  Sp ({} NameBody {})
            ->  Name
NameBody    <-  {[a-zA-Z_] [a-zA-Z0-9_]*}
FreeName    <-  Sp ({} NameBody=>NotReserved {})
            ->  Name
MustName    <-  Name / DirtyName
DirtyName   <-  {} -> DirtyName
]]

grammar 'Exp' [[
Exp         <-  Sp ExpOr
ExpOr       <-  (ExpAnd     SuffixOr*)     -> Binary
ExpAnd      <-  (ExpCompare SuffixAnd*)    -> Binary
ExpCompare  <-  (ExpBor     SuffixComp*)   -> Binary
ExpBor      <-  (ExpBxor    SuffixBor*)    -> Binary
ExpBxor     <-  (ExpBand    SuffixBxor*)   -> Binary
ExpBand     <-  (ExpBshift  SuffixBand*)   -> Binary
ExpBshift   <-  (ExpConcat  SuffixBshift*) -> Binary
ExpConcat   <-  (ExpAdds    SuffixConcat*) -> Binary
ExpAdds     <-  (ExpMuls    SuffixAdds*)   -> Binary
ExpMuls     <-  (ExpUnary   SuffixMuls*)   -> Binary
ExpUnary    <-  (           SuffixUnary)   -> Unary
            /   ExpPower
ExpPower    <-  (ExpUnit    SuffixPower*)  -> Binary

SuffixOr    <-  OR     (ExpAnd     / {} -> DirtyExp)
SuffixAnd   <-  AND    (ExpCompare / {} -> DirtyExp)
SuffixComp  <-  Comp   (ExpBor     / {} -> DirtyExp)
SuffixBor   <-  BOR    (ExpBxor    / {} -> DirtyExp)
SuffixBxor  <-  BXOR   (ExpBand    / {} -> DirtyExp)
SuffixBand  <-  BAND   (ExpBshift  / {} -> DirtyExp)
SuffixBshift<-  Bshift (ExpConcat  / {} -> DirtyExp)
SuffixConcat<-  Concat (ExpConcat  / {} -> DirtyExp)
SuffixAdds  <-  Adds   (ExpMuls    / {} -> DirtyExp)
SuffixMuls  <-  Muls   (ExpUnary   / {} -> DirtyExp)
SuffixUnary <-  Unary+ (ExpPower   / {} -> DirtyExp)
SuffixPower <-  POWER  (ExpUnary   / {} -> DirtyExp)

ExpUnit     <-  Nil
            /   Boolean
            /   String
            /   Number
            /   DOTS
            /   Table
            /   Function
            /   Simple

Simple      <-  (Prefix (Sp Suffix)*)
            ->  Simple
Prefix      <-  Sp ({} PL DirtyExp DirtyPR)
            ->  Prefix
            /   FreeName
Suffix      <-  DOT   Name / DOT   {} -> MissField
            /   Method (!PL {} -> MissPL)?
            /   ({} Table {}) -> Call
            /   ({} String {}) -> Call
            /   ({} BL DirtyExp DirtyBR) -> Index
            /   ({} PL CallArgList DirtyPR) -> Call
Method      <-  COLON Name / COLON {} -> MissMethod

DirtyExp    <-  Exp
            /   {} -> DirtyExp
MaybeExp    <-  Exp / MissExp
MissExp     <-  {} -> MissExp
ExpList     <-  Sp (MaybeExp (COMMA (MaybeExp))*)
            ->  List
MustExpList <-  Sp (Exp      (COMMA (MaybeExp))*)
            ->  List
CallArgList <-  Sp ({} (COMMA {} / Exp)+ {})
            ->  CallArgList
            /   %nil
NameList    <-  (MustName (COMMA MustName)*)
            ->  List

ArgList     <-  (DOTS / Name / Sp {} COMMA)*
            ->  ArgList

Table       <-  Sp ({} TL TableFields? DirtyTR)
            ->  Table
TableFields <-  (TableSep {} / TableField)+
TableSep    <-  COMMA / SEMICOLON
TableField  <-  NewIndex / NewField / Exp
NewIndex    <-  Sp ({} BL !BL !ASSIGN DirtyExp DirtyBR DirtyAssign DirtyExp)
            ->  NewIndex
NewField    <-  (MustName ASSIGN DirtyExp)
            ->  NewField

Function    <-  Sp ({} FunctionBody {})
            ->  Function
FuncArg     <-  PL ArgList MaybePR
            /   {} -> MissPL Nothing
FunctionBody<-  FUNCTION FuncArg
                    (!END Action)*
                MaybeEnd

-- 纯占位，修改了 `relabel.lua` 使重复定义不抛错
Action      <-  !END .
Set         <-  END
]]

grammar 'Action' [[
Action      <-  Sp (CrtAction / UnkAction)
CrtAction   <-  Semicolon
            /   Do
            /   Break
            /   Return
            /   Label
            /   GoTo
            /   If
            /   For
            /   While
            /   Repeat
            /   NamedFunction
            /   LocalFunction
            /   Local
            /   Set
            /   Call
            /   Exp
UnkAction   <-  ({} {Word+})
            ->  UnknownSymbol
            /   ({} {. (!Sps !CrtAction .)*})
            ->  UnknownSymbol

Semicolon   <-  SEMICOLON
            ->  Skip
SimpleList  <-  (Simple (COMMA Simple)*)
            ->  List

Do          <-  Sp ({} DO DoBody MaybeEnd {})
            ->  Do
DoBody      <-  (!END Action)*
            ->  DoBody

Break       <-  BREAK
            ->  Break

Return      <-  RETURN MustExpList?
            ->  Return

Label       <-  LABEL MustName -> Label DirtyLabel

GoTo        <-  GOTO MustName -> GoTo

If          <-  Sp ({} IfBody {})
            ->  If
IfHead      <-  (IfPart     -> IfBlock)
            /   (ElseIfPart -> ElseIfBlock)
            /   (ElsePart   -> ElseBlock)
IfBody      <-  IfHead
                (ElseIfPart -> ElseIfBlock)*
                (ElsePart   -> ElseBlock)?
                MaybeEnd
IfPart      <-  IF Exp THEN
                    {} (!ELSEIF !ELSE !END Action)* {}
            /   IF DirtyExp THEN
                    {} (!ELSEIF !ELSE !END Action)* {}
            /   IF DirtyExp
                    {}         {}
ElseIfPart  <-  ELSEIF Exp THEN
                    {} (!ELSE !ELSEIF !END Action)* {}
            /   ELSEIF DirtyExp THEN
                    {} (!ELSE !ELSEIF !END Action)* {}
            /   ELSEIF DirtyExp
                    {}         {}
ElsePart    <-  ELSE
                    {} (!END Action)* {}

For         <-  Loop / In
            /   FOR

Loop        <-  Sp ({} LoopBody {})
            ->  Loop
LoopBody    <-  FOR LoopStart LoopFinish LoopStep DO?
                    (!END Action)*
                MaybeEnd
LoopStart   <-  MustName ASSIGN DirtyExp
LoopFinish  <-  COMMA? Exp
            /   COMMA? DirtyName
LoopStep    <-  COMMA  DirtyExp
            /   COMMA? Exp
            /   Nothing

In          <-  Sp ({} InBody {})
            ->  In
InBody      <-  FOR NameList IN? ExpList DO?
                    (!END Action)*
                MaybeEnd

While       <-  Sp ({} WhileBody {})
            ->  While
WhileBody   <-  WHILE Exp DO
                    (!END Action)*
                MaybeEnd

Repeat      <-  Sp ({} RepeatBody {})
            ->  Repeat
RepeatBody  <-  REPEAT
                    (!UNTIL Action)*
                UNTIL Exp

Local       <-  (LOCAL TOCLOSE? NameList (ASSIGN ExpList)?)
            ->  Local
Set         <-  (SimpleList ASSIGN ExpList?)
            ->  Set

Call        <-  Simple

LocalFunction
            <-  Sp ({} LOCAL FunctionNamedBody {})
            ->  LocalFunction

NamedFunction
            <-  Sp ({} FunctionNamedBody {})
            ->  NamedFunction
FunctionNamedBody
            <-  FUNCTION FuncName FuncArg
                    (!END Action)*
                MaybeEnd
FuncName    <-  (MustName (DOT MustName)* FuncMethod?)
            ->  Simple
FuncMethod  <-  COLON Name / COLON {} -> MissMethod
]]

grammar 'Lua' [[
Lua         <-  Head? Action* -> Lua Sp
Head        <-  '#' (!%nl .)*
]]

return function (lua, mode, parser_)
    parser = parser_ or {}
    local gram = compiled[mode] or compiled['Lua']
    local r, _, pos = gram:match(lua)
    if not r then
        local err = errorpos(pos)
        return nil, err
    end

    return r
end
