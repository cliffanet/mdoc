#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;

# ----------------------------------------------------------------------
my $p = arg();

my $txt = Txt->fromfile($p->{file}->[0])
    || err('Can\'t open file "%s": %s', $p->{file}->[0], $!);

my $yaml = yaml($txt) || err($!);


use Data::Dumper;
print Dumper $yaml, $txt, $p;

# ----------------------------------------------------------------------
# ---
# ---   Error
# ---

sub usage {
    my $s = shift();

    print "$s\n" if defined($s);
    print "\n" if $s;

    print "Usage:
    $0 [options] source destination

Options:
    -h, --help      This usage message

    -t, --type      Out type format (doc, pdf, html)

";
    exit defined($s) ? -1 : ();
}

sub err {
    my $s = shift;
    $s = $s->err if ref($s) eq 'TxtParser';
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
    my $h;

    GetOptions(
        'help+'     => \$h,
        'type=s'    => \$r->{type},
        '<>'        => sub { push @{ $r->{file}||=[] }, shift(); },
    ) || return usage('');
    return usage() if $h;
    return usage('Not defined source file') if !$r->{file};

    return $r;
}


# ----------------------------------------------------------------------
# ---
# ---   YAML
# ---

sub yaml {
    my $txt = $_[0]->copy();

    $txt->skipempty();
    $txt->fetchln(qr/^\s*\-{3}/) || return {};
    $_[0] = $txt;

    my $yaml = {};
    my @cur = { space => 0, data => $yaml };

    while (my ($s) = $txt->fetchln()) {
        # просто стираем пустые строки
        $s->empty() && next;
        # проверка на окончание yaml
        $s->match(qr/^\-{3}/) && last;

        # Строки переносим в @yaml
        my (undef, $space, $key, $val) = $s->match(qr/^(\s*)([a-zA-Z]+[a-zA-Z \-\d]+)\s*(?:\:\s*)(.*)?/);
        $val || last;

        # сначала разбираемся с уровнем вложенности
        $space->{len} += 3 while $space->{str} =~ s/\t//;
        $space = $space->{len};
        pop(@cur) while (@cur > 1) && ($cur[@cur-1]->{space} > $space);
        my $c = $cur[@cur-1];

        if ($space > $c->{space}) {
            my $k = $c->{key} || return $key->err('YAML: Deeper level without key');
            my $d = ( $c->{data}->{ $k } = {} );
            push @cur, { space => $space, data => $d };
            $c = $cur[@cur-1];
        }

        my $d = $c->{data};

        # key
        if (exists $d->{ $key->{str} }) {
            return $key->err('YAML: Duplicate key: %s', $key->{str});
        }
        $key = $key->{str};

        if ($val->empty()) {
            $c->{key} = $key;
        }
        else {
            delete $c->{key};

            if (my (undef, $v1) = $val->match(qr/^\"((\\.|[^\\\"]+)*)\"\s*$/)) {
                $val = $v1;
            }
            elsif ($val->match(qr/^\"/)) {
                return $val->err('YAML: Not-correct string value');
            }
            elsif ($val->match(qr/^\-?\d$/)) {
                $val->{str} = int $val->{str};
            }
        }

        $d->{ $key } = $val->{str};
    }

    return $yaml;
}

# ----------------------------------------------------------------------
# ---
# ---   Txt
# ---

package Txt;

sub new {
    my $class = shift;
    my $txt = [@_];

    my $r = 0;
    foreach (@$txt) {
        $r++;
        s/[\r\n]+//;
        $_ = Str->new($_, row => $r, col => 1);
    }

    return bless $txt, $class;
}

sub fromfile {
    my $class = shift;

    open(my $fh, shift()) || return;
    my $txt = $class->new( <$fh> );
    close $fh;

    return $txt;
}

sub copy {
    my $txt = shift;

    return bless [ @$txt ], ref($txt);
}

sub skipempty {
    my $txt = shift;

    my $n = 0;
    while (@$txt && $txt->[0]->empty(@_)) {
        shift @$txt;
        $n ++;
    }

    return $n;
}

sub fetchln {
    my $txt = shift;

    my $s = shift(@$txt) || return;
    return @_ ? $s->match(@_) : $s;
}

# ----------------------------------------------------------------------
# ---
# ---   Str
# ---

package Str;

sub new {
    my $class = shift;
    my $s = shift;
    return bless { @_, str => $s, len => length($s) }, $class;
}

sub err {
    my $s = shift;

    if (@_) {
        $s->{err} = shift;
        $s->{err} = sprintf($s->{err}, @_) if @_;
        $! = $s->err;

        return;
    }

    $s->{row} || return $s->{err}||'';

    return sprintf('[row: %d, col: %d] %s', $s->{row}, $s->{col}, $s->{err}||'');
}

sub match {
    my ($s, $regex) = @_;

    defined( $s->{str} ) || return;
    my @r = ($s->{str} =~ /($regex)/);

    foreach my $r (@r) {
        $r = Str->new(
                $r,
                row => $s->{row},
                col => $s->{col} + index($s->{str}, $r)
            );
    }

    return @r;
}

sub empty {
    my ($s, $nospace) = @_;

    defined( $s->{str} ) || return 1;
    return $nospace ? ($s->{str} eq '') : ($s->{str} =~ /^\s*$/);
}

1;
