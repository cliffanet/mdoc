#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;
use prs;
use txt;

my $src = <<'MARKDOWN';
Default.

\right

> Quote.

\center

- [ ] Task.

\justify

| Explicit | Default |
| :------- | ------- |
| Left     | Justify |

\vcenter
\toc
\pagebreak
\right

Combined.

\left

[^note]: Footnote.

Reference[^note].

\right
MARKDOWN

my $doc = prs::doc(txt->new($src));
ok(ref($doc) eq 'ARRAY', 'alignment document parses');

my @mod = map { $_->{name} }
    grep { ($_->{type} || '') eq 'modifier' } @$doc;
is_deeply(
    \@mod,
    [qw(right center justify vcenter toc pagebreak right left right)],
    'all alignment modifiers remain in source order'
);

my @text = grep { ($_->{type} || '') eq 'text' } @$doc;
is($text[0]->{align}, 'l', 'document starts with left alignment');
is($text[-1]->{align}, 'l', 'footnote definition does not change document alignment');

my ($quote) = grep { ($_->{type} || '') eq 'quote' } @$doc;
is($quote->{content}->[0]->{align}, 'r', 'quote paragraph inherits alignment');

my ($list) = grep { ($_->{type} || '') eq 'list' } @$doc;
my $item = $list->{content}->[0];
is($item->{content}->[0]->{align}, 'c', 'task paragraph inherits alignment');

my ($table) = grep { ($_->{type} || '') eq 'table' } @$doc;
is_deeply($table->{align}, ['l', 'j'], 'explicit table alignment overrides document state');

my ($combined) = grep { ($_->{valign} || '') eq 'c' } @text;
is($combined->{align}, 'r', 'vcenter ignores intervening modifiers and keeps waiting for text');

my ($fndef) = grep { ($_->{type} || '') eq 'fndef' } @$doc;
ok(!exists($fndef->{content}->[0]->{align}), 'footnote paragraph does not inherit alignment');

done_testing();
