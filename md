#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;

# ----------------------------------------------------------------------
my $p = arg();

my $txt = Txt->fromfile($p->{file}->[0]) || err();

my $yaml    = yaml($txt) || err();
my $md      = paragraph($txt) || err();

use Data::Dumper;
print Dumper $yaml, $md;#, $txt, $p;

@$txt && err();

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
    my $s = @_ ? shift() : Err->last()->{err};
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

    $_[0] = $txt;
    return $yaml;
}


# ----------------------------------------------------------------------
# ---
# ---   Paragraph
# ---

sub paragraph {
    my $txt = $_[0]->copy();

    my $t = Tree->new();

    while (@$txt) {
        $txt->skipempty();
        my $s = shift(@$txt) || last;

        my @f;
        # блоки, которые могут быть только в корне
        if (@f = $s->match(qr/^ {0,3}\\(pagebreak)\s*$/)) {
            $t->top();
            $t->add(
                modifier =>
                name    => $f[1]->{str}
            );
            next;
        }
        if (@f = $s->match(qr/^ {0,3}(\#+)\s+(.*)$/)) {
            $t->top();
            $t->add(
                header =>
                deep    => length($f[1]->{str}),
                content => [ $f[2] ]
            );
            next;
        }

        # Остальные блоки могут иметь подвложенность
        my ($level, $s_) = $s->level($t->{level});
        # повышаем уровень до текущего
        $t->up() while $t->{level} > $level;
        $s = $s_;

        # проверяем, возможно это вложенный текстовый блок
        my ($l1, $s1) = $s->level(1);
        if ($l1 > 0) {
            my $c = [$s1];
            while (my ($s) = @$txt) {
                last if $s->empty();
                ($l1, $s1) = $s->level($t->{level} + 1);
                last if $l1 <= $t->{level};
                shift(@$txt);
                push @$c, $s1;
            }
        }

        # список
        elsif (@f = $s->match(qr/^ {0,3}([\*\-]|\d+\.?)\s+(.*)$/)) {
            if ($t->{last}->{type} ne 'list') {
                $t->add(list => list => []);
            }
            my $list = $t->{last};
            my $item = $t->down(
                item =>
                $f[1]->hinf('mode'),
                title   => [$f[2]]
            );
            push @{ $list->{list} }, $item;
        }

        else {
            # обычный текстовый блок
            my $c = [$s];
            while (my $s = shift(@$txt)) {
                last if $s->empty();
                if (@f = $s->match(qr/^(\s)\s*(\S.+)$/)) {
                    #push @$c, $f[1];
                    $s = $f[2];
                }
                push @$c, $s;
            }
            $t->add(
                paragraph =>
                content => $c
            );
        }
    }
    
    $_[0] = $txt;
    return $t->root();
}


# ----------------------------------------------------------------------
# ---
# ---   Err
# ---

package Err;

use overload
    'bool'      => sub { return; },
    'nomethod'  => sub { shift()->{err} };

my @all = ();

sub import {
    my $callpkg = caller(0);
    $callpkg = caller(1) if $callpkg eq __PACKAGE__;
    no strict 'refs';
    *{$callpkg.'::err'} = sub {
        return @_ ? __PACKAGE__->new(@_) : __PACKAGE__->last();
    };
}

sub new {
    my $class= shift;

    my $s = shift();
    $s = sprintf($s, @_) if @_;

    my $self = bless { err => $s }, $class;
    push @all, $self;

    return $self;
}

sub all { return @all; }
sub last {
    @all || return {};
    return $all[ @all-1 ];
}

sub clear { @all = (); }

sub p {
    my $self = shift;

    $self->{ shift() } = shift() while @_ > 1;
    
    return $self->{ shift() } if @_;
    return { %$self };
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
    my $fname = shift;

    open(my $fh, $fname)
        || return Err->new('Can\'t open "%s": %s', $fname, $!);
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

    if (@_) {
        @$txt || return;
        my @r = $txt->[0]->match(@_);
        @r || return;
        shift @$txt;
        return @r;
    }

    return shift @$txt;
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

    $s->{row} || return Err->new(@_);
    my $e = Err->new('[row: %d, col: %d] '.shift(), $s->{row}, $s->{col}, @_);
    $e->p($_ => $s->{$_}) foreach grep { exists $s->{$_} } qw/row col str/;

    return $e;
}

sub pos {
    my $s = shift;

    return
        map {
            exists($s->{$_}) ?
                ($_ => $s->{$_}) :
                ()
        } qw/row col/;
}

sub hinf {
    my $s = shift;
    my $f = shift() || 'str';
    return
        $f => $s->{str},
        $s->pos();
}

sub match {
    my ($s, $regex) = @_;

    defined( $s->{str} ) || return;
    my @r = ($s->{str} =~ /($regex)/p);
    my $m = ${^MATCH};
    my $c = length ${^PREMATCH};

    foreach my $r (@r) {
        my $i = index($m, $r);
        if ($i > 0) {
            $c += $i;
            $m = substr($m, $i, length($m) - $i);
        }
        $r = Str->new(
                $r,
                row => $s->{row},
                col => $s->{col} + $c
            );
    }

    return @r;
}

sub empty {
    my ($s, $nospace) = @_;

    defined( $s->{str} ) || return 1;
    return $nospace ? ($s->{str} eq '') : ($s->{str} =~ /^\s*$/);
}

sub level {
    my ($s, $max) = @_;

    my $level = 0;
    while (
            (!defined($max) || ($max > 0)) &&
            (my @s = $s->match(qr/^(    |\t)(.+)$/))
        ) {
        $level ++;
        $max -- if defined($max);
        $s = $s[2];
    }

    return ($level, $s) if wantarray;
    return $level;
}

package Tree;

sub new {
    my $class = shift;

    my $root = {
        @_,
        type    => 'root',
        level   => 0,
        list    => [],
    };

    my $self = {
        tree    => [$root],
        root    => $root,
        level   => 0,
    };

    return bless $self, $class;
}

sub root { return shift()->{tree}->[0]; }

sub add {
    my $self = shift;
    my $type = shift;

    $self->{last} = { @_, type => $type };
    push @{ $self->{node}->{list} }, $self->{last};
}

sub _upd {
    my $self = shift;
    my $node = shift();

    $self->{node}   = $node;
    $self->{level}  = $node->{level};
    if (@{ $node->{list} }) {
        $self->{last} = $node->{list}->[ @{ $node->{list} } - 1 ];
    }
    else {
        delete $self->{last};
    }

    return $node;
}

sub up {
    my $self = shift;

    my $t = $self->{tree};

    pop(@$t) while @$t > 1;

    return $self->_upd($t->[ @$t - 1 ]);
}

sub top {
    my $self = shift;
    my $node = $self->{tree}->[0];
    $self->{tree} = [ $node ];
    return $self->_upd($node);
}

sub down {
    my $self = shift;
    my $type = shift;

    my $node = {
        type    => $type,
        @_,
        level   => $self->{level} + 1,
        list    => [],
    };
    push @{ $self->{tree} }, $node;
    $self->_upd($node);

    return $node;
}

1;
