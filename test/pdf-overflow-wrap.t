#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Path qw(make_path);
use File::Spec;
use PDF::API2;
use Test::More;
use out::pdf;
use prs;
use txt;

my $out = out::pdf->new(root => $Bin);

# Разбирает inline-синтаксис и раскладывает его в указанную ширину PDF.
sub _content {
    my ($s, $w, $align) = @_;

    my %glb = ();
    my $inline = prs::inline(txt->new($s), \%glb);
    my $c = DContent->new(@$inline);
    $c->align($align) if $align;
    $c->stage2size($out);
    $c->stage3layout($w, 700);
    return $c;
}

# Собирает фрагменты текста в порядке обхода дерева после переносов.
sub _pieces {
    my $c = shift;
    my @part = ();
    $c->dncall(sub {
        my $node = shift;
        push @part, map { $_->{txt} } @{ $node->{chld} }
            if $node->isa('DTxt');
    });
    return @part;
}

# Проверяет, что все строки данного блока помещаются в ожидаемую ширину.
sub _fits {
    my ($c, $w) = @_;
    my @line = ();
    $c->dncall(sub { push @line, $_[0] if ref($_[0]) eq 'DLine' });
    return @line && !grep { $_->w(0) > $w + 0.01 } @line;
}

my $word = 'abcdefghijklmnopqrstuvwxyz' x 3;
my $plain = _content("Before $word", 100);
ok(_fits($plain, 100), 'long word fits after ordinary wrapping');
is(join('', _pieces($plain)), 'Before' . $word, 'long word keeps all characters');
is(join('', _pieces($plain->{chld}->[0])), 'Before', 'ordinary space break has priority');

my $cyr = 'сверхдлинноеслово' x 5;
my $russian = _content($cyr, 100);
ok(_fits($russian, 100), 'Cyrillic word fits');
is(join('', _pieces($russian)), $cyr, 'Cyrillic word is unchanged');

my $accent = "e\x{301}" x 30;
my $unicode = _content($accent, 30);
ok(_fits($unicode, 30), 'combining-character word fits');
is(join('', _pieces($unicode)), $accent, 'Unicode text is unchanged');
my @broken = grep { !/^(?:e\x{301})+$/ } _pieces($unicode);
is(scalar(@broken), 0, 'combining marks stay with base letters');

my $styled = _content('abcdefghijklmnopqrst**uvwxyz**abcdefghijklmnopqrst', 100);
ok(_fits($styled, 100), 'joined styled fragments fit');
is(join('', _pieces($styled)), 'abcdefghijklmnopqrst' . 'uvwxyz' . 'abcdefghijklmnopqrst',
    'styled fragments do not gain spaces');

my $escaped = _content('word\!word\!word\!word', 80);
ok(_fits($escaped, 80), 'escaped-punctuation fragments fit');
is(join('', _pieces($escaped)), 'word!word!word!word', 'escaped punctuation gains no spaces');

my $link = _content("[$word](https://example.org/long \"Подсказка\")", 100);
ok(_fits($link, 100), 'link text fits');
is(join('', _pieces($link)), $word, 'link text is unchanged');
my @href = ();
$link->dncall(sub { push @href, $_[0] if ref($_[0]) eq 'DHref' });
ok(@href > 1, 'all wrapped link parts retain link nodes');
my @wrong = grep { $_->{url} ne 'https://example.org/long' || $_->{title} ne 'Подсказка' } @href;
is(scalar(@wrong), 0, 'wrapped link parts retain destination and title');

my $code = _content("`$word`", 100);
ok(_fits($code, 100), 'inline code fits');
is(join('', _pieces($code)), $word, 'inline code is unchanged');
my @code = ();
$code->dncall(sub { push @code, $_[0] if ref($_[0]) eq 'DICode' });
ok(@code > 1, 'all code fragments retain background-rendering node');

my $quote = DQuote->new();
$quote->add(DContent->new(txt->new($word)));
$quote->stage2size($out);
$quote->stage3layout(180, 700);
ok(_fits($quote, 168), 'quote text fits after padding');

my $table = DTable->new(1, [1, 1, 1], ['l', 'l', 'l']);
$table->addrow([txt->new($word)], [txt->new('Other')], [txt->new('Other')]);
$table->stage2size($out);
$table->stage3layout(300, 700);
ok(_fits($table, 90), 'table text fits narrow cell after padding');

my $center = _content($word, 100, 'c');
ok(_fits($center, 100), 'centered text fits');
@wrong = grep { ($_->{align} || '') ne 'c' } @{ $center->{chld} };
is(scalar(@wrong), 0, 'all centered fragments keep alignment');

my $tiny = _content("e\x{301}z", 1);
is(scalar(@{ $tiny->{chld} }), 2, 'one overwide grapheme still makes progress');
is_deeply([_pieces($tiny)], ["e\x{301}", 'z'], 'overwide grapheme stays intact');

my $result = File::Spec->catdir($Bin, 'result');
make_path($result);
my $src = File::Spec->catfile($Bin, 'overflow-wrap.md');
my $pdf = File::Spec->catfile($result, 'overflow-wrap.pdf');
my $md = File::Spec->catfile($Bin, '..', 'md');
is(system($^X, $md, $src, $pdf), 0, 'overflow-wrap document converts to PDF');
my $opened = eval { PDF::API2->open($pdf) };
ok($opened, 'generated PDF opens again');
if ($opened) {
    my @ann = ();
    for my $n (1 .. $opened->pages()) {
        my $page = $opened->open_page($n);
        push @ann, @{ $page->{Annots}->val() } if $page->{Annots};
    }
    ok(@ann > 1, 'wrapped PDF link has annotations on multiple parts');
    @wrong = grep { $_->val()->{A}->{URI}->val() ne 'https://example.org/long' } @ann;
    is(scalar(@wrong), 0, 'all PDF link annotations keep the URI');
    @wrong = grep {
        my $rect = $_->val()->{Rect}->val();
        $rect->[2]->val() - $rect->[0]->val() > 227.5;
    } @ann;
    is(scalar(@wrong), 0, 'PDF link annotations fit document width');
}

done_testing();
