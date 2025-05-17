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

    $self->{doc} = DDocument->new();
    $self->{ctx} = DPage->new();
    $self->{doc}->add($self->{ctx});
    $self->{style} = SStyle->new($self, font => 'Arial.ttf', size => 11);

    return $self;
}

sub data {
    my $self = shift;

    # К этому моменту мы выполнили только первый этап - сформировали
    # базовую структуру и ещё ничего не знаем о размерностях.

    # На втором этапе мы должны задать размеры всем элементам. Для
    # этого нужно будет импортировать в $pdf шрифты и изображения,
    # Без этого не узнаем размеры элементарных объектов.
    $self->{doc}->stage2size($self);

    # Теперь распределяем согласно нашим размерам.
    # Сверху до уровня страниц нам надо передать размерность страницы
    # и размеры всех полей.
    $self->{doc}->stage3layout('A4', %{ $self->{margin} });

    # И, наконец, выводим содержимое
    $self->{doc}->stage4draw( $self->{pdf} );
    
    return $self->{pdf}->to_string();
}

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

sub modifier {
    my ($self, %p) = @_;

    if ($p{name} eq 'pagebreak') {
        return if (ref($self->{ctx}) ne 'DPage') || $self->{ctx}->empty();
        $self->{ctx} = DPage->new();
        $self->{doc}->add($self->{ctx});
    }
}

sub header {
    my ($self, %p) = @_;

    my $c = DHeader->new($p{deep}, @{ $p{ content } });
    $self->{ctx}->add( $c );
}

sub code {
    # для code хорошо бы сделать парсинг кода,
    # но пока просто доблируем работу textblock
    textblock(@_);
}

sub textblock {
    my ($self, %p) = @_;
    
    my $c = DTextBlock->new(@{ $p{ text } });
    $self->{ctx}->add( $c );

}

sub quote {
    my ($self, %p) = @_;

    my $c = DQuote->new();
    $self->{ctx}->add( $c );

    local $self->{ctx} = $c;
    $self->make(@{ $p{ content } });
}

sub listitem {
    my ($self, %p) = @_;

    my $c = DListItem->new($p{mode} eq 'ord' ? int($p{num}) . '.' : ' ' . $p{mode});
    $self->{ctx}->add( $c );

    local $self->{ctx} = $c;
    $self->paragraph(content => $p{title});
    $self->make(@{ $p{ content } }) if $p{ content };
}

