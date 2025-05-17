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

    ----------------------------------------------------------

    В предыдущей версии логики мы шли от страницы, которую набивали строками,
    которые в свою очередь содержат элементы.

    В процессе формирования каждого блочного элемента на каждом
    этапе (страница/строка) мы выделяли некую область - прямоугольник
    или строка ограниченной ширины, которую блочный элемент пытался заполнить,
    насколько сможет, после чего запрашивал следующую область (следующую строку
    или страницу) и набивал уже её.

    Этот алгоритм плохо работает из-за разношёрстности логики работы на каждом
    уровне. А управление происодит только вглубь уровней: мы выделили тексту
    какой-то блок и он может с этим только согласиться или отказаться добавлять
    в себя строчки. На практике затык произошёл, когда речь зашла о quote, listitem,
    внутри которых могут быть такие же элементы, как и на самом верхнем уровне.
    Внутри quote может быть другой qoute, listitem и paragraph.

    Нам необходимо достичь управления из глубны наружу, чтобы при изменении
    размерностей нижестоящих элементов информация об этом шла наверх,
    а вышестоящие элементы уже будут пересчитывать свои размерности и
    при необходимости корректировать структуру.

    Для этого на каждом уровне введём базовый класс, который при добавлении
    внутрь себя подэлементов будет выполнять следуюшее:

    1. Пересчитает свою будущую размерность с учётом нового добавляемого подэлемента.

    2. Сделает запрос вышестоящему о необходимости выполнить изменение
    собственной размерности. Причём, это только запрос без фактического изменения.
    Чтобы упростить разбор ситуаций, условимся, что мы только увеличиваем
    размерности, но не уменьшаем (чтобы обрабатывать только один вариант).
    
    3. Вышестоящий выполняет анализ запрашиваемых изменений:
        а) пересчитывает свою размерность, учитывая запрашиваемые изменения подэлемента
        б) сообщает наверх об изменении своей размерности
        в) при необходимости делает изменения в структуре дерева
    
    4. Добавляет в себя элемент и пересчитывает свои размерности с учётом
    всех изменений в структуре, которые могли произойти на предыдущих этапах.

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

    $self->{doc} = FDocument->new();
    # создаём первую страницу, остальные
    # будут копировать параметры (движок Frame::recalc)
    $self->{context} = FPage->new(
        '', # page size
        ($self->{margin}||{})->{left},
        ($self->{margin}||{})->{right},
        ($self->{margin}||{})->{top},
        ($self->{margin}||{})->{bottom}
    );
    $self->{doc}->add($self->{context});


    $self->{ddoc} = DDocument->new();
    $self->{ctx} = DPage->new();
    $self->{ddoc}->add($self->{ctx});
    # после переезда на этот движок, надо будет
    # упрастить работу с классом SStyle
    $self->{style} = SStyle->new($self);

    #use Data::Dumper;
    #print Dumper [ PDF::API2->font_path() ];

    return $self;
}

sub data {
    my $self = shift;

    # К этому моменту мы выполнили только первый этап - сформировали
    # базовую структуру и ещё ничего не знаем о размерностях.

    # Теперь нам надо выполнить второй этап - распределить
    # элементы по пространству на документе, страницах и т.д.
    $self->{ddoc}->stage2size($self);

    # Теперь распределяем согласно нашим размерам.
    # Сверху до уровня страниц нам надо передать размерность страницы
    # и размеры всех полей.
    $self->{ddoc}->stage3layout('A4', %{ $self->{margin} });

    # И, наконец, выводим содержимое
    $self->{ddoc}->draw( $self->{pdf} );

    # ----------------------
    # старый вариант

    # Мы могли бы создавать сам pdf-объект прямо здесь, но при формировании
    # списка элемента нам важно знать высоту и ширину текста, а для
    # этого нужно знать шрифты, это умеет только сам объект pdf.

    # На стадии сборки списка элементов от pdf-объекта нужны:
    #   - шрифты,
    #   - создание внешних объектов (картинки)
    #
    # Всё остальное делается уже тут - это и есть стадия отрисовки страниц.

    #$self->{doc}->draw( $self->{pdf} );
    
    return $self->{pdf}->to_string();
}

=pod

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

=cut

sub _font {
    my ($self, $name) = @_;
    
    my $fall = ($self->{fontall} ||= {});

    return $fall->{ $name } ||= $self->{pdf}->font($name);
}

sub _image {
    my ($self, $fname) = @_;
    
    my $imgall = ($self->{imgall} ||= {});

    return $imgall->{$fname} ||= $self->{pdf}->image($fname);
}

=pod

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

sub code {
    # для code хорошо бы сделать парсинг кода,
    # но пока просто доблируем работу textblock
    textblock(@_);
}

sub quote {
    my ($self, %p) = @_;
    
    my $p = $self->_page();
    $p->vindent(6);
    my $block = TextQuote->new($p->{maxw}, $p->havail());
    my @ln = LineFull->bycont(SStyle->new($self), $block->{maxw}, @{ $p{ content } });

    foreach my $ln (@ln) {
        next if $block->add($ln);

        # не хватило места на странице
        $p->add($block) if !$block->empty();
        $p = $self->_pageadd();
        $block = TextQuote->new($p->{maxw}, $p->havail());
    }
    $p->add($block) if !$block->empty();
}

sub textblock {
    my ($self, %p) = @_;
    
    my $p = $self->_page();
    $p->vindent(12);
    my $block = TextBox->new($p->{maxw}, $p->havail());
    my $style = SStyle->new($self, font => 'PTMono.ttf');

    my @ln =
        map {
            my $ln  = LineFull->new();
            my $s   = LineStr->new($style);
            $s->add($_->{str});
            $ln->add( $s );
            $ln;
        }
        @{ $p{ text } };

    foreach my $ln (@ln) {
        next if $block->add($ln);

        # не хватило места на странице
        $p->add($block) if !$block->empty();
        $p = $self->_pageadd();
        $block = TextBox->new($p->{maxw}, $p->havail());
    }
    $p->add($block) if !$block->empty();
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

=cut

sub header {
    my ($self, %p) = @_;

    #my @size = ( 22, 18, 14, 12, 11 );
    #my $sz = ($p{deep} > 0) && ($p{deep} <= @size) ? $size[ $p{deep}-1 ] : $size[ @size-1 ];
    #my $style = SStyle->new($self, bold => 1, size => $sz);

    #my $c = FHeader->new($style, $self->{context}->{maxw});
    #$self->{context}->add($c);
    #$c->content(@{ $p{ content } });

    my $c = DHeader->new($p{deep}, @{ $p{ content } });
    $self->{ctx}->add( $c );
}

sub paragraph {
    my ($self, %p) = @_;

    #my $c = FContent->new(SStyle->new($self), $self->{context}->{maxw});
    #$self->{context}->add($c);
    #$c->content(@{ $p{ content } });

    my $c = DContent->new(@{ $p{ content } });
    $self->{ctx}->add( $c );
}

# ============================================================
#
#       SStyle
#
# ============================================================

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

sub height { return shift()->{size}; }

sub font {
    my $self = shift;
    return wantarray ? ($self->{font}, $self->{size}) : $self->{font};
}

sub ulpos {
    my $self = shift;
    return $self->{font}->underlineposition() * $self->{size} / 1000 || 1;
}

package PageDraw;

sub new {
    my ($class, $page) = @_;
    return bless({ page => $page, col => '#000' }, $class);
}

sub _text {
    my $self = shift();
    
    if (!$self->{text}) {
        $self->{text} = $self->{page}->text();
        $self->{txtx} = 0;
        $self->{txty} = 0;
        $self->{font} = ['', 0];
    }

    return $self->{text};
}

sub font {
    my ($self, $fn, $sz) = @_;

    my $t = $self->_text();

    return if ($self->{font}->[0] eq $fn) && ($self->{font}->[1] == $sz);

    $self->{font} = [$fn, $sz];
    $t->font($fn, $sz);
}

sub text {
    my ($self, $x, $y, $str) = @_;

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

    my ($dx, $dy) = ($x - $self->{txtx}, $y - $self->{txty});
    if ($dx || $dy) {
        $t->position($dx, $dy);
        $self->{txtx} = $x;
        $self->{txty} = $y;
    }

    $t->text($str);
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
        $self->{gfx} = $self->{page}->graphics();
        push(@{ $self->{page}->{'Contents'}->val() }, $tc) if $tc;
    }

    return $self->{gfx};
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

    return if $self->{col} eq $col;

    my $g = $self->gfx();
    $self->{col} = $col;
    $g->stroke_color($col);
    $g->fill_color($col);
}

