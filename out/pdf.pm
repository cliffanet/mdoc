package out::pdf;

use strict;
use warnings;

use base 'out';

use PDF::API2;

use constant mm2pix => 2.8346904;

PDF::API2->add_to_font_path('.', './fonts', '/System/Library/Fonts', '/System/Library/Fonts/Supplemental', '/Library/Fonts', '~/Library/Fonts');

my %style = (
    base => {
        #font => 'Arial.ttf',
        font => 'helvetica_regular.otf',
        #font => 'Helvetica',    # с ttf-шрифтами не работает wordspace, который нужен для justify
                                # но core-шрифты не работают с кодировками совсем
        size => 11,
    },

    bold => {
        font => 'Times-Bold',
    },

    italic => {
        font => 'Times-Italic',
    }
);

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

    $self->_style('base');
    
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

sub _style {
    my $self = shift;
    if (@_ == 1) {
        my $ss = $style{ shift() } || {};
        return $self->_style(%$ss);
    }
    if (@_) {
        my $ss = { @_ };
        if (my $fname = delete $ss->{font}) {
            my $fall = ($self->{fontall} ||= {});
            $ss->{font} = ( $fall->{ $fname } ||= $self->{pdf}->font($fname) );
        }
        push @{ $self->{style}||=[] }, $ss;
    }

    return { map { %$_ } @{ $self->{style}||[] } };
}
sub _styleend {
    my $self = shift;
    return pop @{ $self->{style}||[] };
}

sub _line_get {
    my ($self, $width, @c) = @_;
    $width ||= 0;

    my ($h, $ww, $spcnt, @cmd) = (0, 0, 0);
    my $ss = $self->_style();
    my $sw = $ss->{font}->width(' ') * $ss->{size};

    while (my $c = shift @c) {
        my $last;
        if (ref($c) eq 'Str') {
            my $l = PdfLine->new($ss->{font}, $ss->{size}, $width);
            while (my ($wrd, $n) = $c->word()) {
                if ($l->add($wrd->{str})) {
                    $c = $n || last;
                    next;
                }
                
                unshift(@c, $c);
                $last = 1;
                last;
            }
            
            if (!$l->empty()) {
                $h = $l->{h} if $h < $l->{h};
                $ww += $l->{ww};
                $width -= $l->{lw};
                $spcnt ++ if @cmd;
                $spcnt += @{ $l->{wrd} } - 1;
                push @cmd, sub { $l->cmd(@_); };
            }
        }
        last if $last;
    }

    return
        h       => $h,          # высота строки
        ww      => $ww,         # суммарная ширина всех неразрывных элементов
        spcnt   => $spcnt,      # количество пробельных элементов
        nxt     => [@c],        # остаток от content
        cmd     => [@cmd];      # функции по генерации команд
}

sub _line {
    my ($self, $width, @c) = @_;
    $width ||= 0;

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

    my $ss = $self->_style();
    my $fsize = $ss->{size};
    my @cmd = (
        # сюда в качестве $x, $y передаётся левый верхний угол текста,
        # отступ вниз на высоту шрифта мы делаем сами
        sub {
            my ($text, $x, $y) = @_;
            $text->position($x, $y - $fsize);
        },
        [font => $ss->{font}, $ss->{size}]
    );

    # на входе - элементы content
    my %p = $self->_line_get($width, @c);
    @{ $p{cmd} || [] } || return h => $p{h}, nxt => $p{nxt};
    
    my @arg = ();
    if (@{$p{nxt}} && ($width > $p{ww}) && $p{spcnt}) {
        # есть продолжение, в $p{nxt}, значит эту строчку надо растянуть
        @arg = (ws => ($width - $p{ww}) / $p{spcnt});
    }

    my $xp = 0;
    my @cmdr = @{ $p{cmd} };
    while (my $c = shift(@cmdr)) {
        @cmdr || push(@arg, lnend => 1);
        my ($w, @c) = $c->(x => $xp, @arg);
        $xp += $w;
        push @cmd, @c;
    }

    return
        h   => $p{h},
        cmd => [@cmd],
        nxt => $p{nxt};
}

sub _text_out {
    my ($self, $x, $y, @cmd) = @_;

    my $txt = $self->{page}->text();
    foreach my $cmd (@cmd) {
        if (ref($cmd) eq 'CODE') {
            $cmd->($txt, $x, $y);
        }
        elsif (ref($cmd) eq 'ARRAY') {
            my ($m, @arg) = @$cmd;
            $txt->$m(@arg);
        }
    }
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

    my $txtsz = $self->_style()->{size};
    my $width = $self->{frame}->{w};
    $self->_parindent( $p->{vindent} );
    $self->_style(font => 'Arial Bold.ttf', size => $p->{size});

    my @c = @{ $p{content} };
    my ($h, @cmd) = $txtsz + 6;
    while (@c) {
        my %p = $self->_line($width, @c);
        @{ $p{cmd}||[] } || last;
        push @cmd, [$p{h}, $p{cmd}];
        $h += $p{h};
        @c = @{ $p{nxt}||[] };
    }

    if ($self->{frame}->{h} < $h) {
        $self->_page();
        $self->_parindent( $p->{vindent} );
    }

    my $ff = $self->{frame};
    my $y = $ff->{y} + $ff->{h};
    foreach (@cmd) {
        my ($h, $cmd) = @$_;
        $self->_text_out($ff->{x}, $y, @$cmd);
        $y -= $h;
        $ff->{h} -= $h;
    }

    $self->_styleend();
}

sub paragraph {
    my ($self, %p) = @_;

    $self->_parindent(6);

    my $ff = $self->{frame};
    my $y = $ff->{y} + $ff->{h};

    my @c = @{ $p{content} };
    while (@c) {
        my %p = $self->_line($ff->{w}, @c);
        @{ $p{cmd}||[] } || last;

        if ($ff->{h} < $p{h}) {
            $self->_page();
            $self->_parindent(6);
            $ff = $self->{frame};
            $y = $ff->{y} + $ff->{h};
        }

        $self->_text_out($ff->{x}, $y, @{ $p{cmd} });
        $y -= $p{h};
        $ff->{h} -= $p{h};
        @c = @{ $p{nxt}||[] };
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

package PdfLine;

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

1;
