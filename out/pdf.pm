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
    my ($self, $indent) = @_;

    my $ff = $self->{frame};
    if (!delete($self->{first})) {
        $ff->{h} -= $indent;
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
        }, {
            size    => 18,
            vindent => 10,
        }, {
            size    => 14,
            vindent => 8,
        }, {
            size    => 12,
            vindent => 8,
        }, {
            size    => 11,
            vindent => 8,
        },
    );
    my $p = ($p{deep} > 0) && ($p{deep} <= @level) ? $level[ $p{deep}-1 ] : $level[ @level-1 ];

    $self->_parindent( $p->{vindent} );
    my $font = $self->_font('Arial Bold.ttf');
    my @ln = LineFull->bycont($font, $p->{size}, $self->{frame}->{w}, @{ $p{ content } });

    my $h = $self->{size} + 6;
    $h += $_->{h} foreach @ln;

    if ($self->{frame}->{h} < $h) {
        $self->_page();
        $self->_parindent( $p->{vindent} );
    }

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

    my @ln = LineFull->bycont($self->{font}, $self->{size}, $ff->{w}, @{ $p{ content } });
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

package WrdLine;

# Строка из слов - с учётом шрифта, его размера и выделенной максимальной ширины строки,
# позволяет максимально заполнить строку словами.
#
# 1. При создании указываем: параметры шрифта и выделенную ширину.
# 2. Набиваем словами (метод add), пока не кончатся слова или не заполнится вся ширина.
# 3. Получаем команды для вывода текста всей строки (метод cmd).

sub new {
    my ($class, $font, $size, $width) = @_;

    my $self = {
        w => $width,                        # выделенная максимальная ширина
        h => 0,                             # высота всей строки (самого высокого элемента)
        f => $font,                         # шрифт
        sz => $size,                        # размер шрифта
        spw => $font->width(' ') * $size,   # ширина пробела для данного шрифта
        ww  => 0,                           # суммарная ширина всех слов без пробелов
        lw  => 0,                           # суммарная шарина всех слов, включая стандартные пробелы между ними
        wrd => []                           # список слов: [строка, ширина слова]
    };

    return bless($self, $class);
}

sub add {
    my ($self, $wrd) = @_;

    my $w = $self->{f}->width($wrd) * $self->{sz};
    my $sw = @{ $self->{wrd} } * $self->{spw};
    return if $self->{w} < $self->{ww} + $sw + $w;
    
    $self->{ww} += $w;
    $self->{lw} = $self->{ww} + $sw;

    my $h = $self->{sz} * 1.2;
    $self->{h} = $h if $self->{h} < $h;

    push @{ $self->{wrd} }, [$wrd, $w];

    return 1;
}

sub empty { @{ shift()->{wrd} } == 0; }

sub cmd {
    my $self = shift;
    my %p = @_;

    if (my $ws = $p{ws}) { # указано принудительно расстояние между словами
        # это значит надо использовать его, а не стандартное пробельное
        my ($x, @cmd) = 0;
        my @wrd = @{ $self->{wrd} };
        while (my ($s, $ww) = @{ shift(@wrd)||[] }) {
            push @cmd, [text => $s];
            # в самом конце строки (целиковой в блоке) смещений не делаем,
            # хотя на это можно забить, просто будет лишняя команда
            # в конце текстового блока, которая ни на что не влияет
            last if !@wrd && $p{lnend};
            $x += $ww + $ws;
            push @cmd, [position => $ww + $ws, 0];
        }

        return $x, @cmd;
    }

    my $spw = @{ $self->{wrd} };
    $spw -- if $spw > 0;
    $spw *= $self->{spw};
    my $s = join(chr(0x20), map { $_->[0] } @{ $self->{wrd} });
    return $spw + $self->{ww}, [text => $s];
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
    my ($class, $font, $size, $width) = @_;
    my $self = $class->SUPER::new();
    $self->{font}   = $font;
    $self->{size}   = $size;
    $self->{maxw}   = $width;
    $self->{spw}    = $font->width(' ') * $size;    # ширина пробела для данного шрифта
    $self->{wrd}    = [];                           # список слов: [строка, ширина слова]

    return $self;
}

sub empty { @{ shift()->{wrd} } == 0; }

sub add {
    my ($self, $wrd) = @_;

    my $ww = $self->{font}->width($wrd) * $self->{size};    # ширина добавляемого слова
    my $sw = @{ $self->{wrd} } ? $self->{spw} : 0;          # нужно ли добавлять ширину пробела
    my $fw = $self->{w} + $sw + $ww;                        # ширина строки с учётом добавляемого слова
    return if $self->{maxw} < $fw;
    
    $self->{spcnt} = @{ $self->{wrd} };
    $self->{w} = $fw;

    my $h = $self->{size} * 1.2;
    $self->{h} = $h if $self->{h} < $h;

    push @{ $self->{wrd} }, [$wrd, $ww];

    return 1;
}

sub run {
    my ($self, $txt, $x, $y) = @_;

    $txt->font($self->{font}, $self->{size});

    if (my $sw = $self->{ws}) { # указано дополнительное расстояние между словами
        # это расстояние нужно добавить к существующему пробельному расстоянию
        $sw += $self->{spw};            # итоговая ширина пробела между словами
        my @wrd = @{ $self->{wrd} };
        # суммарная ширина всей строки, которую мы вернём
        # стартуем её значение с полной ширины всех пробелов между словами
        my $w = @wrd ? (@wrd - 1) * $sw : 0;
        while (my ($s, $ww) = @{ shift(@wrd)||[] }) {
            $txt->text($s);
            $w += $ww;
            # в самом конце строки (целиковой в блоке) смещений не делаем,
            # хотя на это можно забить, просто будет лишняя команда
            # в конце текстового блока, которая ни на что не влияет
            last if !@wrd && $self->{lnend};    # признак, что это крайний элемент в строке,
                                                # его выставляет вышестоящая полная строка
            $txt->position($ww + (@wrd ? $sw : 0), 0);
        }

        return $w;
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
    my ($class, $font, $size, $width, @c) = @_;
    
    my $sw = $font->width(' ') * $size;
    my ($w, @e) = 0;

    while (my $c = shift @c) {
        my $last;
        if (ref($c) eq 'Str') {
            my $w1 = $w + (@e ? $sw : 0);
            my $e = LineStr->new($font, $size, $width - $w1);
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

    $e[@e-1]->{lnend} = 1 if @e;

    my $self = bless { w => $w, h => $h, sw => $sw, elem => [@e] }, shift();
    return $self, @c;
}

sub bycont {
    my ($class, $font, $size, $width, @c) = @_;

    my @all = ();

    while (@c) {
        my $ln;
        ($ln, @c) = $class->line($font, $size, $width, @c);
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
        my $w1 = $e->run($txt, $x, $y);
        $w1 += $self->{sw} if @e;
        $x += $w1;
        $w += $w1;
    }

    return $w;
}

1;
