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

# Печатает сообщение об ошибке (если оно передано), справку по запуску
# и завершает программу. Без сообщения используется для обычного --help.
sub usage {
    my $s = shift();

    $s = sprintf($s, @_) if @_;
    print "$s\n" if defined($s);
    print "\n" if $s;

    print "Usage:
    $0 [options] source destination

Options:
    -h, --help          This usage message

    -t, --type          Out type format (doc, pdf, html)

    -r, --root-dir      Work directory for including files

    -b, --base-uri      Base-prefix for relative links

    --lnk-fmt           Replace .md in anchored links with output format
    --no-lnk-fmt        Preserve .md in anchored links

    --toc-noh1          Exclude H1 headings from table of contents
    --no-toc-noh1       Include H1 headings in table of contents
    --toc-hmax=N        Maximum heading level in table of contents (1-6)

    --page-number       Print page numbers in PDF
    --no-page-number    Disable page numbers

";
    exit defined($s) ? -1 : ();
}

# Печатает ошибку и завершает программу. Если первым аргументом передана
# позиция txt::posinf, добавляет к сообщению строку и столбец исходного файла.
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

# Разбирает параметры командной строки, проверяет набор входных аргументов
# и загружает выбранный модуль вывода. Возвращает параметры рендерера,
# включая вычисленный тип результата и рабочий каталог исходного файла.
sub arg {
    my $r = {};

    GetOptions(
        'h|help'        => sub { usage() },
        't|type=s'      => sub { $r->{type}             = $_[1] },
        'r|root-dir=s'  => sub { $r->{root}             = $_[1] },
        'b|base-uri=s'  => sub { $r->{'base-uri'}       = $_[1] if $_[1] },
        'lnk-fmt!'      => sub { $r->{'lnk-fmt'}        = $_[1] },
        'toc-noh1!'     => sub { $r->{'toc-noh1'}       = $_[1] },
        'toc-hmax=s'    => sub { $r->{'toc-hmax'}       = $_[1] },
        'page-number!'  => sub { $r->{'page-number'}    = $_[1] },
        '<>'            => sub {
            if (!exists($r->{src})) {
                $r->{src} = shift();
            }
            elsif (!exists($r->{dst})) {
                $r->{dst} = shift();
            }
            else {
                usage('Too many defined files');
            }
        },
    ) || return usage('');

    $r->{src} ||
        return usage('Not defined source file');
    $r->{dst} ||
        return usage('Not defined destination file');
    
    if (!$r->{type}) {
        ($r->{dst} =~ /\.([a-z]{2,5})$/i) ||
            return usage('Can\'t check type of destination file');

        $r->{type} = lc $1;
    }
    eval("require out::$r->{type};") ||
        return usage('Type \'%s\' of destination file not found: %s', $r->{type}, $@);
    
    if ($r->{root}) {
        $r->{root} = abs_path($r->{root}) ||
            return usage('Work directory fail: %s', $r->{root});
    }
    else {
        my $path = abs_path($r->{src});
        if ($path && ($path =~ s/\/[^\/]+$//)) {
            $r->{root} = $path;
        }
    }

    return $r;
}


# ----------------------------------------------------------------------
# ---
# ---   YAML
# ---

# Разбирает необязательный YAML-блок в начале документа. Поддерживаются
# вложенные словари, строки, целые числа и boolean; geometry дополнительно
# преобразуется в словарь значений. При успехе исходный txt-объект заменяется
# остатком документа, а функция возвращает хеш параметров.
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
        elsif ($val->match(qr/true\s*$/i)) {
            $val->{txt} = 1;
        }
        elsif ($val->match(qr/false\s*$/i)) {
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
