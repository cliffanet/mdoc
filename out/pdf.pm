package out::pdf;

use strict;
use warnings;

use base 'out';

use PDF::API2;

use constant mm2pix => 2.8346904;

PDF::API2->add_to_font_path('.', './fonts', '/System/Library/Fonts', '/System/Library/Fonts/Supplemental', '/Library/Fonts', '~/Library/Fonts');

sub new {
    my $self = shift()->SUPER::new(@_);

    my $pdf = ($self->{pdf} = PDF::API2->new(compress => 0));
    my $o = $self->{opt} || {};

    if (my $s = $o->{title}) {
        $pdf->title($s);
    }
    if (my $s = $o->{author}) {
        $pdf->author($s);
    }
    {
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime(CORE::time());
        $pdf->created(
            sprintf(
                'D:%04d%02d%02d%02d%02d%02d+00\'00\'',
                $year+1900, $mon+1, $mday, $hour, $min, $sec
            )
        );
    }
    $pdf->producer('mdoc');

    my $geom = sub {
        my $v = ($o->{geometry} || {})->{'margin-' . shift()};
        $v = ($o->{geometry} || {})->{margin} if !defined($v);
        $v = shift() if !defined($v);
        return int($1 * mm2pix + .5)        if $v =~ /^([\d\.]+)mm$/i;
        return int($1 * mm2pix * 10 + .5)   if $v =~ /^([\d\.]+)cm$/i;
        return int($v + .5);
    };
    $self->{margin} = {
        left    => $geom->('left',      '2.5cm'),
        right   => $geom->('right',     '1.5cm'),
        top     => $geom->('top',       '1.5cm'),
        bottom  => $geom->('bottom',    '2.5cm'),
    };

    $self->{font} = $self->_font('Arial.ttf');
    $self->{size} = 11;
    
    $self->_page();


    my $g = $self->{page}->graphics();
    my $ff = $self->{frame};
    my ($x1,$y1, $x2,$y2) = ($ff->{x}, $ff->{y}, $ff->{x}+$ff->{w}, $ff->{y}+$ff->{h});
    $g->move($x1,$y1);
    $g->hline($x2);
    $g->move($x1,$y1);
    $g->vline($y2);
    $g->move($x2,$y2);
    $g->hline($x1);
    $g->move($x2,$y2);
    $g->vline($y1);
    $g->paint();

    use Data::Dumper;
    print Dumper [ $pdf->standard_fonts() ];
    print Dumper [ PDF::API2->font_path() ];

    return $self;
}

sub data { return shift()->{pdf}->to_string(); }

sub _page {
    my ($self, %p) = @_;

    my $page = ($self->{page} = $self->{pdf}->page());
    $page->size($p{size} || 'A4');
    my ($x, $y, $w, $h) = $page->size();

    $self->{frame} = {
        x   => $x + (($self->{margin}||{})->{left} || 0),
        y   => $y + (($self->{margin}||{})->{bottom} || 0),
        w   => $w - (($self->{margin}||{})->{left} || 0) - (($self->{margin}||{})->{right} || 0),
        h   => $h - (($self->{margin}||{})->{bottom} || 0) - (($self->{margin}||{})->{top} || 0),
    };
    $self->{first} = 1;

    return $page;
}

sub _parindent {
    my ($self, $indent, $contr) = @_;

    my $ff = $self->{frame};
    if (!delete($self->{first})) {
        $ff->{h} -= $indent;
    }
    elsif ($contr) {
        $ff->{h} += $contr;
    }
}

sub _font {
    my ($self, $name) = @_;
    
    my $fall = ($self->{fontall} ||= {});

    return $fall->{ $name } ||= $self->{pdf}->font($name);
}