sub paragraph {
    my ($self, %p) = @_;

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

    my $self = bless { out => $out }, $class;
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

# ============================================================
#
#       Базовые узлы (основной функционал движка)
#
# ============================================================

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

sub stage4draw {
    my $self = shift;
    $_->stage4draw(@_) foreach @{ $self->{chld} };
}


package DNodeH;     # узел вертикального заполнения
use base 'DNode';

sub szchld  { shift()->_szchld('w', 'h'); }
sub restw   { shift()->_rest  ('w', @_); }

sub stage4draw {
    my ($self, $x, @p) = @_;

    foreach my $c (@{ $self->{chld} }) {
        $c->stage4draw($x, @p);
        $x += $c->{w} + $self->{spc} + $self->{spa};
    }
}


package DNodeV;     # узел горизонтального заполнения
use base 'DNode';

sub szchld  { shift()->_szchld('h', 'w'); }
sub resth   { shift()->_rest  ('h', @_); }

sub stage4draw {
    my ($self, $x, $y, @p) = @_;

    $y += $self->{h};

    foreach my $c (@{ $self->{chld} }) {
        $y -= $c->{h};
        $c->stage4draw($x, $y, @p);
        $y -= $self->{spc} + $self->{spa};
    }
}


# ============================================================
#
#       Вспомогательный доп-классы (инструменты)
#
# ============================================================

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




# ============================================================
#
#       Структура документа
#
# ============================================================

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

sub stage4draw {
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
        $c->stage4draw($g->{x}, $y, $page, $pdf);
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

sub stage4draw {
    my ($self, $x, $y, $page, $pdf) = @_;

    my $d = PageDraw->new($page);

    $self->SUPER::stage4draw($x, $y, $d, $page, $pdf);
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





# ============================================================
#
#       Части строк (горизонтальные элементы)
#
# ============================================================

package DStr;
use base 'DNodeH', 'DJustify';

sub new {
    my $self = shift()->SUPER::new();
    $self->addwrd(@_);
    return $self;
}

sub addwrd {
    my $self = shift;

    foreach my $s (@_) {
        my @wrd = split /\s+/, (ref($s) eq 'Str') || (ref($s) eq 'HASH') ? $s->{str} : $s;
        shift(@wrd) if @wrd && ($wrd[0] eq '');
        pop(@wrd)   if @wrd && ($wrd[@wrd-1] eq '');

        $self->add(map { { str => $_ } } @wrd);
    }
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

sub stage4draw {
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

sub stage4draw {
    my ($self, $x, $y, $d, @p) = @_;

    $d->gfxcol('#aaa');
    $d->rrect($x, $y - $self->{yz}, $self->{w}, $self->{fsz} + $self->{yz}*2, 4);

    $self->SUPER::stage4draw($x + $self->{pad}, $y, $d, @p);
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

sub stage4draw {
    my ($self, $x, $y, $d, $page, @p) = @_;

    $d->gfxcol('#000');
    my $g = $d->gfx();
    $g->move($x, $y);
    $g->hline($x + $self->{w});
    $g->stroke();

    $self->SUPER::stage4draw($x, $y, $d, $page, @p);

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

sub stage4draw {
    my ($self, $x, $y, $d, $page, @p) = @_;

    if ($self->{img}) {
        $page->object($self->{img}, $x, $y);
    }
    elsif ($self->{alt}) {
        $self->{alt}->stage4draw($x, $y, $d, $page, @p);
    }
}





# ============================================================
#
#       Блочные элементы страницы
#
# ============================================================


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

package DTextBlock;
use base 'DNodeV';

sub new {
    my $self = shift()->SUPER::new();
    $self->addstr(@_);
    return $self;
}

sub addstr {
    my $self = shift;

    $self->add(
        map {
            {
                str => (ref eq 'Str') || (ref eq 'HASH') ? $_->{str} : $_
            }
        } @_
    );
}

sub szchld {
    my $self = shift;
    $self->SUPER::szchld(@_);
    $self->{w} += ($self->{padw}||0) * 2;
    $self->{h} += ($self->{padw}||0) * 2;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    my $style = $p->{style}->clone(font => 'PTMonoBold.ttf');

    $self->{font}   = [ $style->font() ];
    $self->{ulpos}  = $style->ulpos();

    $self->{padw} = $style->width(' ');
    $self->{padh} = $style->height() * 0.7;
    $self->{spc} = $style->height() * 0.2;
    $self->{spa} = 0;
    $self->{yz} = $style->height() * 0.2;

    my $h = $p->{style}->height();
    foreach my $c (@{ $self->{chld} }) {
        $c->{w} = $style->width($c->{str});
        $c->{h} = $h;
    }

    $self->szchld();
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->{cntw} = $w;

    $self->SUPER::stage3layout($w, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page) = @_;

    my $d = PageDraw->new($page);

    $d->gfxcol('#888');
    $d->rrect($x, $y, $self->{cntw}, $self->{h}, 4);

    $x += $self->{padw};
    $y += $self->{h} - $self->{padh} + $self->{yz};

    $d->font(@{ $self->{font} });
    my $t = $d->_text();
    $t->fill_color('#fff');

    foreach my $c (@{ $self->{chld} }) {
        $y -= $c->{h};
        $d->text($x, $y - $self->{ulpos}, $c->{str});
        $y -= $self->{spc} + $self->{spa};
    }

    $t->fill_color('#000');
}



package DQuote;
use base 'DNodeV';

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{spc}    = 12;
    $self->{pad}    = 12;

    $self->SUPER::stage2size($p, @p);
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->SUPER::stage3layout($w - $self->{pad}, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page) = @_;

    my $gfx = $page->graphics();
    $gfx->move($x, $y);
    $gfx->vline($y + $self->{h});
    $gfx->stroke();
    $gfx->move($x+2, $y);
    $gfx->vline($y + $self->{h});
    $gfx->stroke();
    $gfx->move($x+4, $y);
    $gfx->vline($y + $self->{h});
    $gfx->stroke();

    $self->SUPER::stage4draw($x + $self->{pad}, $y, $page);
}



package DListItem;
use base 'DNodeV';

sub new {
    my $self = shift()->SUPER::new();
    $self->{num} = shift();
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{spc}    = 12;
    $self->{pad}    = 20;
    $self->{nw}     = $p->{style}->width($self->{num} . ' ');
    $self->{font}   = [ $p->{style}->font() ];
    $self->{ulpos}  = $p->{style}->ulpos();

    $self->SUPER::stage2size($p, @p);
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->SUPER::stage3layout($w - $self->{pad}, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page) = @_;

    my $d = PageDraw->new($page);
    $d->font(@{ $self->{font} });
    $d->text(
        $x + $self->{pad} - $self->{nw},
        $y + $self->{h} - $self->{font}->[1] - $self->{ulpos},
        $self->{num}
    );

    $self->SUPER::stage4draw($x + $self->{pad}, $y, $page);
}


1;
