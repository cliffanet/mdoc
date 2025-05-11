package out::pdf;

use strict;
use warnings;

use base 'out';

use PDF::API2;

use constant mm2pix => 2.8346904;

PDF::API2->add_to_font_path('.', './fonts', '/System/Library/Fonts', '/System/Library/Fonts/Supplemental', '/Library/Fonts', '~/Library/Fonts');

=pod

    Концептуально формирование документа производим в два этапа:

    1. Сборка элементов.

        На данном этапе нам нужны только:

        - ширина страницы, чтобы формировать строки;
        - высота страницы, чтобы формировать страницы из строк.

        Мы собираем список элементов, которые нам нужно отрисовать.

    2. Отрисовка страниц

        На данном этапе мы формируем в PDF::API2 все нужные элементы:

        - страницы,
        - текст,
        - графику.

        Последовательно для каждого элемента выполняем метод run,
        куда передаём объект-контекст и текущие координаты отрисовки элемента.
        Внутри метода run могут быть вызваны методы объекта-контекста,
        которые будут смещать координаты, согласно их внутреннему алгоритму.
    
    Вся структура документа состоит из уровней:

    - Page - страница, на которой формируются строки.

        Страница состоит из строк, расположенных друг под другом.

        При формировании строки мы должны ей передать только максимальную
        ширину - это ширина страницы с учётом боковых отступов.

        Суммарная высота строк не должна превышить максимальную
        высоту страницы с учетом верхнего и нижнего отступов.
    
    - LineFul - целиком строка на странице.

        Из этих элементов состоит страница Page.

        При формировании строки мы не должны выходить за пределы
        максимально возможной ширины.

        Когда строка сформирована, у неё появляется самый важный элемент -
        её высота (максимальная, с учётом всех подэлементов).

        Высота может быть:

        - положительная (обычный текст) - последующие строки отрисуются ниже;
        - нулевая - обычно это графика, которая ляжет под последующие строки;
        - отрицательная - если нам надо сместить последующий текст выше.
    
    - LineElem - это подэлементы строки

        Строка разбивается на подэлементы, потому что может потребоваться
        существенное изменение стиля и алгоритма отрисовки:

        - обычный текст,
        - bold,
        - italic,
        - inlinecode,
        - image
        - link

        У каждого из этих подэлементов присутствуют параметры:

        - высота,
        - стандартная ширина,
        - количество пробелов,
        - добавочная ширина пробела (устанавливается в LineFul).

        По высотам подэлементов LineFul определит содственную высоту.

        Стандартная ширина и количество пробелов нужны для LineFul, который при
        необходимости растянуть всю строку сообщит каждому подэлементу
        "добавочную ширину пробела" ещё на стадии сборки списка элементов.

=cut

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
    
    $self->_pageadd();

    #use Data::Dumper;
    #print Dumper [ PDF::API2->font_path() ];

    return $self;
}

sub data {
    my $self = shift;

    # Мы могли бы создавать сам pdf-объект прямо здесь, но при формировании
    # списка элемента нам важно знать высоту и ширину текста, а для
    # этого нужно знать шрифты, это умеет только сам объект pdf.

    # На стадии сборки списка элементов от pdf-объекта нужны только шрифты.
    # Всё остальное делается уже тут - это и есть стадия отрисовки страниц.

    foreach my $p (@{ $self->{pageall} }) {
        $p->run($self->{pdf});
    }
    
    return $self->{pdf}->to_string();
}

sub _pageadd {
    my $self = shift;

    my $page = Page->new(
        shift(),
        ($self->{margin}||{})->{left},
        ($self->{margin}||{})->{right},
        ($self->{margin}||{})->{top},
        ($self->{margin}||{})->{bottom}
    );

    push @{ $self->{pageall} ||= [] }, $page;

    return $page;
}

sub _page {
    my $self = shift;

    my $p = $self->{pageall};
    @$p || return;

    return $p->[@$p-1];
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
    my $f = ($p{deep} > 0) && ($p{deep} <= @level) ? $level[ $p{deep}-1 ] : $level[ @level-1 ];

    my $p = $self->_page();
    my $style = SStyle->new($self, bold => 1, size => $f->{size});
    my @ln = LineFull->bycont($style, $p->{maxw}, @{ $p{ content } });

    my $h = $self->{size} + 6;
    $h += $f->{vindent} if !$p->empty();
    $h += $_->{h} foreach @ln;

    $p = $self->_pageadd() if $p->havail() < $h;

    $p->vindent( $f->{vindent}, -$f->{vcontr} );

    $p->add($_) foreach @ln;
}

