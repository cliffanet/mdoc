#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;
use Cwd qw(abs_path);

my @lib;
BEGIN {
    @lib = $0;
    $lib[0] =~ s/\/?[^\/\\]+$//;
    unshift @lib, $lib[0].'/lib';
}
use lib @lib;
use txt;
use prs;

# ----------------------------------------------------------------------
my $p = arg();

my $s = txt->fromfile($p->{src})
    || err('Can\'t read file \'%s\': %s', $p->{src}, $!);

my $yaml = yaml($s) || exit -1;

my $cont = prs::doc($s) || err(prs::err);

#use Data::Dumper;
#print Dumper $yaml, $cont;

my $out = 'out::' . $p->{type};
$out = $out->new(%$yaml, %$p);
$out->make(@$cont);
$out->save($p->{dst}) || err('Can\'t save to \'%s\': %s', $p->{dst}, $!);

# ----------------------------------------------------------------------
# ---
# ---   Error
# ---

sub usage {
    my $s = shift();

    $s = sprintf($s, @_) if @_;
    print "$s\n" if defined($s);
    print "\n" if $s;

    print "Usage:
    $0 [options] source destination

Options:
    -h, --help      This usage message

    -t, --type      Out type format (doc, pdf, html)

    -r, --root-dir  Work directory for including files

    -b, --base-uri  Base-prefix for relative links

";
    exit defined($s) ? -1 : ();
}

sub err {
    my $s = shift;
    if (ref($s) eq 'txt::posinf') {
        my $pos = $s;
        $s = sprintf '[ln: %d, col: %d] %s', $pos->{row}, $pos->{col}, shift();
    }
    $s = sprintf($s, @_) if @_;
    print STDERR $s."\n";
    exit -1;
}

# ----------------------------------------------------------------------

# ---
# ---   Arguments
# ---

sub arg {
    my $r = {};
    my ($h, $t, $root, $baseuri, @file);

    GetOptions(
        'help'          => \$h,
        'type=s'        => \$t,
        'root-dir=s'    => \$root,
        'base-uri=s'    => \$baseuri,
        '<>'            => sub { push @file, shift(); },
    ) || return usage('');
    return usage() if $h;

    ($r->{src}, $r->{dst}, @file) = @file;
    $r->{src} ||
        return usage('Not defined source file');
    $r->{dst} ||
        return usage('Not defined destination file');
    @file &&
        return usage('Too many defined files');
    
    if ($t) {
        $r->{type} = $t;
    }
    else {
        ($r->{dst} =~ /\.([a-z]{2,5})$/i) ||
            return usage('Can\'t check type of destination file');

        $r->{type} = lc $1;
    }
    eval("require out::$r->{type};") ||
        return usage('Type \'%s\' of destination file not found: %s', $r->{type}, $@);
    
    if ($root) {
        $r->{root} = abs_path($root) ||
            return usage('Work directory fail: %s', $root);
    }
    else {
        my $path = abs_path($r->{src});
        if ($path && ($path =~ s/\/[^\/]+$//)) {
            $r->{root} = $path;
        }
    }

    $r->{'base-uri'} = $baseuri if $baseuri;

    return $r;
}


# ----------------------------------------------------------------------
# ---
# ---   YAML
# ---

sub yaml {
    my @s = $_[0];
    my @yaml = ();

    while (@s) {
        # вложенный блок закончился переходим уровнем выше
        if ($s[0]->empty()) {
            (@s > 1) || last;
            shift @s;
            shift @yaml;
            next;
        }

        # Берём первую строку из текста
        my ($ln, $tail) = $s[0]->line(1);
        $s[0] = $tail;

        # Пустые строки просто пропускаем
        $ln->empty() && next;

        # проверка на начало/окончание yaml
        if ( (@s == 1) && $ln->match(qr/\-{3}/) ) {
            @yaml && last;      # достигли конца yaml-блока
            @yaml = {};         # это только начало yaml
            next;
        }

        # если в этом месте @yaml пуст, значит встретился какой-то текст до начала yaml-блока
        # это значит, что в этом файле нет yaml-блока
        my ($y) = $yaml[0] || return {};

        my (undef, $val, $par) = $ln->match(qr/(?:\s*)([a-zA-Z]+[a-zA-Z \-\d]+)\s*(?:\:\s*)/);
        $par                || return err($ln->{pos}, 'YAML: synthax error');
        my $p = $par->{txt};
        exists($y->{ $p })  && return err($par->{pos}, 'YAML: Duplicate key: %s', $p);

        if (my ($ind, $t) = $tail->indent(qr/(?: {1,4}| {0,3}\t)/, 1)) {
            # Если после параметра есть вложенный подблок,
            # возьмём его весь для дальнейшего парсинга уровнем ниже
            $s[0] = $t;
            unshift @s, $ind;
            unshift @yaml, $y->{ $p } = {};
            next;
        }

        # Если это обычный параметр без вложенного подблока, то просто присвоим значение
        if (my (undef, undef, $v1) = $val->match(qr/\"((\\.|[^\\\"]+)*)\"\s*$/)) {
            $val = $v1;
        }
        elsif ($val->match(qr/\"/)) {
            return $val->err('YAML: Not-correct string value');
        }
        elsif ($val->match(qr/\-?\d+\s*$/)) {
            $val->{txt} = int $val->{txt};
        }
        elsif ($val->match(qr/false\s*$/)) {
            $val->{txt} = 0;
        }
        $y->{ $p } = $val->{txt};
    }

    if (my ($s) = reverse @s) {
        $_[0] = $s;
    }

    my $yaml = (reverse @yaml)[0] || {};

    foreach my $k (qw/geometry/) {
        my $v = $yaml->{$k} || next;
        my @v = split /\s+/, $v;
        $v = ($yaml->{$k} = {});
        foreach (@v) {
            my ($k1, $v1) = split /\=/, $_, 2;
            $v->{$k1} = $v1;
        }
    }

    return $yaml;
}

1;
