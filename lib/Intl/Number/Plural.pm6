unit module Plural;

use Intl::UserLanguage;
use Intl::CLDR;

grammar PluralMatcher      { ... }
class   PluralAction       { ... }
sub     get-matcher($,$,$) { ... }
class   Logic::AlwaysFalse { ... }
class   NumExt             { ... }

multi sub plural-count(
    Numeric  $number,                   #= The number whose count will be determined
            :$language = user-language, #= The language used in determining the count
            :$type     = 'cardinal'     #= The plural count type (cardinal or ordinal)
) is export {

    my $n = NumExt.new: $number;

    for <zero one two few many zero> -> $count {
        my $matcher = get-matcher($language, $count, $type);
        return $count if $matcher.check: $n;
    }

    return 'other';
}

multi sub plural-count(
    Numeric  $from,
    Numeric  $to,
            :$language = user-language, #= The language used in determining the count
) is export {

    # Figure out the count of the extremes
    my $start = plural-count $from, :$language, :type<cardinal>;
    my $end   = plural-count $to,   :$language, :type<cardinal>;

    # The relationships are precalculated as a table in CLDR
    cldr{$language}.grammar.plurals.ranges.from($start).to($end);
}

# This is currently a quick way (stolen from the old Intl::CLDR methods)
# to provide access to certain qualities of a number without recalculating.
# When RakuAST is completed, all plural rules can be merged into a single
# callable that can also handle non-Latin digits nicely.
class NumExt {
    has $.original;
    has $.n; #= absolute value
    has $.i; #= integer digits of $.n
    has $.v; #= count of visible fraction digits, with trailing zeros
    has $.w; #= count of visible fraction digits, without trailing zeros
    has $.f; #= visible fraction digits
    has $.t; #= visible fractional digits without trailing zeros
    proto method new(|c) { * }
    multi method new(Numeric $original) { samewith $original.Str }
    multi method new(Str     $original, :$language) {
        $original ~~ /^
            ('-'?)         # negative marker [0]
            ('0'*)         # leading zeros [1]
            (<[0..9]>+)    # one or more integer values [2]
            [
              '.'          #   decimal pointer
              (<[0..9]>*?) #   any number of decimals [3]
              ('0'*)       #   with trailing zeros [4]
            ]?             # decimal group is optional
        $/;
        return False unless $/; # equivalent of death
        my $n = $original.abs;
        my $i = $2.Str.Int;
        my ($f, $t, $v, $w);
        if $3 { # the decimal matched
            $f = $3.Str ~ $4.Str;
            $t = $4.Str;
            $v = $f.chars;
            $w = $t.chars;
        } else { # no integer value
            ($f, $t, $v, $w) = 0 xx 4;
        }
        self.bless(:$original, :$n, :$i, :$f, :$t, :$v, :$w);
    }
}


#| Obtains a Callable that matches a number to a particular input
sub get-matcher($lang, $count, $type) {

    state %cache;
    .return with %cache{"$type $count $lang"};

    my $cldr-form = cldr{$lang}.grammar.plurals{$type}{$count};

    %cache{"$type $count $lang"}
        = PluralMatcher.parse($cldr-form, :actions(PluralAction)).made
}