sub close {
    my $self = shift();

    # Почему-то в PDF изменение fill_color (а может и stroke_color) действует
    # не до конца content-stream, а до конца страницы. Поэтому надо сменить
    # цвет на стандартный в конце gfx-content
    $self->gfxcol('#000') if $self->{col} ne '#000';
    delete $self->{text};
    delete $self->{txtx};
    delete $self->{txty};
    delete $self->{font};
    delete $self->{gfx};
}

DESTROY { shift()->close(); }



=pod

# ============================================================
#
#       LineElem
#
# ============================================================

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
sub empty {}

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
    $self->{maxw}   = $width if $width;
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
    return if $self->{maxw} && ($self->{maxw} < $fw);
    
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

    my $an = $p->{page}->annotation();
    $an->rect($p->{x}, $p->{y} - 3, $p->{x} + $r->{w} + $r->{spcnt}*$self->{ws}, $p->{y} - 3 + $r->{h});
    $an->uri($self->{url});
}

package LineImg;
# image
use base 'LineElem';

sub new {
    my ($class, $img, $url, $title) = @_;
    my $self = $class->SUPER::new();
    $self->{img} = $img;
    $self->{url} = $url;

    $self->{w} = $img->width();
    $self->{h} = $img->height();

    $self->{title} = $title if $title;

    return $self;
}

sub run {
    my ($self, $p) = @_;

    $p->{page}->object($self->{img}, $p->{x}, $p->{y});
    $p->dx($self->{w});
}


# ============================================================
#
#       LineFull
#
# ============================================================

package LineFull;

sub new {
    my $class = shift;

    my $self = bless(
        {
            w       => 0,
            h       => 0,
            spw     => 0,
            spcnt   => 0,
            ws      => 0,
            elem    => []
        },
        $class
    );

    if (my $style = shift()) {
        $self->{spw} = $style->width(' ');
    }

    return $self;
}

