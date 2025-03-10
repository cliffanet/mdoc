#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long;

# ----------------------------------------------------------------------
my $p = arg();

my $txt = Txt->fromfile($p->{file}->[0]) || err();

my $yaml    = yaml($txt) || err();
my $cont    = paragraph($txt) || err();
   $cont    = txtstyle($cont);

use Data::Dumper;
print Dumper $yaml, $cont;#, $txt, $p;

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
    my ($txt, $t) = @_;

    if (!$t) {
        $t = Tree->new();
        $txt = $txt->copy();
    }

    my $level = $t->{level};

    while (@$txt) {
        $txt->skipempty();
        my $s = shift(@$txt) || last;

        my @f;
        # блоки, которые могут быть только в корне
        if (!$level && (@f = $s->match(qr/^ {0,3}\\(pagebreak)\s*$/))) {
            $t->top();
            $t->add(
                modifier =>
                name    => $f[1]->{str}
            );
        }
        elsif (!$level && (@f = $s->match(qr/^ {0,3}(\#+)\s+(.*)$/))) {
            $t->top();
            $t->add(
                header =>
                deep    => length($f[1]->{str}),
                content => [ $f[2] ]
            );
        }

        # список
        elsif (@f = $s->match(qr/^ {0,3}([\*\-]|\d+\.)\s+(.*)$/)) {
            $t->add(
                listitem =>
                $f[1]->{str} =~ /(\d+)/ ? (
                    mode    => 'ord',
                    num     => int($1)
                ) : (
                    mode    => $f[1]->{str}
                ),
                $f[1]->pos(),
                title   => [$f[2]]
            );

            if (my @sub = $txt->fetchlevel($level+1)) {
                paragraph( Txt->new(@sub), $t->down() );
            }
        }

        # горизонтальная линия
        elsif ($s->match(qr/^ {0,3}\-\-\-\s*$/)) {
            $t->add('hline');
        }

        # горизонтальная линия с текстом
        elsif (@$txt && $txt->[0]->match(qr/^ {,3}\-\-\-\s*$/)) {
            shift(@$txt);
            $t->add(
                hline =>
                title => [$s]
            );
        }

        # badge
        elsif (@f = $s->match(qr/^ {0,3}\[([^\]]+)\]\s*\:\s*(\S+)\s+(.*\S)\s*$/)) {
            shift(@$txt);
            push @{ $t->root()->{badge} ||= [] }, {
                code => $f[1]->{str},
                href => $f[2]->{str},
                title => [$f[3]->cut(qr/^[\"\']/)->cut(qr/[\"\']$/)]
            };
        }

        # таблица 1
        elsif (
                $s->match(qr/\|/) &&
                @$txt &&
                $txt->[0]->match(qr/^ {,3}\|?(\s*\:?\-+\:?\s*\|)+\s*\:?\-+\:?\s*\|?\s*$/)
            ) {
            # разбиваем на колонки
            my $split = sub { shift()->cut(qr/^\s*\|/)->cut(qr/\|\s*$/)->split(qr/\|/, @_); };
            # убираем пробелы в колонках
            my $space = sub { map { $_->cut(qr/^\s+/)->cut(qr/\s+$/) } @_; };
            # всё вместе
            my $col = sub { $space->( $split->(@_) ); };

            my @width = $split->($s);
            my $hdr = [ map { [$_] } $space->(@width) ];
            my @align = 
                map {
                    my $l = $_->match(qr/^\:/);
                    my $r = $_->match(qr/\:$/);
                    $l && $r    ? 'c' :
                    $l          ? 'l' :
                    $r          ? 'r' : ''
                }
                $col->( shift(@$txt) );
            my $rall = [];

            while (@$txt && $txt->[0]->match(qr/\|/)) {
                push @$rall, [
                    map { [$_] }
                    $col->( shift(@$txt) )
                ];
            }

            $t->add(
                table =>
                mode    => 1,
                width   => [ map { $_->{len} } @width ],
                align   => [ @align ],
                hdr     => $hdr,
                row     => $rall
            );
        }

        # таблица 2
        elsif ($s->match(qr/^ {0,3}(\-[\- ]{3,})$/)) {
            my @width = $s->split(qw/\s+/);
            my $row = [ map { [] } @width ];
            my $rall= [ $row ];

            while (my $s = shift(@$txt)) {
                if ($s->empty()) {
                    if (grep { @$_ > 0 } @$rall) {
                        $row = [ map { [] } @width ];
                        push @$rall, $row;
                    }
                    next;
                }
                if ($s->match(qr/^ {0,3}\-[\- ]*$/)) {
                    last;
                }

                my @row = @$row;
                foreach my $w (@width) {
                    my $r = shift @row;
                    my $sc = $s->substr($w->{col}-1, $w->{len}) || last;
                    next if $sc->empty();
                    push @$r, $sc->cut(qr/^\s+/)->cut(qr/\s+$/);
                }
            }

            $t->add(
                table =>
                mode    => 2,
                width   => [ map { $_->{len} } @width ],
                row     => $rall
            );
        }

        # code-блок
        elsif (@f = $s->match(qr/^ {0,3}\`\`\`(.*)$/)) {
            my $lang = $f[1]->{str};
            my $c = [];
            while (my $s = shift(@$txt)) {
                last if $s->match(qr/^ {0,3}\`\`\`/);
                push @$c, { $s->hinf() };
            }
            $t->add(
                code =>
                $lang ? (lang => $lang) : (),
                text => $c
            );
        }

        # quote-блок
        elsif (@f = $s->match(qr/^ {0,3}\>\s{,4}(.*)$/)) {
            my @txt = ($f[1]);
            while (@$txt && (@f = $txt->[0]->match(qr/^ {0,3}\>\s{,4}(.*)$/))) {
                shift @$txt;
                push @txt, $f[1];
            }
            $t->add('quote');
            paragraph( Txt->new(@txt), $t->down() );
        }
        
        # вложенный текстовый блок
        elsif ($s->level() > 0) {
            unshift @$txt, $s;
            my @txt = $txt->fetchlevel($level+1);
            pop(@txt) while @txt && $txt[@txt-1]->empty();
            $t->add(
                textblock =>
                # чтобы txtstyle() потом не начал парсить содержимое
                # этого текста, преобразуем его из Str в обычный хэш
                text => [ map { { $_->hinf() } } @txt ]
            );
        }

        # обычный текстовый блок
        else {
            my $c = [$s];
            while (my $s = shift(@$txt)) {
                last if $s->empty();
                push @$c, $s->cut(qr/^\s+/);
            }
            $t->add(
                paragraph =>
                text => $c
            );
        }
    }
    
    $_[0] = $txt;
    return $t->root()->{content};
}


# ----------------------------------------------------------------------
# ---
# ---   TxtStyle
# ---
sub _txtstyle_hash {
    my $h = shift;

    my @h = ();
    foreach my $k (keys %$h) {
        my @v = txtstyle($h->{$k});
        push @h, $k => @v > 1 ? [@v] : $v[0];
    }

    return { @h };
}

sub _txtstyle_str {
    my @str = shift;

    my @q = (
        qr/\*\*(\S(.*\S)?)\*\*/,
        sub {
            return {
                type    => 'bold',
                text    => [ _txtstyle_str($_[1]) ]
            };
        },

        qr/__(\S(.*\S)?)__/,
        sub {
            return {
                type => 'bold',
                text => [ _txtstyle_str($_[1]) ]
            };
        },

        qr/\*(\S(.*\S)?)\*/,
        sub {
            return {
                type    => 'italic',
                text    => [ _txtstyle_str($_[1]) ]
            };
        },

        qr/_(\S(.*\S)?)_/,
        sub {
            return {
                type    => 'italic',
                text    => [ _txtstyle_str($_[1]) ]
            };
        },

        qr/\`(.+?)\`/,
        sub {
            return {
                type    => 'inlinecode',
                $_[1]->hinf()
            };
        },

        qr/\!\[(.*?)\]\((.+?)(?:\s+\"(.*?)\")?\)/,
        sub {
            return {
                type    => 'image',
                url     => $_[2]->{str},
                $_[1]->{len} ?
                    (alt    => $_[1]->{str}) : (),
                $_[3] && $_[3]->{len} ?
                    (title  => $_[3]->{str}) : (),
            };
        },

        qr/\[(.+?)\]\((.+?)\)/,
        sub {
            return {
                type    => 'href',
                text    => [ _txtstyle_str($_[1]) ],
                url     => $_[2]->{str}
            };
        }
    );

    my @r = ();
    top: while (my $s = shift @str) {
        # усложняем алгоритм поиска
        # будем посимвольно перемещаться по строке слева направо
        # и на каждом шаге проверять все шаблоны.
        #
        # Это нужно, чтобы не было косяков, когда у нас один шаблон
        # оказался внутри другого шаблона, например:
        #       _You **can** combine them_
        #
        # При простом линейном прогоне всех шаблонов по строке,
        # если у нас шаблон /**bold**/ окажется первым в списке,
        # то он разделит строку на три части и шаблон /_italic_/
        # уже не сработает.
        #
        # В более сложном алгоритме мы в данном примере сначала
        # обнаружим /_italic_/ (даже если этот шаблон не первый),
        # а уже внутри найденного рекурсией будем заного искать
        # все шаблоны и найдём там: **can**
        for (my $i = 0; $i < $s->{len}; $i++) {
            my @q1 = @q;
            my $s1 = $s->substr($i);
            while (my $q = shift @q1) {
                my $get = shift @q1;
                my @m   = $s1->match(qr/^$q/);
                @m || next;
                # нашли совпадение
                # в @r отправим всё, что находится до совпадения
                if ($i > 0) {
                    push @r, $s->substr(0, $i);
                }
                # и само совпадение
                push @r, $get->(@m);
                # а в @str отправим всё, что оказалось после совпадения
                if ((my $b = $m[0]->{len}) < $s1->{len}) {
                    unshift @str, $s1->substr($b, $s1->{len}-$b);
                }

                next top;
            }
        }

        # не найдено совпадений, отправляем $s в @r как есть
        push @r, $s;
    }

    return @r;
}

sub txtstyle {
    my @r =
        map {
            ref($_) eq 'HASH' ?
                _txtstyle_hash($_) :
            ref($_) eq 'ARRAY' ?
                [ txtstyle(@$_) ] :
            ref($_) eq 'Str' ?
                _txtstyle_str($_) :
                $_;
        } @_;

    @r || return;
    return $r[0] if @r == 1;
    return @r;
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
        next if ref($_) eq 'Str';
        s/[\r\n]+//;
        $_ = Str->new($_, row => $r, col => 1);
    }

    return bless $txt, $class;
}

sub fromfile {
    my $class = shift;
    my $fname = shift;

    open(my $fh, '<:encoding(UTF-8)', $fname)
        || return Err->new('Can\'t open "%s": %s', $fname, $!);
    my $txt = $class->new( <$fh> );
    close $fh;

    return $txt;
}

sub copy {
    my $txt = shift;

    return bless [ map { $_->copy() } @$txt ], ref($txt);
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

sub fetchlevel {
    my ($txt, $level) = @_;

    my $copy = $txt->copy();
    $copy->skipempty();
    return if !@$copy || ($copy->[0]->level() < $level);

    my @r = ();
    while (@$txt) {
        my ($l, $s) = $txt->[0]->level($level);
        last if ($l < $level) && !$s->empty();
        shift @$txt;
        push @r, $s;
    }

    return @r;
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

sub copy {
    my $s = shift();

    return bless { %$s }, ref($s);
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
            $m = CORE::substr($m, $i, length($m) - $i);
        }
        $r = Str->new(
                $r,
                row => $s->{row},
                col => $s->{col} + $c
            );
    }

    return @r;
}

sub split {
    my ($s, $regex, $count) = @_;
    defined( $s->{str} ) || return;
    $regex || return $s;

    my @r = ();
    while ($s->{str} =~ /$regex/p) {
        push @r,
            Str->new(
                ${^PREMATCH},
                row => $s->{row},
                col => $s->{col}
            );
        $s = Str->new(
                ${^POSTMATCH},
                row => $s->{row},
                col => $s->{col} + length(${^PREMATCH}) + length(${^MATCH})
            );
        if (defined $count) {
            $count--;
            last if $count <= 0;
        }
    }

    return @r, $s;
}

sub substr {
    my $s = shift;
    my $c = shift;
    defined( $s->{str} ) || return;

    my $str = @_ ?
        # Если просто передавать @_ напрямую, то у CORE::substr
        # некорректно работает проверка количества аргументов
        CORE::substr($s->{str}, $c, shift) :
        CORE::substr($s->{str}, $c);
    defined( $str ) || return;

    $c += $s->{len} if $c < 0;
    $c = 0 if $c < 0;

    return Str->new(
                $str,
                row => $s->{row},
                col => $s->{col} + $c
            );
}

sub cut {
    my ($s, $regex) = @_;
    defined( $s->{str} ) || return;

    return $s if $s->{str} !~ /$regex/p;

    return
        length(${^PREMATCH}) ?
            Str->new(
                ${^PREMATCH} . ${^POSTMATCH},
                row => $s->{row},
                col => $s->{col}
            ) :
            Str->new(
                ${^POSTMATCH},
                row => $s->{row},
                col => $s->{col} + length( ${^MATCH} )
            );
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

# ----------------------------------------------------------------------
# ---
# ---   Tree
# ---

package Tree;

sub new {
    my $class = shift;

    my $root = {
        type    => 'root',
        level   => 0,
        content => [],
        @_
    };

    my $self = bless { tree => [$root] }, $class;
    $self->_upd($root);

    return $self;
}

sub root { return shift()->{tree}->[0]; }

sub add {
    my $self = shift;
    my $type = shift;

    $self->{last} = { @_, type => $type };
    push @{ $self->{node}->{content} }, $self->{last};

    return $self->{last};
}

sub _upd {
    my $self = shift;
    my $node = shift();

    $self->{node}   = $node;
    $self->{level}  = $node->{level};
    if (@{ $node->{content} }) {
        $self->{last} = $node->{content}->[ @{ $node->{content} } - 1 ];
    }
    else {
        delete $self->{last};
    }

    return $node;
}

sub up {
    my $self = shift;
    my $t = $self->{tree};
    pop(@$t) if @$t > 1;
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

    my $last = $self->{last} || return;
    $last->{content} ||= [];

    return Tree->new( %$last );
}

1;