sub header {
    my ($self, %p) = @_;

    my @level = (
        {
            size    => 22,
            vindent => 12,
            vcontr  => 10,
        }, {
            size    => 18,
            vindent => 10,
            vcontr  => 7,
        }, {
            size    => 14,
            vindent => 8,
            vcontr  => 5,
        }, {
            size    => 12,
            vindent => 8,
            vcontr  => 5,
        }, {
            size    => 11,
            vindent => 8,
            vcontr  => 5,
        },
    );
    my $p = ($p{deep} > 0) && ($p{deep} <= @level) ? $level[ $p{deep}-1 ] : $level[ @level-1 ];

    my $style = SStyle->new($self, bold => 1, size => $p->{size});
    my @ln = LineFull->bycont($style, $self->{frame}->{w}, @{ $p{ content } });

    my $h = $self->{size} + 6;
    $h += $_->{h} foreach @ln;

    $self->_page() if $self->{frame}->{h} < $h;
    $self->_parindent( $p->{vindent}, $p->{vcontr} );

    my $ff = $self->{frame};
    my $y = $ff->{y} + $ff->{h};
    foreach my $ln (@ln) {
        $y          -= $ln->{h};
        my $w = $ln->run($self->{page}, $ff->{x}, $y);
        $ff->{h}    -= $ln->{h};
    }
}

sub paragraph {
    my ($self, %p) = @_;

    $self->_parindent(6);

    my $ff = $self->{frame};

    my @ln = LineFull->bycont(SStyle->new($self), $ff->{w}, @{ $p{ content } });
    my $y = $ff->{y} + $ff->{h};
    foreach my $ln (@ln) {
        if ($ff->{h} < $ln->{h}) {
            $self->_page();
            $self->_parindent(6);
            $ff = $self->{frame};
            $y = $ff->{y} + $ff->{h};
        }

        $y          -= $ln->{h};
        my $w = $ln->run($self->{page}, $ff->{x}, $y);
        $ff->{h}    -= $ln->{h};
    }
}

=pod

    my %boundaries = $self->{page}->boundaries();
    use Data::Dumper;
    print Dumper \%boundaries, [$self->{page}->size()];

    my $g = $self->{page}->graphics();
    $g->line_dash_pattern();
    $g->move(100, 500-12*0.2);
    $g->hline(300);
    $g->move(100, 500+12-12*0.2);
    $g->hline(300);
    $g->line_width(1);
    $g->paint();

    my $font = $pdf->font('Helvetica-Bold');
    my $text = $self->{page}->text();
    $text->font($font, 12);
    $text->position(100, 500);
    #$text->text('Hello World! might');
    #$text->text('Hello World!', align => 'right', underline => 'auto');
    #$text->text_justified('Hello World!', 595);
   # my $str = qq~Word spacing might only affect simple fonts and composite fonts where the space character is a single-byte code. This is a limitation of the PDF specification at least as of version 1.7 (see section 9.3.3). It's possible that a later version of the specification will support word spacing in fonts that use multi-byte codes.~;
   # my ($overflow, $height) = $text->paragraph($str, 200, 200, align => 'justify');
    my ($overflow, $height) = $text->paragraph('Hello World! might', 200, 200, align => 'justify');
    print Dumper $overflow, $height;
=cut

package SStyle;

sub new {
    my $class = shift;
    my $out = shift;

    my $self = bless { out => $out, font => $out->{font}, size => $out->{size} }, $class;
    $self->set(@_);

    return $self;
}

sub set {
    my ($self, %p) = @_;

    if (my $f = $p{font}) {
        $self->{font} = $self->{out}->_font($f);
    }
    elsif ($p{italic} || $p{bold}) {
        $self->{bold} = 1 if $p{bold};
        $self->{italic} = 1 if $p{italic};
        if ($self->{bold} && $self->{italic}) {
            $self->{font} = $self->{out}->_font('Arial Bold Italic.ttf');
        }
        elsif ($self->{bold}) {
            $self->{font} = $self->{out}->_font('Arial Bold.ttf');
        }
        elsif ($self->{italic}) {
            $self->{font} = $self->{out}->_font('Arial Italic.ttf');
        }
    }

    $self->{size} = $p{size} if $p{size};
}

sub clone {
    my $self = shift;
    my $copy = bless { %$self }, ref($self);
    $copy->set(@_);
    return $copy;
}

sub width {
    my $self = shift;
    return $self->{font}->width(@_) * $self->{size};
}

sub height { return shift()->{size} * 1.2; }

sub font {
    my $self = shift;
    return wantarray ? ($self->{font}, $self->{size}) : $self->{font};
}

package LineElem;

