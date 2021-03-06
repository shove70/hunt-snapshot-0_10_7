module hunt.templates.rule;

import std.regex;
import std.exception;
import std.string;

import hunt.templates.match;

void template_engine_throw(string type, string message) {
	throw new Exception("[Template Engine exception." ~ type ~ "] " ~ message);
}

enum  Type {
	Comment,
	Condition,
	ConditionBranch,
	Expression,
	Loop,
	Main,
	String
}

enum  Delimiter {
	Comment,
	Expression,
	LineStatement,
	Statement
}

enum  Statement {
	Condition,
	Include,
	Loop
}

//the order is import
enum  Function {
	Not,
	And,
	Or,
	In,
	Equal,
	Greater,
	GreaterEqual,
	Less,
	LessEqual,
	Different,
	Callback,
	DivisibleBy,
	Even,
	First,
	Float,
	Int,
	Last,
	Length,
	Lower,
	Max,
	Min,
	Odd,
	Range,
	Result,
	Round,
	Sort,
	Upper,
	ReadJson,
	Default
}

enum  Condition {
	ElseIf,
	If,
	Else 
}

enum  Loop {
	ForListIn,
	ForMapIn
}

static this()
{
	regex_map_delimiters = [
		Delimiter.Statement :  ("\\{\\%\\s*(.+?)\\s*\\%\\}"),
		Delimiter.LineStatement: ("(?:^|\\n)## *(.+?) *(?:\\n|$)"),
		Delimiter.Expression : ("\\{\\{\\s*(.+?)\\s*\\}\\}"),
		Delimiter.Comment: ("\\{#\\s*(.*?)\\s*#\\}")
	];
}

__gshared string[Delimiter] regex_map_delimiters;

enum string[Statement] regex_map_statement_openers = [
	Statement.Loop : ("for (.+)"),
	Statement.Condition : ("if (.+)"),
	Statement.Include : ("include \"(.+)\"")
];

enum string[Statement] regex_map_statement_closers = [
	Statement.Loop : ("endfor"),
	Statement.Condition : ("endif")
];

enum string[Loop] regex_map_loop = [
	Loop.ForListIn : ("for (\\w+) in (.+)"),
	Loop.ForMapIn : ("for (\\w+),\\s*(\\w+) in (.+)")
];

enum string[Condition] regex_map_condition = [
	Condition.If : ("if (.+)"),
	Condition.ElseIf : ("else if (.+)"),
	Condition.Else : ("else")
];

string function_regex(const string name, int number_arguments) {
	string pattern = name;
	pattern ~= "(?:\\(";
	for (int i = 0; i < number_arguments; i++) {
		if (i != 0) pattern ~= ",";
		pattern ~= "(.*)";
	}
	pattern ~= "\\))";
	if (number_arguments == 0) { // Without arguments, allow to use the callback without parenthesis
		pattern ~= "?";
	}
	return "\\s*" ~ pattern ~ "\\s*";
}

enum string[Function] regex_map_functions = [
	Function.Not : "not (.+)",
	Function.And : "(.+) and (.+)",
	Function.Or : "(.+) or (.+)",
	Function.In : "(.+) in (.+)",
	Function.Equal : "(.+) == (.+)",
	Function.Greater : "(.+) > (.+)",
	Function.Less : "(.+) < (.+)",
	Function.GreaterEqual : "(.+) >= (.+)",
	Function.LessEqual : "(.+) <= (.+)",
	Function.Different : "(.+) != (.+)",
	Function.Default : function_regex("default", 2),
	Function.DivisibleBy : function_regex("divisibleBy", 2),
	Function.Even : function_regex("even", 1),
	Function.First : function_regex("first", 1),
	Function.Float : function_regex("float", 1),
	Function.Int : function_regex("int", 1),
	Function.Last : function_regex("last", 1),
	Function.Length : function_regex("length", 1),
	Function.Lower : function_regex("lower", 1),
	Function.Max : function_regex("max", 1),
	Function.Min : function_regex("min", 1),
	Function.Odd : function_regex("odd", 1),
	Function.Range : function_regex("range", 1),
	Function.Round : function_regex("round", 2),
	Function.Sort : function_regex("sort", 1),
	Function.Upper : function_regex("upper", 1),
	Function.ReadJson : "\\s*([^\\(\\)]*\\S)\\s*"
];

enum ElementNotation {
	Dot,
	Pointer
};