sub paragraph {
    my ($self, %p) = @_;

    my $p = $self->_page();
    $p->vindent(6, -4);

    my @ln = LineFull->bycont(SStyle->new($self), $p->{maxw}, @{ $p{ content } });
    foreach my $ln (@ln) {
        next if $p->add($ln);

        # не хватило места на странице
        $p = $self->_pageadd();
        $p->vindent(6, -4);
        $p->add($ln);
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

sub ulpos {
    my $self = shift;
    return $self->{font}->underlineposition() * $self->{size} / 1000 || 1;
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

sub run {}

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

    if (!@{ $self->{wrd} } && ($wrd =~ /^[\,\.\:]/)) {
        $self->{nospl} = 1;
    }

    push @{ $self->{wrd} }, [$wrd, $ww];

    return 1;
}

sub run {
    my ($self, $p) = @_;

    $p->font($self->{style}->font());
    
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
    # юникода).
    #
    # Td = position
    # Tw = wordspace
    #
    # Например, экспорт в отечественном office-word в pdf
    # задаёт для каждого слова свои координаты. Чтобы не пересоздавать
    # текстовый блок, там перед словом указываются координаты
    # через команду cm (Modify the current transformation matrix),
    # и в ней надо задавать аж 6 чисел, только двое из которых -
    # это координаты.

    if (my $sw = $self->{ws}) { # указано дополнительное расстояние между словами
        # это расстояние нужно добавить к существующему пробельному расстоянию
        $sw += $self->{spw};            # итоговая ширина пробела между словами
        my @wrd = @{ $self->{wrd} };
        # суммарная ширина всей строки, которую мы вернём
        # стартуем её значение с полной ширины всех пробелов между словами
        my $w = @wrd ? (@wrd - 1) * $sw : 0;
        my $dx = 0;
        while (my ($s, $ww) = @{ shift(@wrd)||[] }) {
            $p->text($s);
            $p->dx($ww);
            $p->dx($sw) if @wrd;
        }
    }
    else {
        my $s = join(chr(0x20), map { $_->[0] } @{ $self->{wrd} });
        $p->text($s);
        $p->dx($self->{w});
    }
}

package LineICode;
# inlinecode
use base 'LineStr';

sub new {
    my $self = shift()->SUPER::new(@_);
    $self->{w} += int($self->{style}->{size} / 2) * 2;
    return $self;
}

sub run {
    my ($self, $p) = @_;

    $p->gfxcol('#aaa');
    my $yz = $self->{style}->{size} * 0.2;
    $p->rrect($p->{x} + 1, $p->{y} + $self->{style}->ulpos() - $yz, $self->{w} - 2 + $self->{spcnt}*$self->{ws}, $self->{style}->{size} + $yz*2, 4);

    my $lw = int($self->{style}->{size} / 2); 
    $p->dx( $lw );

    {
        # При растягивании текста LineStr::run делает внутри себя dx
        # ровно на ширину текста, т.к. считает её вручную.
        # Однако, без растягивания, LineStr::run выводит всю строчку
        # и делает dx на $self->{w}, считая, что там только ширина текста,
        # а в LineICode это не так, там ещё дополнительная ширина $lw*2,
        # которую тут надо временно вычесть. В дальнейшем, наверное,
        # надо сделать, чтобы в LineStr::run пересчитывалась вручную
        # и в случае без растягивания текста так же.
        local $self->{w} = $self->{w} - $lw*2;
        $self->SUPER::run($p);
    } 
    $p->dx( $lw );
}

package LineHref;
# href
use base 'LineElem';

sub new {
    my ($class, $w, $h, $spcnt, $url) = @_;
    my $self = $class->SUPER::new();
    $self->{url} = $url;
    $self->{rect} = {
        w       => $w,
        h       => $h,
        spcnt   => $spcnt
    };

    return $self;
}

sub run {
    my ($self, $p) = @_;

    my $r = $self->{rect};
    my $g = $p->gfx();
    $p->gfxcol('#000');
    $g->move($p->{x}, $p->{y} - 3);
    $g->hline($p->{x} + $r->{w} + $r->{spcnt}*$self->{ws});
    $g->stroke();

    my $an = $p->annotation();
    $an->rect($p->{x}, $p->{y} - 3, $p->{x} + $r->{w} + $r->{spcnt}*$self->{ws}, $p->{y} - 3 + $r->{h});
    $an->uri($self->{url});
}


package LineFull;

sub new {
    return bless { w => 0, h => 0, spcnt => 0, elem => [] }, shift();
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
        elsif ($c->{type} eq 'inlinecode') {
            my $s = Str->new($c->{str}, row => $c->{row}, col => $c->{col});
            my $e = LineICode->new($style, $width - $w1);
            while (my ($wrd, $n) = $s->word()) {
                if ($e->add($wrd->{str})) {
                    $s = $n || last;
                    next;
                }
                
                unshift(@c, { $s->hinf(), type => 'inlinecode' });
                $last = 1;
                last;
            }
            
            if (!$e->empty()) {
                push @e, $e;
                $w = $w1 + $e->{w};
            }
        }
        elsif ($c->{type} eq 'href') {
            my ($ln, @c1) = $class->line($style, $width - $w1, @{ $c->{text} });

            if ($ln->empty()) {
                unshift(@c, $c);
                $last = 1;
                last;
            }
            else {
                my $href = LineHref->new($ln->{w}, $ln->{h}, $ln->{spcnt}, $c->{url});
                # $href должен быть перед текстовыми элементами, чтобы были
                # корректными x и y.
                # И т.к. $href является отдельным элементом, надо доработать
                # межэлементные интервалы: у $href nospl должен соответствовать
                # первому элементу в $ln->{elem}, а для первого элемента
                # nospl должен быть обязательно установлен, чтобы не было
                # промежутков между $href и $ln->{elem}.
                my $e0 = $ln->{elem}->[0];
                $href->{nospl} = 1 if $e0->{nospl};
                $e0->{nospl} = 1;
                push @e, $href, @{ $ln->{elem} };
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

    my $spcnt = undef;
    foreach my $e (@e) {
        if (!defined($spcnt)) {
            $spcnt = 0;
        }
        elsif (!$e->{nospl}) {
            $spcnt ++;
        }
        $spcnt += $e->{spcnt};
    }
    $spcnt ||= 0;
    
    if (@c && $spcnt && ($width > $w)) {
        # есть ещё контент, поэтому эту строчку надо растянуть
        my $ws = ($width - $w) / $spcnt;
        $_->{ws} = $ws foreach @e;
        $sw += $ws;
    }

    my $self = bless { w => $w, h => $h, sw => $sw, spcnt => $spcnt, elem => [@e] }, shift();
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
    my ($self, $p) = @_;

    my $f = 1;
    foreach my $e (@{ $self->{elem} }) {
        if ($f) {
            undef $f;
        }
        elsif (!$e->{nospl}) {
            $p->dx($self->{sw});
        }
        $e->run($p);
    }
}

package LineClean;

sub new {
    my ($class, $height) = @_;

    return bless { w => 0, h => $height }, shift();
}

sub run {
    my ($self, $p) = @_;

    delete $p->{text};
    $p->gfxclear();
}

package Page;

sub new {
    my ($class, $size, $mleft, $mright, $mtop, $mbottom) = @_;

    $size       ||= 'A4';
    $mleft      //= 0;
    $mright     //= $mleft;
    $mtop       //= $mright;
    $mbottom    //= $mtop;

    my ($x, $y, $w, $h) = PDF::API2::Page::_to_rectangle($size);

    return bless({
        margin  => {
            left    => $mleft,
            right   => $mright,
            top     => $mtop,
            bottom  => $mbottom
        },
        size    => $size,
        maxw    => $w - $mleft - $mright, 
        maxh    => $h - $mbottom - $mtop,
        w       => 0,
        h       => 0,
        line    => [],
    }, $class);
}

sub empty { @{ shift()->{line} } == 0 }

sub havail {
    my $self = shift;
    return $self->{maxh} - $self->{h};
}

sub add {
    my ($self, $ln) = @_;

    return if $ln->{h} > $self->havail();

    push @{ $self->{line} }, $ln;

    $self->{w} = $ln->{w} if $self->{w} > $ln->{w};

    $self->{h} += $ln->{h};

    return 1;
}

sub vindent {
    my ($self, $next, $frst) = @_;
    # Добавление отступа:
    #   $next - если уже есть элементы и надо отступить перед ними
    #   $frst - если элементов на странице ещё нет
    if ($self->empty()) {
        return $frst ? $self->add(LineClean->new($frst)) : 1;
    }
    else {
        return $next ? $self->add(LineClean->new($next)) : 1;
    }
}

sub run {
    my ($self, $pdf) = @_;

    my $page = ($self->{page} = $pdf->page());
    $page->size($self->{size});
    my ($x, $y, $w, $h) = $page->size();

    $self->{y} = $y + $h - $self->{margin}->{top};

    my $g = $page->graphics();
    my ($x1,$y1, $x2,$y2) = ($x+$self->{margin}->{left}, $y+$self->{margin}->{bottom}, $x+$w-$self->{margin}->{right}, $self->{y});
    $g->move($x1,$y1);
    $g->hline($x2);
    $g->vline($y2);
    $g->hline($x1);
    $g->vline($y1);
    $g->stroke();

    foreach my $ln (@{ $self->{line} }) {
        $self->{x}  = $x + $self->{margin}->{left};
        $self->{y}  -= $ln->{h};
        # координаты x,y нам задают текущую позицию, в которой должна
        # отрисоваться строка. При этом, "y" - это нижняя точка этого элемента,
        # а верхняя будет = y + $ln->{h};
        $ln->run($self);
    }

    delete $self->{page};
    delete $self->{text};
    $self->gfxclear();
    delete $self->{x};
    delete $self->{y};
}

sub dx {
    my ($self, $dx) = @_;
    $self->{x} += $dx;
}

sub _text {
    my $self = shift();
    
    if (!$self->{text}) {
        my $t = $self->{page}->text();
        $self->{text} = {
            x   => $self->{x},
            y   => $self->{y},
            f   => ['', 0],
            o   => $t
        };
        $t->position($self->{x}, $self->{y});
    }

    return $self->{text};
}

sub font {
    my ($self, $fn, $sz) = @_;

    my $t = $self->_text();

    return if ($t->{f}->[0] eq $fn) && ($t->{f}->[1] == $sz);

    $t->{f} = [$fn, $sz];
    $t->{o}->font($fn, $sz);
}

sub text {
    my $self = shift();

    my $t = $self->_text();

    # Позиционировать будем через position, он работает следующим
    # образом: при первом вызове после создания text-obj
    # он задаёт абсолютные координаты, а все последующие
    # вызовы смещают относительно предыдущей установки позиции.
    #
    # В $self->{x}/$self->{y} у нас хранятся виртуальные координаты,
    # для отрисовки очередного элемента.
    #
    # Каждый раз, перед тем, как вывести текст, мы будем проверять,
    # насколько у нас убежали виртуальные координаты с момента
    # предыдущего задания позиции через метод position. И при
    # необходимости скорректируем.

    my ($dx, $dy) = ($self->{x} - $t->{x}, $self->{y} - $t->{y});
    if ($dx || $dy) {
        $t->{o}->position($dx, $dy);
        $t->{x} += $dx;
        $t->{y} += $dy;
    }

    # Фактически в итоге мы сможем включать весь текст внутрь
    # одного text-obj. А между абзацами у нас будет вызываться
    # LineClean, который работает одновременно и отступом между
    # абзацами, и закрывает текущий text-obj, заставляя для
    # следующего абзаца создавать новый.

    $t->{o}->text(@_);
}

sub gfx {
    my $self = shift();

    if (!$self->{gfx}) {
        # Если на странице мы используем и графику и текст, то нам важно,
        # чтобы content с графикой был по текущим text-content,
        # если таковой уже открыт, иначе графика закроет текст.
        my $tc;
        if ($self->{text}) {
            # Нормального способа, как в PDF::API2::Page сменить местами
            # два верхних потока я не нашёл, поэтому немного взламываем код,
            # из-за чего он может перестать работать, если в PDF::API2::Page
            # что-то сильно поменяют, т.к. это внутренняя кухня.
            $tc = pop @{ $self->{page}->{'Contents'}->val() };
        }
        my $g = $self->{page}->graphics();
        push(@{ $self->{page}->{'Contents'}->val() }, $tc) if $tc;
        $self->{gfx} = {
            c => '#000',
            o => $g,
        };
    }

    return $self->{gfx}->{o};
}

sub rrect {
    my ($self, $x, $y, $w, $h, $r) = @_;

    my $g = $self->gfx();
    $g->move($x, $y+$r);
    $g->arc($x + $r,        $y + $r,        $r, $r, -180, -90);
    $g->hline($x + $w - $r);
    $g->arc($x + $w - $r,   $y + $r,        $r, $r, -90, 0);
    $g->vline($y + $h - $r);
    $g->arc($x + $w - $r,   $y + $h - $r,   $r, $r, 0, 90);
    $g->hline($x + $r);
    $g->arc($x + $r,        $y + $h - $r,   $r, $r, 90, 180);
    $g->vline($y + $r);
    $g->paint();
}

sub gfxcol {
    my ($self, $col) = @_;

    my $g = $self->gfx();
    return if $self->{gfx}->{c} eq $col;
    $self->{gfx}->{c} = $col;
    $g->stroke_color($col);
    $g->fill_color($col);
}

sub gfxclear {
    my $self = shift();

    # Почему-то в PDF изменение fill_color (а может и stroke_color) действует
    # не до конца content-stream, а до конца страницы. Поэтому надо сменить
    # цвет на стандартный в конце gfx-content
    $self->{gfx} || return;
    my $c = $self->{gfx}->{c};
    $self->gfxcol('#000') if $c;
    delete $self->{gfx};
}

sub annotation {
    my $self = shift();
    return $self->{page}->annotation();
}

1;