# Горизонтальный элемент контента.
# Его роль в том, чтобы смочь вывести себя в двух вариантах:
#   - обычный
#   - растянутый на всю ширину
# В каждой строке таких элементов может быть несколько, и чтобы
# корректно они могли растягиваться, каждый элемент в себе хранит
# свою обычную ширину и количество пробелов. Так же пробелами
# считаются места между такими элементами.
#
# Таким образом, вся строка может быть сформирована, опираяся
# на суммаршую ширину всех элементов и ширину пробелов между
# ними. А если надо будет строку растянуть, всем её элементам
# будет передан параметр ws - который сообщит о дополнительном
# расстоянии между элементами.

sub new {
    my $class = shift();

    my $self = bless(
        {
            # стандартные поля, на которые будет опираться
            # целиковая строка на стадии принятия решения,
            # надо ли растягивать или оставить, как есть.
            w => 0,     # стандартная ширина всего элемента
            h => 0,     # высота элемента
            spcnt => 0, # количество пробелов, которые можно будет нарастить для растягивания всей строки
            ws => 0,    # дополнительное наращивание ширины пробела, если всю строчку нужно растянуть
        },
        $class
    );
}

package LineStr;
# Простой текстовый элемент строки.
# Принцип формирования:
# 1. При создании указываем: параметры шрифта и максимально возможную ширину.
# 2. Набиваем словами (метод add), пока не кончатся слова или не заполнится вся выделенная ширина.
use base 'LineElem';

sub new {
    my ($class, $style, $width) = @_;
    my $self = $class->SUPER::new();
    $self->{style}  = $style;
    $self->{maxw}   = $width;
    $self->{spw}    = $style->width(' ');   # ширина пробела для данного шрифта
    $self->{wrd}    = [];                   # список слов: [строка, ширина слова]

    return $self;
}

sub empty { @{ shift()->{wrd} } == 0; }

sub add {
    my ($self, $wrd) = @_;

    my $ww = $self->{style}->width($wrd);               # ширина добавляемого слова
    my $sw = @{ $self->{wrd} } ? $self->{spw} : 0;      # нужно ли добавлять ширину пробела
    my $fw = $self->{w} + $sw + $ww;                    # ширина строки с учётом добавляемого слова
    return if $self->{maxw} < $fw;
    
    $self->{spcnt} = @{ $self->{wrd} };
    $self->{w} = $fw;

    my $h = $self->{style}->height();
    $self->{h} = $h if $self->{h} < $h;

    push @{ $self->{wrd} }, [$wrd, $ww];

    return 1;
}

sub run {
    my ($self, $txt, $x, $y) = @_;

    $txt->font($self->{style}->font());

    if (my $sw = $self->{ws}) { # указано дополнительное расстояние между словами
        # это расстояние нужно добавить к существующему пробельному расстоянию
        $sw += $self->{spw};            # итоговая ширина пробела между словами
        my @wrd = @{ $self->{wrd} };
        # суммарная ширина всей строки, которую мы вернём
        # стартуем её значение с полной ширины всех пробелов между словами
        my $w = @wrd ? (@wrd - 1) * $sw : 0;
        my $dx = 0;
        while (my ($s, $ww) = @{ shift(@wrd)||[] }) {
            $txt->text($s);
            $w += $ww;
            @wrd || last;
            $txt->position($ww + $sw, 0);
            $dx += $ww + $sw;
        }

        return $w, $dx;
    }

    my $s = join(chr(0x20), map { $_->[0] } @{ $self->{wrd} });
    $txt->text($s);

    return $self->{w};
}

package LineFull;

sub new {
    return bless { w => 0, h => 0, elem => [] }, shift();
}