grammar PluralMatcher {
    # Rules found at http://unicode.org/reports/tr35/tr35-numbers.html#Language_Plural_Rules
    rule  TOP        { #`[<count> ':'] <or>? #`<samples> }
    rule  or         { <and>+ % 'or'  }
    rule  and        { <rel>+ % 'and' }

    proto rule rel   { * }
    rule  rel:is     { <expr> 'is' ('not'?) <value> }
    rule  rel:in     { <expr> ('not in' | 'in' | '=' | '!=') <range-list> }
    rule  rel:within { <expr>  ('not')? 'within' <range-list> }
    rule  expr       { <operand> [('mod' | '%') <value>]? }
    token operand    { <[niftvw]> }
    rule  range-list { (<range> || <value>)* % ',' }
    token range      { <value> '..' <value> }
    token value      { <[0..9]>+ }
    token dec-value  { <value> ('.' <value>)? }
}

# Always returns false, used if string is blank
class Logic::AlwaysFalse {
    method check($ -->False) {}
}

class Logic::Condition is export {
    has @!options is built;
    method check(NumExt $x) {
        return True if .check($x) for @!options;
        False;
    }
}

class Logic::And {
    has @!relations is built;
    method check(NumExt $x) {
        return False unless .check($x) for @!relations;
        return True;
    }
}

class Logic::RelationIs {
    has $.expression;
    has $.not;
    has $.value;
    method check(NumExt $x) {
        my $expression-value = $.expression.evaluate($x);
        $.not
            ?? !$.value.equals($expression-value)
            !!  $.value.equals($expression-value)
    }
}
class Logic::RelationIn {
    has      $.expression;
    has Bool $.not;
    has      @.values;
    method check(NumExt $x) {
        my $expression-value = $.expression.evaluate($x);
        $.not
            ?? !?@.values.any.in-range($expression-value)
            !!  ?@.values.any.in-range($expression-value)
    }
}

class Logic::Expression {
    has $.operand;
    has $.mod = Nil;
    method evaluate($x) {
        if $!mod {
            return $!operand.value($x) % $!mod;
        } else {
            return $!operand.value($x)
        }
    }
}
class Logic::Operand {
    has $.type;
    method value ($x) {
        given $!type {
            when 'n' { $x.n }
            when 'i' { $x.i }
            when 'v' { $x.v }
            when 'w' { $x.w }
            when 'f' { $x.f }
            when 't' { $x.t }
        }
    }
}
class Logic::SingleValue {
    has $.value;
    method equals(  $x) { $!value == $x }
    method in-range($x) { $!value == $x }
}
class Logic::RangeValue {
    has Range $.value;
    method equals(  $x) { $!value == $x }
    method in-range($x) { $x ∈ $!value}
}

class PluralAction {

    # Pass through the OR condition.
    method TOP ($/) {
        with $<or> {
            make $<or>.made
        } else {
            make Logic::AlwaysFalse.new;
        }
    }

    # Create an OR conditional
    # If there is only one element, pass through transparently.
    method or ($/) {
        when    $<and> == 1 { make $<and>.head.made }
        default             { make Logic::And.new: optios => $<and>>>.made }
    }

    # Create an AND condional
    # If there is only one element, pass through transparently.
    method and ($/) {
        when    $<rel> == 1 { make $<rel>.head.made }
        default             { make Logic::And.new: relations => $<rel>>>.made }
    }

    #method relation ($/) {
    #    make $<is-relation>.made if $<is-relation>;
    #    make $<in-relation>.made if $<in-relation>;
    #    $<within-relation>.made;
    #}

    method rel:is ($/) {
        make Logic::RelationIs.new(
            expression => $<expr>.made,
            not        => ($0.Str.starts-with('not')),
            value      => $<value>.made
            );
        make $<expr>.made ~ ($0 eq 'is' ?? ' == ' !! ' != ') ~ $<value>.made
    }
    method rel:in ($/) {
        make Logic::RelationIn.new(
            expression => $<expr>.made,
            not        => ?($0.Str.starts-with: 'not'|'!='),
            values     => $<range-list>.made
            );
    }
    method rel:within ($/) {
        # This is currently not used in any plural rules as of CLDR 38.1 (late 2020)
        # This should be implemented if it is ultimately used at some point
        die "-(not) within- has NOT been implemented for plural rules.  If not an error, implement."
    }
    method expr ($/) {
        make Logic::Expression.new( operand => $<operand>.made, mod => ($<value> ?? $<value>.Str.Int !! Nil ))
    }
    method operand ($/) {
        make Logic::Operand.new(type => $/.Str )
    }
    method range-list ($/) {
        my @values = $0.grep({$_{"value"} :exists}).map(*<value>.made);
        my @ranges = $0.grep({$_{"range"} :exists}).map(*<range>.made);
        make (|@values, |@ranges);
    }
    method range ($/) { make Logic::RangeValue.new( value => $<value>[0].Str.Int..$<value>[1].Str.Int ) }
    method value ($/) { make Logic::SingleValue.new( value => $/.Str ) }
}

