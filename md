#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;

# ----------------------------------------------------------------------
my $p = arg();

my $s = TxtParser->fromfile($p->{file}->[0])
    || err('Can\'t open file "%s": %s', $p->{file}->[0], $!);

my $yaml = $s->getyaml()
    || err($s);


use Data::Dumper;
print Dumper $yaml, $s, $p;

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
# ---   TxtParser
# ---

package TxtParser;

sub new {
    my $class = shift;
    return bless { txt => [@_] }, $class;
}

sub fromfile {
    my $class = shift;

    open(my $fh, shift()) || return;
    my @txt = <$fh>;
    close $fh;

    s/[\r\n]+// foreach @txt;

    return $class->new(@txt);
}

sub possave {
    return TxtParser::PosSave->new(shift());
}

sub err {
    my $s = shift;

    if (@_) {
        $s->{err} = shift;
        $s->{err} = sprintf($s->{err}, @_) if @_;

        return;
    }

    $s->{row} || return $s->{err}||'';

    return sprintf('[row: %d, col: %d] %s', $s->{row}, $s->{col}, $s->{err}||'');
}

sub avail { return scalar @{ shift()->{txt}||[] }; }

sub strnext {
    my $s = shift;

    $s->avail() || return;
    $s->{row} ||= 0;
    $s->{row} ++;
    $s->{col} = 1;
    $s->{str} = shift @{ $s->{txt}||[] };
    $s->{len} = length $s->{str};

    return defined( $s->{str} );
}

sub check {
    my ($s, $regex) = @_;

    defined( $s->{str} ) || return;
    return $s->{str} =~ s/^($regex)//;
}

sub empty {
    my ($s, $nospace) = @_;

    defined( $s->{str} ) || return 1;
    return $nospace ? ($s->{str} eq '') : ($s->{str} =~ /^\s*$/);
}

sub skipempty {
    my $s = shift;

    my $n = 0;
    while ($s->empty(@_)) {
        $s->strnext();
        $n ++;
    }

    return $n;
}

sub fetch {
    my ($s, $regex) = @_;
    
    defined( $s->{str} ) || return;
    return if $s->{str} !~ s/^($regex)//;

    my $len = length $s->{str};
    $s->{col} += $s->{len} - $len;
    $s->{len} = $len;

    return [ @{^CAPTURE} ];
}

sub fetchspace {
    my $s = shift;

    my $r = 0;
    while (1) {
        my $n = 0;
        $s->fetch(qr/ /)    && ($n ++);
        $s->fetch(qr/\t/)   && ($n += 4);
        $n || last;
        $r += $n;
    }

    return $r;
}

sub getyaml {
    my $s = shift;

    $s->skipempty();
    $s->fetch(qr/\s*\-{3}/) || return {};

    my $yaml = {};
    my @cur = { space => 0, data => $yaml };

    while ($s->avail()) {
        # просто стираем пустые строки
        $s->skipempty() && next;
        # проверка на окончание yaml
        $s->fetch(qr/\-{3}/) && last;

        # Строки переносим в @yaml
        # сначала разбираемся с уровнем вложенности
        my $space = $s->fetchspace() || 0;
        pop(@cur) while (@cur > 1) && ($cur[@cur-1]->{space} > $space);
        my $c = $cur[@cur-1];

        if ($space > $c->{space}) {
            my $k = $c->{key} || return $s->err('YAML: Deeper level without key');
            my $d = ( $c->{data}->{ $k } = {} );
            push @cur, { space => $space, data => $d };
            $c = $cur[@cur-1];
        }

        my $d = $c->{data};

        # last - страховка от зацикливания
        my $p = $s->possave();
        my $r = $s->fetch(qr/(([a-zA-Z]+[a-zA-Z \-\d]+)\s*(?:\:\s*))(.*)?/) || last;
        my (undef, $f, $k, $v) = @$r;
        if (exists $d->{ $k }) {
            return $s->err('YAML: Duplicate key: %s', $k);
        }

        $v = '' if !defined($v);
        if ($v ne '') {
            delete $c->{key};

            if ($v =~ /^\"((\\.|[^\\\"]+)*)\"\s*$/) {
                $v = $1;
            }
            elsif ($v =~ /^\"/) {
                $p->{col} += length $f;
                return $s->err('YAML: Not-correct string value');
            }
            elsif ($v =~ /^\-?\d$/) {
                $v = int $v;
            }
        }
        else {
            $c->{key} = $k;
        }

        $d->{ $k } = $v;
    }

    return $yaml;
}



package TxtParser::PosSave;

sub new {
    my $class = shift;
    my $s = shift() || return;

    delete $s->{err};

    return bless {
        own => $s,
        map { exists($s->{$_}) ? ($_ => $s->{$_}) : () }
        qw/row col str len/
    }, $class;
}

sub restore {
    my $self = shift;

    my $s = delete($self->{own}) || return;
    $s->{$_} = $self->{$_} foreach grep { !ref($self->{$_}) } keys %$self;
}

DESTROY {
    my $self = shift;
    $self->restore() if ($self->{own}||{})->{err};
}