sub line {
    my ($class, $style, $width, @c) = @_;
    
    my $ln = $class->new($style);

    while (my $c = shift @c) {
        my $w = $width - ($ln->{w} + ($ln->empty() ? 0 : $ln->{spw}));
        my $last;

        if (ref($c) eq 'Str') {
            my $e = LineStr->new($style, $w);
            while (my ($wrd, $n) = $c->word()) {
                if ($e->add($wrd->{str})) {
                    $c = $n || last;
                    next;
                }
                
                unshift(@c, $c);
                $last = 1;
                last;
            }
            $ln->add($e);
        }
        elsif (($c->{type} eq 'bold') || ($c->{type} eq 'italic')) {
            my $s1 = $style->clone($c->{type} => 1);
            my ($ln1, @c1) = $class->line($s1, $w, @{ $c->{text} });

            if ($ln1->empty()) {
                unshift(@c, $c);
                $last = 1;
                last;
            }
            else {
                $ln->add(@{ $ln1->{elem} });
                if (@c1) {
                    unshift(@c, { %$c, text => [@c1] });
                }
            }
        }
        elsif ($c->{type} eq 'inlinecode') {
            my $s = Str->new($c->{str}, row => $c->{row}, col => $c->{col});
            my $e = LineICode->new($style, $w);
            while (my ($wrd, $n) = $s->word()) {
                if ($e->add($wrd->{str})) {
                    $s = $n || last;
                    next;
                }
                
                unshift(@c, { $s->hinf(), type => 'inlinecode' });
                $last = 1;
                last;
            }
            $ln->add($e);
        }
        elsif ($c->{type} eq 'href') {
            my ($ln1, @c1) = $class->line($style, $w, @{ $c->{text} });

            if ($ln1->empty()) {
                unshift(@c, $c);
                $last = 1;
                last;
            }
            else {
                my $href = LineHref->new($ln1->{w}, $ln1->{h}, $ln1->{spcnt}, $c->{url});
                # $href должен быть перед текстовыми элементами, чтобы были
                # корректными x и y.
                # И т.к. $href является отдельным элементом, надо доработать
                # межэлементные интервалы: у $href nospl должен соответствовать
                # первому элементу в $ln1->{elem}, а для первого элемента
                # nospl должен быть обязательно установлен, чтобы не было
                # промежутков между $href и $ln1->{elem}.
                my $e0 = $ln1->{elem}->[0];
                $href->{nospl} = 1 if $e0->{nospl};
                $e0->{nospl} = 1;
                $ln->add($href, @{ $ln1->{elem} });
                if (@c1) {
                    unshift(@c, { %$c, text => [@c1] });
                }
            }
        }
        elsif ($c->{type} eq 'image') {
            my $img = eval { $style->{out}->_image($c->{url}) };

            my $e;
            if ($img) {
                $e = LineImg->new($img, $c->{url}, $c->{title});
            }
            elsif ($c->{alt}) {
                $e = LineStr->new($style);
                $e->add('[' . $c->{alt} . ']');
            }

            $e || next;

            if (($e->{w} > $w) && !$ln->empty()) {
                unshift(@c, $c);
                $last = 1;
            }
            else {
                $ln->add( $e );
            }
        }

        last if $last;
    }
    
    if (@c) {
        # есть ещё контент, поэтому эту строчку надо растянуть
        $ln->justify($width);
    }

    return $ln, @c;
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

sub add {
    my $self = shift;

    foreach my $e (@_) {
        next if $e->empty();

        if (@{ $self->{elem} } && !$e->{nospl} && $self->{spw}) {
            $self->{w} += $self->{spw};
            $self->{spcnt} ++;
        }
        if ($e->{w}) {
            $self->{w} += $e->{w};
        }

        $self->{h} = $e->{h} if $self->{h} < $e->{h};

        if ($e->{spcnt}) {
            $self->{spcnt} += $e->{spcnt};
        }

        push @{ $self->{elem} }, $e;
    }
}

sub justify {
    my ($self, $width) = @_;

    return if !$self->{spcnt} || ($width < $self->{w});

    $self->{ws} = ($width - $self->{w}) / $self->{spcnt};
    $_->{ws} = $self->{ws} foreach @{ $self->{elem} };
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
            $p->dx($self->{spw} + $self->{ws});
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

package TextBlock;
# Текстовый подблок.
#
# Содержит в себе одну или несколько LineFull.
#
# Требуется там, где нам надо изменить геометрию блока,
# куда надо вывести текст.
#
# Для Page ведёт себя так же, как и LineFull

sub new {
    my ($class, $maxw, $maxh) = @_;

    return bless(
        {
            w       => 0,
            h       => 0,
            maxw    => $maxw,
            maxh    => $maxh,
            line    => []
        },
        $class
    );
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

sub run {
    my ($self, $p, $dx, $dy) = @_;

    $dx ||= 0;
    $dy ||= 0;
    my $x = $p->{x} + $dx;
    my $y = $p->{y};
    $p->{y} += $self->{h} - $dy;

    foreach my $ln (@{ $self->{line} }) {
        $p->{x} = $x;
        $p->{y} -= $ln->{h};
        $ln->run($p);
    }

    $p->{y} = $y; # необходимо восстановить y
}

package TextBox;
use base 'TextBlock';

sub new {
    my ($class, $maxw, $maxh, $pad) = @_;

    $pad //= 16;
    my $self = $class->SUPER::new($maxw - $pad * 2, $maxh);
    $self->{h} += $pad * 2;
    $self->{pad} = $pad;
    
    return $self;
}

sub run {
    my ($self, $p) = @_;

    $p->gfxcol('#888');
    $p->rrect($p->{x}, $p->{y}, $self->{maxw} + $self->{pad}*2, $self->{h}, ($self->{pad} || 10) / 2);

    my $t = $p->_text()->{o};
    $t->fill_color('#fff');
    $self->SUPER::run($p, $self->{pad}, $self->{pad} - 2);
    $t->fill_color('#000');
}

package TextQuote;
use base 'TextBlock';

sub new {
    my ($class, $maxw, $maxh, $pad) = @_;

    $pad //= 20;
    my $self = $class->SUPER::new($maxw - $pad, $maxh);
    $self->{pad} = $pad;
    
    return $self;
}

sub run {
    my ($self, $p) = @_;

    #$p->gfxcol('#888');
    #$p->rrect($p->{x}, $p->{y}, $self->{maxw} + $self->{pad}*2, $self->{h}, ($self->{pad} || 10) / 2);

    $self->SUPER::run($p, $self->{pad});
}




# ============================================================
#
#       Page
#
# ============================================================

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

=cut


# ============================================================
#
#       Frame
#
# ============================================================

# Принцип работыFrame-блоков двухэтапный:
#
# 1. Сначала мы формируем структуру, в которой нам надо знать
# только допустимые границы (w/h), на каждом уровне набиваем
# элементами.
#
# На этой стадии нам надо будет иметь возможность запрашивать
# выделение следующего фрейма с подвариантами:
#   а) оставить заполненный фрейм в том месте, где он и выделялся
#   б) запросить новый фрейм у уровня выше и перенести
#   туда всё, что мы только что заполняли на текущем уровне,
#   с обновлением параметров границ.
#
# Т.е. на текущем уровне вложенности мы будем просто заполнять
# элементами, а в случае переполнения на каком-то из уровней
# должно автоматически приняться необходимое решение, как именно
# выполнить переход к следующему фрейму.
#
# 2. Имея полную структуру с размерами на каждом уровне
# будем отрисовывать все элементы, передавая им текущие x/y.

package Frame;

sub new {
    my $class = shift();

    my $self = bless(
        {
            # Интервал между элементами: основной и дополнительный.
            # Оба интервала суммируются и применяются между элементами,
            # т.е. перед первым элементом отсуп не применяется.
            spc     => 0,
            # Дополнительный интервал применяется снаружи, когда
            # вышестоящий уровень хочет ещё дополнительно увеличить
            # ширину всех своих элементов за счёт интервалов внутри
            # каждого элемента
            spa    => 0,
            @_,
            elem    => [],
        },
        $class
    );

    $self->szupd();

    return $self;
}

sub empty { @{ shift()->{elem} } == 0; }

# проверка, что на данном уровне нас устраивают текущие размеры
sub szchk { 1 }

sub szupd {}
sub _szupd {
    my ($self, $fs, $fm) = @_;
    # fs - суммируемое поле
    # fm - поле с максимальным значением

    $self->{w} = 0;
    $self->{h} = 0;
    foreach my $e (@{ $self->{elem} }) {
        $self->{$fs} += $e->{$fs};
        $self->{$fm} = $e->{$fm} if $self->{$fm} < $e->{$fm};
    }

    my $wcnt = @{ $self->{elem} };
    $self->{$fs} += ($self->{spc} + $self->{spa}) * ($wcnt-1) if $wcnt;
}

sub _max {
    my ($self, $f) = @_;

    my $max = $self->{'max'.$f};
    return $max if defined $max;

    my $own = $self->{own} || return;
    my $m = $own->can($f . 'avail') || return;
    return $m->($own, $self);
}

sub _avail {
    my ($self, $fs, $ef) = @_;

    my $m = $self->can('max' . $fs) || return;
    my $max = $m->($self) // return;

    foreach my $e (@{ $self->{elem} }) {
        next if $ef && ($e eq $ef);
        # Добавочный интервал не применяется при вычислении
        # оставшегося места, используем только основной интервал
        $max -= $e->{$fs} + $self->{spc};
    }

    return $max;
}

sub fulled {
    my $self = shift;
    # когда в текущем блоке место закончилось, надо
    # выполнить рокировку - у вышестоящего уровня
    # вместо себя помещаем свою копию, а себя
    # очищаем и передобавляем
    my $own = $self->{own} || return;

    # Вместо себя в списке текущего own надо оставить
    # копию себя (заменить себя на копию).
    my $dup = bless({ %$self }, ref($self));
    foreach my $e (@{ $own->{elem} }) {
        next if $e ne $self;
        $e = $dup;
        last;
    }

    # А в себе оставляем только @over
    delete $self->{own};
    # В аргументах можно передать новый собственный список
    $self->{elem} = [@_];
    $self->szupd();
    # А себя добавляем в конец списка в own
    $own->add($self);
    # Важно именно в такой последовательности, чтобы 
    # на нашем месте в списке вышестоящего оказалась наша копия,
    # а наш экземпляр объекта оказался в конце и пустым.
    # В этом случае ссылка на наш объект, которая где-то
    # за пределами пытается добавлять в нас новые подэлементы,
    # могла дальше это делать.
}

sub recalc {
    my $self = shift;

    $self->szupd();

    # Если это верх дерева и родителя нет,
    # то мы не сможем в родителе добавить
    # пустую копию себя, поэтому ограничимся
    # тем, что обновим свой размер.
    my $own = $self->{own} || return;

    my @over = (); # непоместившияся подэлементы
    # Мы не будем переносить крайни элемент, если у нас
    # кроме него больше ничего нет - нет никакого смысла
    # оставлять себя пустым. Такая ситуация возможна,
    # если даже один добавляемый элемент не влезает 
    # в выделенную область. Например, если слово слишком
    # длинное, что даже оно одно не влезает в ширину строки.
    # В этом случае оставляем переполнение таким, какое есть.
    while (( @{ $self->{elem} } > 1 ) && !$self->szchk()) {
        # У нас есть возможность удалить лишний элемент
        # а текущий размер нас не устраивает:
        # Удаляем крайнее и снова обновляем свой размер.
        unshift @over, pop( @{ $self->{elem} } );
        $self->szupd();
    }

    # Убеждаемся, что выше по дереву тоже всё в допустимых рамках,
    # это надо сделать до возвращения удалённых @over, чтобы
    # сначала текущая структура закрепилась
    $own->recalc();

    # При переполнении себя делаем передобавление своей копии
    # у вышестоящего уровня
    $self->fulled(@over) if @over;
}

sub add {
    my $self = shift;
    # Допустим, у нас есть дерево элементов:
    #
    #       L0 -> L1 -> L2
    #
    # И мы хотим внутри элемента L2 добавить ещё несколько элементов,
    # после чего обновим размеры L2 -> L1 -> L0. И на каждом из уровней
    # может возникнуть превышение допустимых размеров. И если для L2
    # это превышение способно выясниться ещё до добавления, то для
    # остальных уровней это изменение уже добавленных элементов и список
    # надо пересобрать.

    # В случае переполнения возможны два варианта:
    # 
    # 1. Мы ещё на стадии добавления подэлемента понимаем, что он
    #    не влезет и нужен перенос. Например, при добавлении слова
    #    к строчке.
    #
    # 2. На стадии добавления элемента было всё нормально, но в процессе
    #    его наполнения внутрь себя подэлементами любой степени
    #    вложенности стало понятно, что он превысил допустимый размер.
    #    Например, если в заголовке появилась новая строка, которая
    #    уже не влазит на этой странице, и надо весь заголовок перенести
    #    на следующую.
    #
    # Обработка обоих вариантов позволяет не делать лишнее добавление
    # в список, но в этом случае у нас сильно усложняется алгоритм,
    # появляется много вспомогательных методов, куда надо передавать
    # списком множество аргументов.

    # Для упрощения первую ситуацию будем обрабатывать точно так же,
    # как вторую - сначала добавляем элемент, а потом при пересчёте
    # своего размера принимаем решение о переносе крайнего элемента.
    # В этом случае нам в некоторых случаях придётся делать удаление
    # из списка сразу после добавления в него подэлемента, но зато
    # количество вспомогательных методов сильно сокращается, аргументы
    # в них уже передавать не надо (работаем только с тем, что есть
    # в $self), а логика этих методов сильно упрощается.

    foreach my $e (@_) {
        # выполняем фактическое добавление элемента
        $e->{own} = $self;
        push @{ $self->{elem} }, $e;

        $self->recalc();
    }
}

sub draw {}

package FrameH; # Блок горизонтального заполнения
use base 'Frame';

sub szupd   { shift()->_szupd('w', 'h'); }
sub maxw    { shift()->_max  ('w'); }
sub wavail  { shift()->_avail('w', @_); }

sub szchk {
    my $self = shift;
    my $max = $self->maxw() // return 1;
    return $self->{w} <= $max;
}

sub draw {
    my ($self, $x, $y, @p) = @_;

    foreach my $e (@{ $self->{elem} }) {
        $e->draw($x, $y, @p);
        $x += $e->{w} + $self->{spc} + $self->{spa};
    }
}

package FrameV; # Блок вертикального заполнения
use base 'Frame';

sub szupd   { shift()->_szupd('h', 'w'); }
sub maxh    { shift()->_max  ('h'); }
sub havail  { shift()->_avail('h', @_); }

sub szchk {
    my $self = shift;
    my $max = $self->maxh() // return 1;
    return $self->{h} <= $max;
}

sub draw {
    my ($self, $x, $y, @p) = @_;

    $y += $self->{h};

    foreach my $e (@{ $self->{elem} }) {
        $y -= $e->{h};
        $e->draw($x, $y, @p);
        $y -= $self->{spc} + $self->{spa};
    }
}

#####
# Механизм растягивания за счёт внутренних интервалов между элементами.
# Для этого существует поле spa. Но его ещё надо корректно вычислить.
# У нас может быть строка глубокой вложенности элементов.
# 
# 1. рекурсивно вниз считаем суммарное число элементов
# 2. высчитываем размер одного такого интервала
# 3. снова рекурсивно устанавливаем одинаковый spa для всех
#
# пп 1,3 надо делать только для тех элементов, которые поддерживают
# рекурсивную установку spa
package Justified;

sub spacnt {
    my $self = shift;
    my $cnt = @{ $self->{elem} } || return 0;
    $cnt --;
    foreach my $e (@{ $self->{elem} }) {
        $e->{elem} || next;
        $e->can('spacnt') || next;
        $cnt += $e->spacnt();
    }
    return $cnt;
}

sub spaset {
    my ($self, $spa) = @_;

    foreach my $e (@{ $self->{elem} }) {
        $e->{elem} || next;
        $e->can('spaset') || next;
        $e->spaset($spa);
    }

    $self->{spa} = $spa;
    $self->szupd();
}


# ============================================================
#
#       Элементы нового движка - общий каркас
#
# ============================================================

package FDocument;

sub new {
    my $class = shift();

    my $self = bless(
        {
            @_,
            elem    => [],
        },
        $class
    );

    return $self;
}

sub add {
    my $self = shift;

    $_->{own} = $self foreach @_;
    push @{ $self->{elem} }, @_;
}
# заглушка, которую будут дёргать нижестоящие элементы
sub recalc {}

sub draw {
    my $self = shift;

    $_->draw(@_) foreach @{ $self->{elem} };
}


package FPage;
use base 'FrameV';

sub new {
    my ($class, $size, $mleft, $mright, $mtop, $mbottom) = @_;

    $size       ||= 'A4';
    $mleft      //= 0;
    $mright     //= $mleft;
    $mtop       //= $mright;
    $mbottom    //= $mtop;

    my ($x, $y, $w, $h) = PDF::API2::Page::_to_rectangle($size);

    return $class->SUPER::new(
        margin  => {
            left    => $mleft,
            right   => $mright,
            top     => $mtop,
            bottom  => $mbottom
        },
        size    => $size,
        maxw    => $w - $mleft - $mright, 
        maxh    => $h - $mbottom - $mtop,
        # расстояние между абзацами
        spc     => 12,
    );
}

sub draw {
    my ($self, $pdf) = @_;
    
    my $page = $pdf->page();
    $page->size($self->{size});
    my ($x, $y, $w, $h) = $page->size();

    $y += $h - $self->{margin}->{top};

    my $g = $page->graphics();
    my ($x1,$y1, $x2,$y2) = ($x+$self->{margin}->{left}, $self->{margin}->{bottom}, $x+$w-$self->{margin}->{right}, $y);
    $g->move($x1,$y1);
    $g->hline($x2);
    $g->vline($y2);
    $g->hline($x1);
    $g->vline($y1);
    $g->stroke();

    $x += $self->{margin}->{left};

    foreach my $e (@{ $self->{elem} }) {
        $y -= $e->{h};
        $e->draw($x, $y, $pdf, $page);
        $y -= $self->{spc} + $self->{spa};
    }
}


# ============================================================
#
#       Парсер строчных элементов
#
# ============================================================

package FInlineParser;

sub inadd { shift()->add(@_); }

sub content {
    my $self = shift;

    foreach my $c (@_) {
        if (ref($c) eq 'Str') {
            next if $c->empty(); # попадаются пустые строки с пробелом
            my $e = FStr->new($self->{style});
            $self->inadd($e);
            $e->add($c->{str});
        }
        elsif (($c->{type} eq 'bold') || ($c->{type} eq 'italic')) {
            local $self->{style} = $self->{style}->clone($c->{type} => 1);
            $self->content(@{ $c->{text} });
        }
        elsif ($c->{type} eq 'inlinecode') {
            my $e = InlineCode->new($self->{style});
            $self->inadd($e);
            $e->add($c->{str});
        }
        elsif ($c->{type} eq 'href') {
            my $e = FHref->new($self->{style}, $c->{url});
            $self->inadd($e);
            $e->content(@{ $c->{text} });
        }
        elsif ($c->{type} eq 'image') {
            my $img = eval { $self->{style}->{out}->_image($c->{url}) };

            my $e;
            if ($img) {
                $e = FImage->new($img, $c->{url}, $c->{title});
            }
            elsif ($c->{alt}) {
                $e = FStr->new($self->{style});
                $e->add('[' . $c->{alt} . ']');
            }
            $self->inadd($e);
        }
    }
}

# ============================================================
#
#       Блочные элементы
#
# ============================================================

package FContent;
use base 'FrameV', 'FInlineParser';

sub new {
    my ($class, $style, $width) = @_;
    my $self = $class->SUPER::new(
        style   => $style,
        spc     => $style->height() * 0.2, # расстояние между строками
    );
    $self->{maxw} = $width if defined $width;
    return $self;
}

sub lastline {
    my $self = shift;

    if ($self->empty()) {
        my $ln = FContentLine->new($self->{style}, $self->{maxw});
        $self->add($ln);
        return $ln;
    }

    my $e = $self->{elem};

    return $e->[@$e - 1];
}

sub inadd { shift()->lastline()->add(@_); }

sub draw {
    my ($self, $x, $y, $pdf, $page) = @_;

    my $d = PageDraw->new($page);

    $self->SUPER::draw($x, $y, $pdf, $page, $d);
}

package FContentLine;
use base 'FrameH', 'Justified';

sub new {
    my ($class, $style, $width) = @_;
    my $self = $class->SUPER::new(
        spc     => $style->width(' '),
    );
    $self->{maxw} = $width if defined $width;
    return $self;
}

sub justify {
    my $self = shift;

    my $max = $self->maxw() // return;
    my $spacnt = $self->spacnt() || return;
    $self->spaset(($max - $self->{w}) / $spacnt);
}

sub fulled {
    my $self = shift;
    
    # В случае полного заполнения себя
    # нужно себя растянуть по всей ширине
    $self->justify();

    return $self->SUPER::fulled(@_);
}


# ============================================================
#
#       Строчные элементы
#
# ============================================================

package FStr;
use base 'FrameH', 'Justified';

sub new {
    my ($class, $style) = @_;
    return $class->SUPER::new(
        style   => $style,
        spc     => $style->width(' '),
    );
}

sub add {
    my $self = shift;

    foreach my $s (@_) {
        my @wrd = split /\s+/, (ref($s) eq 'Str') || (ref($s) eq 'HASH') ? $s->{str} : $s;
        shift(@wrd) if @wrd && ($wrd[0] eq '');
        pop(@wrd)   if @wrd && ($wrd[@wrd-1] eq '');

        foreach my $w (@wrd) {
            $w = {
                str => $w,
                w   => $self->{style}->width($w),
                h   => $self->{style}->height(),
            };
        }
        $self->SUPER::add(@wrd);
    }
}

sub draw {
    my ($self, $x, $y, $pdf, $page, $d) = @_;

    $d->font($self->{style}->font());
    
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

    if (my $spa = $self->{spa}) { # указано дополнительное расстояние между словами
        foreach my $e (@{ $self->{elem} }) {
            $d->text($x, $y - $self->{style}->ulpos(), $e->{str});
            $x += $e->{w} + $self->{spc} + $spa;
        }
    }
    else {
        # если текст не надо растягивать, выводим его простой строкой с пробелами
        $d->text($x, $y - $self->{style}->ulpos(), join(' ', map { $_->{str} } @{ $self->{elem} }));
    }
}

package InlineCode;
use base 'FStr';

sub new {
    my $self = shift()->SUPER::new(@_);
    $self->{pad} = $self->{style}->width(' ');
    return $self;
}

sub wavail {
    my $self = shift;
    my $max = $self->SUPER::wavail(@_) // return;
    return $max - $self->{pad} * 2;
}

sub szupd {
    my $self = shift;
    $self->SUPER::szupd(@_);
    $self->{w} += ($self->{pad}||0) * 2;
}

sub draw {
    my ($self, $x, $y, $pdf, $page, $d) = @_;

    $d->gfxcol('#aaa');
    my $yz = $self->{style}->{size} * 0.2 - 1;
    $d->rrect($x, $y - $yz, $self->{w}, $self->{style}->{size} + $yz*2, 4);

    $self->SUPER::draw($x + $self->{pad}, $y, $pdf, $page, $d);
}

package FHref;
use base 'FrameH', 'Justified', 'FInlineParser';

sub new {
    my ($class, $style, $url) = @_;
    return $class->SUPER::new(
        style   => $style,
        spc     => $style->width(' '),
        url     => $url,
    );
}

sub draw {
    my ($self, $x, $y, $pdf, $page, $d) = @_;

    $d->gfxcol('#000');
    my $g = $d->gfx();
    $g->move($x, $y);
    $g->hline($x + $self->{w});
    $g->stroke();

    $self->SUPER::draw($x, $y, $pdf, $page, $d);

    my $an = $page->annotation();
    $an->rect($x, $y, $x + $self->{w}, $y + $self->{h});
    $an->uri($self->{url});
}

package FImage;

sub new {
    my ($class, $img, $url, $title) = @_;

    my $self = bless(
        {
            w   => $img->width(),
            h   => $img->height(),
            img => $img,
            url => $url
        }
    );
    $self->{title} = $title if $title;

    return $self;
}

sub draw {
    my ($self, $x, $y, $pdf, $page, $d) = @_;

    $page->object($self->{img}, $x, $y);
}


# ============================================================
#
#       Блок-абзацы
#
# ============================================================

package FHeader;
use base 'FContent';

# этот блок неразрывный, поэтому не даём себя разрезать на части в recalc,
# сразу перенаправляем этот запрос выше
sub recalc {
    my $self = shift();

    $self->szupd();

    my $own = $self->{own} || return;
    $own->recalc();

    # Но задача усложняется ещё и тем, что нам надо не просто поместиться
    # на странице, но ещё чтобы после нас поместилась хотябы одна строчка.
    # Проверяем в самом ли конце списка родителя мы
    return if $own->empty() || ($own->{elem}->[ @{ $own->{elem} } - 1 ] ne $self);
    # Смотрим, сколько ещё места осталось у родителя, вместе с нами:
    return if $own->havail() > $own->{spc} + 15;

    # вырезаем себя у родителя (текущей страницы)
    pop @{ $own->{elem} };
    # просим страницу передобавиться и возвращаем себя
    $own->fulled($self);
}















# ============================================================
#
#       Ещё одана концептуальная переработка принципов
#       формирования и отрисовки контента
#
# ============================================================

=pod

    Разобъём процесс формирования PDF-документа на три части:

    1. Раскидаем пришедший на входе контент по дереву объектов,
    которые определяют собственное поведение:

        - при распределении пространства на странице,
        - при отрисовке.

        Тут мы только раскидаем по объектам, раздробив, насколько
        это возможно содержимое (все строки режутся на слова).

        На этой стадии нам ничего не нужно знать о размерах,
        поэтому никакие объекты ($pdf, $page и т.д.) нам сюда
        передавать не требуется. Только формируем структуру.
    
    2. Заставляем всех рекурсивно вниз обновить свои размеры

        Это можно было бы сделать и на предыдущем этапе, но для этого
        нужно заморачиваться, как передавать вспомогательные инструменты
        ещё при формировании структуры. А так мы это всё можем рекурсивно
        передать одной командой, одинаковым списком аргументов для всех.
    
    3. Распределение пространства.

        Начиная с самого верхнего уровня мы вызываем метод stage3layout,
        в который передадим:

        - допустимые границы, в которые необходимо уместиться
        - ссылку на процедуры, которые позволят внутри stage3layout
        определить, что делать, если в допустимые границы
        мы не влазим.

        На данной стадии нам нужно будет знать о размерах,
        начиная с самого глубинного элемента и обратно
        наружу, поэтому рекурсивно придётся передавать
        элементы вроде $pdf, $page и т.д.
    
    4. Отрисовка документа

        Здесь мы выполняем непосредственную отрисовку всех
        элементов в уже известных координатах.

    
    Этот концепт отличается от предыдущего, в котором первые
    два пункта были совмещены в один - мы тыпались распределять
    пространство уже сразу на стадии добавления в структуру.
    Как мне показалось в процессе реализации, эта логика
    всё ещё сложновата, если вернуться к ней, спустя время,
    когда потребуется что-то доработать.

    С третьим этапом отрисовки уже всё отработано надёжно.
    К этому моменту мы уже будем точно знать размеры, занимаемые
    элементами на странице. И нам останется только, спускаясь
    от вершины дерева к нижним уровням, сформировать координаты
    отрисовки, отталкиваясь от размеров элементов. А в процессе
    спуска вглубь, будем передавать дополнительные объекты для
    отрисовки: $pdf, $page ... и т.д.

=cut

package DNode;

sub new {
    my $class = shift();
    return bless({ @_, chld => [] }, $class);
}

sub dup {
    my $self = shift;
    return bless { %$self, chld => [ @_ ] }, ref($self);
}

sub add {
    my $self = shift;
    push @{ $self->{chld} }, @_;
}

sub empty { return  @{ shift()->{chld} } == 0; }

sub szchld {}
# Метод szchld нужен, чтобы обновить свой размер с учётом списка потомков.
# Тем узлам, чьи размеры не зависят от их вложенных элементов, этот
# метод не нужен.
sub _szchld {
    my ($self, $fs, $fm) = @_;
    # fs - суммируемое поле
    # fm - поле с максимальным значением

    $self->{w} = 0;
    $self->{h} = 0;
    foreach my $c (@{ $self->{chld} }) {
        $self->{$fs} += $c->{$fs};
        $self->{$fm} = $c->{$fm} if $self->{$fm} < $c->{$fm};
    }

    my $wcnt = @{ $self->{chld} };
    $self->{$fs} += ($self->{spc} + $self->{spa}) * ($wcnt-1) if $wcnt;
}

sub stage2size {
    my $self = shift;
    # метод для рекурсивного обновления всего дерева с одинаковым
    # набором аргументов. Самые нижние узлы, у которых нет или
    # не может быть вложенных элементов, должны обновить только свой размер.
    $_->stage2size(@_) foreach @{ $self->{chld} || [] };

    $self->{spc} ||= 0;
    $self->{spa} = 0;
    $self->szchld();
}

sub restw {}
sub resth {}
sub _rest {
    my ($self, $fs, $sz) = @_;
    # зная размерности всех элементов, мы можем их спокойно распределить
    # по структуре. Для этого на входе получаем поле размерности и значение
    # размерности. Для горизонтальных элементов это 'w' и максимальная ширина,
    # для вертикальных элементов это 'h' и макмимальная высота.
    #
    # Вернуть этот метод должен два варианта:
    # undef - если элемент неразделим и не может вместиться в данный размер
    # [...] - если элемент смог вместиться в указанный размер, то он
    #       возвращает список своих подэлементов, которые не влезли в этот
    #       размер. Если список пуст, значит все подэлементы влезли.

    my @chld = ();
    my @over = @{ $self->{chld} };
    while (my ($c) = @over) {
        if (@chld) {
            # хватает ли места хотябы на интервал между элементами
            $sz -= $self->{spc};
            last if $sz <= 0;
        }

        if ($c->{$fs} <= $sz) {
            # если на элемент хватает место целиком, то мы его
            # так и оставляем
            push @chld, shift @over;
            $sz -= $c->{$fs};
            next;
        }

        # Если это вообще не объект, так же завершаем задачу разделения
        last if !ref($c) || (ref($c) eq 'HASH');

        # если места на очередной элемент не хватило,
        # просим его уместиться в той же размерности
        my $restm = 'rest' . $fs;
        # если элемент не может уместиться, перенесём его целиком
        $c->can($restm) || last;
        my $over = $c->$restm($sz) || last;

        @$over || next; # элемент сообщил нам, что уместился весь.
        # эту проверку выполняем на всякий случай, но такая
        # ситуация может возникнуть только если у элемента
        # ошибка в его размерах w/h, которые мы уже проверили выше.
        
        # текущий элемент, видя, что не смог вместить всё, должен
        # сам обрезать своё содержимое и обновить свой размер.
        # поэтому тут мы его добавляем не глядя
        push @chld, shift @over;

        # а вернул нам элемент свой подэлементы, которые не вошли
        # в тот размер, который мы ему передали, поэтому сделаем
        # копию этого элемента и отдадим ему этот остаток.
        my $dup = $c->dup(@$over);
        $dup->szchld();
        # эта копия зайдёт в следующий раз
        unshift @over, $dup;
        # А мы на этом должны уже прерваться, т.к. понятно, что
        # больше в нас ничего не влезет.
        last;
    }

    @chld || return; # если вообще не смогли разделить
    @over || return []; # если вдруг в нас всё влезло

    # Если есть невлезшие элементы, обрежем свой список и обновим размер
    $self->{chld} = [@chld];
    $self->szchld();

    # и возвращаем невлезший остаток
    return [@over];
}

sub laynode {  }
sub _laynode {
    my ($self, $fs, $sz) = @_;
    # этот метод применяется в точке перехода к уровню вертикального
    # или горизонтального заполнения. Например, FContent сам является
    # уровнем вертикального заполнения, но все его подэлементы - это
    # уже уровень горизонтального заполнения.
    #
    # Поэтому внутри FContent необходимо определить метод:
    # sub laynode { shift()->_laynode('w', $_[0]); }
    #
    # В результате, ответвление от stage3layout внутри FContent выполнит вмещение
    # в горизонтальный размер $w всех более глубоких уровней. Он порежет
    # горизонтальные строчки в нужных местах, сместив их вниз. После этого,
    # у всех нижестоящих элементов зафиксируется их высота, и можно будет
    # на уровне DDocument выполнять аналогичное разделение контента вглубь
    # уже по вертикальному размеру $h (разделение на страницы).

    # Если наш размер уже вписывается в заданный, то необходимости
    # лезть вглубь элементов уже и не будет.
    return if $self->{$fs} <= $sz;

    # Для сравнения, логика методов restX:
    # При вызове этот метод на входе получает размер, этот размер ему надо
    # разделить между всеми chld. Для этого он сначала смотрит первый
    # подэлемент, подом для второго остаётся места меньше на размер первого
    # элемента - и т.д.
    # В итоге, например, вызывая для FLine метод restw, он отрежет от строки
    # всё, что за пределами $sz.

    # И уже в этом методе мы не уменьшаем размер. Например, если мы вызываемся
    # из FContent (содержит внутри себя строки FLine), который является
    # уже блоком вертикального заполнения, то мы:
    # - отрезаем от первого своего chld (FLine) всё, что за границами $sz,
    # - помещаем отрезанное в новый FLine (копия предыдущего),
    # - помещаем новый FLine следом за первым...
    # и т.д.

    my @chld = ();
    my @prev = @{ $self->{chld} };
    while (my $c = shift @prev) {
        push @chld, $c;
        next if $c->{$fs} <= $sz;
        my $restm = 'rest' . $fs;
        # если элемент не может уместиться, оставим его таким, как есть
        $c->can($restm) || next;
        my $over = $c->$restm($sz) || next;
        @$over || next; # почему-то элемент уместился весь,
                        # хотя мы проверяли его размер выше
        
        # Помещаем остаток в такой же экземпляр
        my $dup = $c->dup(@$over);
        $dup->szchld();
        # повторно проверим остаток на следующей итерации
        unshift @prev, $dup;
    }

    $self->{chld} = [@chld];
    $self->szchld();
    1;  # сигнал вышестоящим о том, что произведены изменения в размерах
        # и их надо обновить выше
}

sub stage3layout {
    my $self = shift;
    # этот метод нужен, чтобы рекурсивно вниз ко всем нижестоящим уровням
    # передать границы области, в которую необходимо поместиться.
    # На самом верхнем уровне DDocument сделает ответвление через laynode
    # в рекурсивное разделение контента по вертикали (на страницы).
    # Но перед этим сначала выполнится ответвление на уровне FContent
    # вглудь своих подэлементов, чтобы уместить их в горизонтальный размер,
    # разделив там, где это нужно.
    #
    # Этот метод переопределяют только узлы, где жёсткие границы меняются.
    # Например, DPage задаёт так свою ширину и высоту.
    # Уровнем ниже может оказаться ячейка таблицы, которая изменит ширину.
    my $chg = 0;
    foreach my $c (@{ $self->{chld} || [] }) {
        next if !ref($c) || (ref($c) eq 'HASH');
        $chg ++ if $c->stage3layout(@_);
    }
    $self->szchld() if $chg;
    $chg ++ if $self->laynode(@_);
    return $chg;
}

sub draw {
    my $self = shift;
    $_->draw(@_) foreach @{ $self->{chld} };
}


package DNodeH;     # узел вертикального заполнения
use base 'DNode';

sub szchld  { shift()->_szchld('w', 'h'); }
sub restw   { shift()->_rest  ('w', @_); }

sub draw {
    my ($self, $x, @p) = @_;

    foreach my $c (@{ $self->{chld} }) {
        $c->draw($x, @p);
        $x += $c->{w} + $self->{spc} + $self->{spa};
    }
}


package DNodeV;     # узел горизонтального заполнения
use base 'DNode';

sub szchld  { shift()->_szchld('h', 'w'); }
sub resth   { shift()->_rest  ('h', @_); }

sub draw {
    my ($self, $x, $y, @p) = @_;

    $y += $self->{h};

    foreach my $c (@{ $self->{chld} }) {
        $y -= $c->{h};
        $c->draw($x, $y, @p);
        $y -= $self->{spc} + $self->{spa};
    }
}


#####
# Механизм растягивания за счёт внутренних интервалов между элементами.
# Для этого существует поле spa. Но его ещё надо корректно вычислить.
# У нас может быть строка глубокой вложенности элементов.
# 
# 1. рекурсивно вниз считаем суммарное число элементов
# 2. высчитываем размер одного такого интервала
# 3. снова рекурсивно устанавливаем одинаковый spa для всех
#
# пп 1,3 надо делать только для тех элементов, которые поддерживают
# рекурсивную установку spa
#
package DJustify;

sub spacnt {
    my $self = shift;
    my $cnt = @{ $self->{chld} } || return 0;
    $cnt --;
    foreach my $c (@{ $self->{chld} }) {
        $c->{chld} || next;
        $c->can('spacnt') || next;
        $cnt += $c->spacnt();
    }
    return $cnt;
}

sub spaset {
    my ($self, $spa) = @_;

    foreach my $c (@{ $self->{chld} }) {
        $c->{chld} || next;
        $c->can('spaset') || next;
        $c->spaset($spa);
    }

    $self->{spa} = $spa;
    $self->szchld();
}

# Весь этот механизм вставим в метод restX - он обрезает строку
# под нужный размер. Тут нам двойное удобство:
#   1. Именно тут нам удобно узнать, что строка не поместилась вся, она
#      обрезана и этот кусок надо растянуть.
#   2. У нас имеется размер, до которого надо растянуть строку.
sub justify {
    my ($self, $sz) = @_;
    # рассчитываем дополнительные пробельные расстояния
    my $spacnt = $self->spacnt() || return;
    # устанавливаем spa по всему дереву от нас вниз
    $self->spaset(($sz - $self->{w}) / $spacnt);
}

package DParserH;

sub toline { shift()->add(@_); }

sub content {
    my $self = shift;

    foreach my $c (@_) {
        if (ref($c) eq 'Str') {
            my $s = DStr->new($c->{str});
            # попадаются пустые строки, их наличие будет
            # мешать корректному распределению пробелов
            # между словами в строках, состоящих из смешанных
            # элементов.
            next if $s->empty();
            $self->toline($s);
        }
        elsif (($c->{type} eq 'bold') || ($c->{type} eq 'italic')) {
            $self->toline( DContentStyle->new($c->{type}, @{ $c->{text} }) );
        }
        elsif ($c->{type} eq 'inlinecode') {
            $self->toline( DICode->new($c->{str}) );
        }
        elsif ($c->{type} eq 'href') {
            $self->toline( DHref->new($c->{url}, @{ $c->{text} }) );
        }
        elsif ($c->{type} eq 'image') {
            $self->toline( DImage->new($c->{url}, $c->{title}, $c->{alt}) );
        }
    }
}



package DDocument;
use base 'DNodeV';

sub stage3layout {
    my ($self, $size, %m) = @_;

    my ($x, $y, $w, $h) = PDF::API2::Page::_to_rectangle($size);
    my %geom = (
        size=> $size,
        x   => $x + ($m{left}||0),
        y   => $y + ($m{bottom}||0),
        w   => $w - ($m{left}||0) - ($m{right}||0),
        h   => $h - ($m{top}||0) - ($m{bottom}||0),
    );

    # тут надо продублировать $geom{w}, $geom{h} вначале,
    # чтобы они попали в нужном составе в laynode
    $self->SUPER::stage3layout($geom{w}, $geom{h}, %geom);
}

sub laynode { shift()->_laynode('h', $_[1]); }

package DPage;
use base 'DNodeV';

sub stage3layout {
    my ($self, $w, $h, %g) = @_;

    $self->{geom}   = { %g };
    $self->{spc}    = 12;

    $self->SUPER::stage3layout($w, $h);
}

sub draw {
    my ($self, $pdf) = @_;
    
    my $page = $pdf->page();
    my $g = $self->{geom};
    $page->size($g->{size});

    my $gfx = $page->graphics();
    $gfx->move($g->{x}, $g->{y});
    $gfx->hline($g->{x} + $g->{w});
    $gfx->vline($g->{y} + $g->{h});
    $gfx->hline($g->{x});
    $gfx->vline($g->{y});
    $gfx->stroke();

    my $y = $g->{y} + $g->{h};
    foreach my $c (@{ $self->{chld} }) {
        $y -= $c->{h};
        $c->draw($g->{x}, $y, $page, $pdf);
        $y -= $self->{spc} + $self->{spa};
    }
}


package DContent;
use base 'DNodeV', 'DParserH';

sub new {
    my $self = shift()->SUPER::new();
    $self->content(@_);
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{spc} = $p->{style}->height() * 0.2;
    $self->SUPER::stage2size($p, @p);
}

sub draw {
    my ($self, $x, $y, $page, $pdf) = @_;

    my $d = PageDraw->new($page);

    $self->SUPER::draw($x, $y, $d, $page, $pdf);
}

# в laynode приходят два размера: $w, $h - это границы
# радела: страницы, ячейки таблицы и т.д.
sub laynode { shift()->_laynode('w', $_[0]); }

sub toline {
    my $self = shift;

    my $ln;
    if ($self->empty()) {
        $ln = DLine->new();
        $self->add($ln);
    }
    else {
        my $c = $self->{chld};
        $ln = $c->[@$c-1];
    }

    return $ln->add(@_);
}


package DLine;
use base 'DNodeH', 'DJustify';

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{spc} = $p->{style}->width(' ');
    $self->SUPER::stage2size($p, @p);
}

# активация justify для всей строки,
# включая все вложенные элементы, которым
# достаточно прописать base 'DJustify'.
# Метод restX надо переопределять только
# на самом верхнем уровне растягивания.
sub restw {
    my $self = shift;
    my ($sz) = @_;

    my $over = $self->SUPER::restw(@_) || return;
    @$over || return $over; # строка вся влезла

    $self->justify($sz);
    return $over;
}


package DStr;
use base 'DNodeH', 'DJustify';

sub new {
    my $self = shift()->SUPER::new();

    foreach my $s (@_) {
        my @wrd = split /\s+/, (ref($s) eq 'Str') || (ref($s) eq 'HASH') ? $s->{str} : $s;
        shift(@wrd) if @wrd && ($wrd[0] eq '');
        pop(@wrd)   if @wrd && ($wrd[@wrd-1] eq '');

        $self->add(map { { str => $_ } } @wrd);
    }

    return $self;
}

sub stage2size {
    my ($self, $p) = @_;

    my $h = $p->{style}->height();
    foreach my $c (@{ $self->{chld} }) {
        $c->{w} = $p->{style}->width($c->{str});
        $c->{h} = $h;
    }

    $self->{spc} = $p->{style}->width(' ');
    $self->{spa} = 0;
    $self->szchld();

    # доп данные для отрисовки (получить их можем только тут):
    $self->{font}   = [ $p->{style}->font() ];
    $self->{ulpos}  = $p->{style}->ulpos();
}

sub draw {
    my ($self, $x, $y, $d) = @_;

    $d->font(@{ $self->{font} });
    
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

    if (my $spa = $self->{spa}) { # указано дополнительное расстояние между словами
        foreach my $c (@{ $self->{chld} }) {
            $d->text($x, $y - $self->{ulpos}, $c->{str});
            $x += $c->{w} + $self->{spc} + $spa;
        }
    }
    else {
        # если текст не надо растягивать, выводим его простой строкой с пробелами
        $d->text($x, $y - $self->{ulpos}, join(' ', map { $_->{str} } @{ $self->{chld} }));
    }
}

package DContentStyle;
use base 'DNodeH', 'DJustify', 'DParserH';

sub new {
    my $self = shift()->SUPER::new();
    $self->{style} = shift();
    $self->content(@_);
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    local $p->{style} = $p->{style}->clone($self->{style} => 1);
    $self->{spc} = $p->{style}->width(' ');

    $self->SUPER::stage2size($p, @p);
}

package DICode;
use base 'DStr';

sub szchld {
    my $self = shift;
    $self->SUPER::szchld(@_);
    $self->{w} += ($self->{pad}||0) * 2;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{pad} = $p->{style}->width(' ');
    $self->{fsz} = $p->{style}->height();
    $self->{yz} = $p->{style}->height() * 0.2 - 1;

    $self->SUPER::stage2size($p, @p);
}

sub draw {
    my ($self, $x, $y, $d, @p) = @_;

    $d->gfxcol('#aaa');
    $d->rrect($x, $y - $self->{yz}, $self->{w}, $self->{fsz} + $self->{yz}*2, 4);

    $self->SUPER::draw($x + $self->{pad}, $y, $d, @p);
}

package DHref;
use base 'DNodeH', 'DJustify', 'DParserH';

sub new {
    my $self = shift()->SUPER::new();
    $self->{url} = shift();
    $self->content(@_);
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{spc} = $p->{style}->width(' ');

    $self->SUPER::stage2size($p, @p);
}

sub draw {
    my ($self, $x, $y, $d, $page, @p) = @_;

    $d->gfxcol('#000');
    my $g = $d->gfx();
    $g->move($x, $y);
    $g->hline($x + $self->{w});
    $g->stroke();

    $self->SUPER::draw($x, $y, $d, $page, @p);

    my $an = $page->annotation();
    $an->rect($x, $y, $x + $self->{w}, $y + $self->{h});
    $an->uri($self->{url});
}

package DImage;

sub new {
    my ($class, $url, $title, $alt) = @_;

    my $self = bless({ url => $url }, $class);
    $self->{title} = $title if $title;
    $self->{alt} = DStr->new('[' . $alt . ']') if $alt;

    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    eval { $self->{img} = $p->_image($self->{url}) };
    if (my $img = $self->{img}) {
        $self->{w} = $img->width();
        $self->{h} = $img->height();
    }
    elsif (my $alt = $self->{alt}) {
        $alt->stage2size($p, @p);
        $self->{w} = $alt->{w};
        $self->{h} = $alt->{h};
    }
    else {
        $self->{w} = 0;
        $self->{h} = 0;
    }
}

sub stage3layout {}

sub draw {
    my ($self, $x, $y, $d, $page, @p) = @_;

    if ($self->{img}) {
        $page->object($self->{img}, $x, $y);
    }
    elsif ($self->{alt}) {
        $self->{alt}->draw($x, $y, $d, $page, @p);
    }
}


package DHeader;
use base 'DContent';

sub new {
    my $class = shift;
    my $deep = shift;

    my $self = $class->SUPER::new(@_);
    $self->{deep} = $deep;

    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    my @size = ( 22, 18, 14, 12, 11 );
    my $sz = ($self->{deep} > 0) && ($self->{deep} <= @size) ? $size[ $self->{deep} - 1 ] : $size[ @size-1 ];

    local $p->{style} = $p->{style}->clone(bold => 1, size => $sz);
    $self->{spc} = $p->{style}->width(' ');

    $self->SUPER::stage2size($p, @p);
}

sub resth {} # вертикальная неразрывность содержимого

1;