sub line {
    my ($class, $style, $width, @c) = @_;
    
    my $sw = $style->width(' ');
    my ($w, @e) = 0;

    while (my $c = shift @c) {
        my $w1 = $w + (@e ? $sw : 0);
        my $last;
        if (ref($c) eq 'Str') {
            my $e = LineStr->new($style, $width - $w1);
            while (my ($wrd, $n) = $c->word()) {
                if ($e->add($wrd->{str})) {
                    $c = $n || last;
                    next;
                }
                
                unshift(@c, $c);
                $last = 1;
                last;
            }
            
            if (!$e->empty()) {
                push @e, $e;
                $w = $w1 + $e->{w};
            }
        }
        elsif (($c->{type} eq 'bold') || ($c->{type} eq 'italic')) {
            my $s1 = $style->clone($c->{type} => 1);
            my ($ln, @c1) = $class->line($s1, $width - $w1, @{ $c->{text} });

            if ($ln->empty()) {
                unshift(@c, $c);
                $last = 1;
                last;
            }
            else {
                push @e, @{ $ln->{elem} };
                $w = $w1 + $ln->{w};
                if (@c1) {
                    unshift(@c, { %$c, text => [@c1] });
                }
            }
        }
        last if $last;
    }

    my $h = 0;
    foreach my $e (@e) {
        $h = $e->{h} if $h < $e->{h};
    }

    if (@c && @e && ($width > $w)) {
        # есть ещё контент, поэтому эту строчку надо растянуть
        my $spc = @e-1;
        $spc += $_->{spcnt} foreach @e;
        if ($spc) {
            my $ws = ($width - $w) / $spc;
            $_->{ws} = $ws foreach @e;
            $sw += $ws;
        }
    }

    my $self = bless { w => $w, h => $h, sw => $sw, elem => [@e] }, shift();
    return $self, @c;
}

sub bycont {
    my ($class, $style, $width, @c) = @_;

    my @all = ();

    while (@c) {
        my $ln;
        ($ln, @c) = $class->line($style, $width, @c);
        last if !$ln || $ln->empty();
        push @all, $ln;
    }

    return @all;
}

sub empty { @{ shift()->{elem} } == 0 }

sub run {
    my ($self, $page, $x, $y) = @_;

    # Для каждой строки будем создавать отдельный text-объект,
    # так делают очень многие конверторы в pdf.
    #
    # Дело в том, что для манипулиции с координатами у нас
    # в основном только Td. Только первый вызов Td внутри
    # текстового блока задаёт абсолютные координаты, все
    # последующие - относительно предыдущего места установки
    # с помощью того же Td.
    #
    # Для строк, которые не надо растягивать на всю ширину это
    # работает нормально - напечатал строку, перевёл через Td
    # на следующую. Но это только крайняя строка в абзаце,
    # по завершении которого мы всё равно закроем блок.
    #
    # Но если строчку надо растянуть, это можно нормально сделать
    # только делая Td после каждого слова (Tw не работает для
    # юникода). Получаем, что напечатав крайнее слово в строке,
    # нам надо не только спуститься вниз, но и откатиться
    # влево на ширину текста до этого слова. Аналогично и с
    # составными строками (когда внутри встречаются разные стили).
    #
    # Td = position
    # Tw = wordspace
    #
    # Поэтому проще всего создавать для каждой строки свой
    # текстовый блок, чтобы корректно задавать абсолютные
    # координаты начала.
    #
    # Например, экспорт в отечественном office-word в pdf
    # задаёт для каждого слова свои координаты. Чтобы не пересоздавать
    # текстовый блок, там перед словом указываются координаты
    # через команду cm (Modify the current transformation matrix),
    # и в ней надо задавать аж 6 чисел, только двое из которых -
    # это координаты.
    #
    # Возможно, имеет смысл тоже делать cm, но для каждой строчки,
    # а текстовый блок выделять на весь абзац. Но пока непонятно,
    # стоит ли заморачиваться с этим усложнением, т.к. придётся
    # всё равно переоткрывать блок, если абзац не вместится
    # на странице и будет перенесён на следующую.

    my $w = 0;
    my @e = @{ $self->{elem} };
    my $txt = $page->text();
    $txt->position($x, $y);

    while (my $e = shift @e) {
        # elem-run возвращает два размера:
        #   - собственную ширину
        #   - на сколько реально был смещён текстовый курсор
        # эти значения могут отличаться, т.к. после крайнего
        # вывода текста (это может быть вся строка, а может
        # только крайнее слово) перемещение корсора не выполняется,
        # чтобы не добавлять лишних команд там, где это не надо
        my ($w1, $dx) = $e->run($txt, $x, $y);
        $x += $w1;
        $w += $w1;
        if (@e) {
            # Поэтому, если нам надо добавить пробел после предыдущего
            # elem перед следущим, надо учесть, что текстовый курсор
            # совсем необязательно находится после выведенного текста
            $dx = $w1-($dx||0); # $dx может отсутствовать на выходе elem-run
            $dx = 0 if $dx < 0;
            $dx += $self->{sw};
            $txt->position($dx, 0);
        }
    }

    return $w;
}

1;
