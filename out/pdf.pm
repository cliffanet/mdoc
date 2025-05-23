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

sub hline {
    my ($self, %p) = @_;

    my $c = DHLine->new(@{ $p{ title } });
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

sub table {
    my ($self, %p) = @_;

    my $tbl = DTable->new($p{mode}, $p{width}, $p{align});
    $self->{ctx}->add( $tbl );

    $tbl->addhdr(@{ $p{hdr} }) if @{ $p{hdr}||[] };
    $tbl->addrow(@$_) foreach @{ $p{row}||[] };
}



# ============================================================
# ============================================================
#
#       SStyle
#
# ============================================================
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

# ============================================================
# ============================================================
#
#       PageDraw
#
# ============================================================
# ============================================================

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
# ============================================================
#
#       Базовые узлы (основной функционал движка)
#
# ============================================================
# ============================================================


# ============================================================
# ============================================================
package DSumIterator;

sub new {
    my ($class, $node, $f, $spa) = @_;
    my $m = $f.'spc';
    my $szfull = ($node->{$f.'beg'}||0) + ($node->{$f.'end'}||0);
    return bless(
        {
            n       => 0,               # сколько всего получено элементов
            f       => $f,              # поле w/h, по которому делаем отсчёт
            bybeg   => 0,               # отступ от самого начала отсчёта
            byprv   => 0,               # отступ от начала предыдущего элемента
            szfull  => $szfull,         # полное расстояние, включая текущий элемент
            spc     => $node->$m()||0,  # пробельное расстояние между элементами
            spa     => $spa // $node->{$f.'spa'} // 0, # дополнительное пробельное расстояние
            # Механизм полей wbeg/hbeg/wend/hend - эти поля предполагают
            # отступ внутри своего размера до первого элемента и после крайнего.
            # Это нужно учитывать именно тут, т.к. это влияет на определение
            # суммарного размера при попытке разрезать элемент на части
            # методами layout/wsplit/hsplit
            szbeg   => $node->{$f.'beg'}||0,
            szend   => $node->{$f.'end'}||0,

            chld    => $node->{chld},
        },
        $class
    );
}

sub avail {
    my $self = shift;
    my $beg = $self->{n};
    my $end = @{ $self->{chld} } - 1;
    return if $beg > $end;
    return (@{ $self->{chld} })[$beg .. $end];
}

sub fetch {
    my $self = shift;

    return if $self->{n} >= @{ $self->{chld} };
    my $c = $self->{chld}->[ $self->{n} ];
    $self->{n} ++;

    $self->{byprv} =
        $self->{n} > 1 ?
            $self->{sz} + $self->{spc} + $self->{spa} :
            $self->{szbeg};
    $self->{bybeg} += $self->{byprv};

    my $f = $self->{f};
    $self->{sz} = ref($c) eq 'HASH' ? $c->{$f}||0 : $c->$f($self->{spa});
    
    $self->{szfull} = $self->{bybeg} + $self->{sz} + $self->{szend};

    return $c;
}

sub full {
    my $self = shift;
    while ($self->fetch()) {}
    return $self->{szfull};
}

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

sub empty   { return  @{ shift()->{chld} } == 0; }

# Получение размеров элемента.
#
# До этого использовались статические размеры w/h в полях объекта,
# которые обновлялись в stage2size, но этот размеры могут меняться
# и на других этапах, например при изменении количества подэлементов
# или размеров отступов. Поэтому принято решение - каждый раз считать
# размер, когда его надо получить вышестоящему элементу. Это немного
# накладно, т.к. каждый раз мы запускаем рекурсию до самых глубин,
# однако, так надёжнее и проще с т.з. формирования дополнительных
# отступов и прочих изменений размеров на разных стадиях.
#
# Чтобы немного разгрузить накладные расходы на рекурсию до низу,
# мы разделим методы получения размеров по длинной и короткой
# сторонам. Как правило, нам нужно знать только длину/высоту,
# и чаще всего - это длинная сторона. Но, например, для вычисления
# высоты содержимого страницы нам не нужно знать ширину строк,
# а только её высоту, что будет сильно экономнее на рекурсии.
#
# У нас система со сложной иерархией, где несколько раз
# происходит переход от элементов горизонтального наполнения
# к элементам вертикального наполнения и обратно.
# Например: страница (верт наполнение) - строка (гор наполн.).
# Тут всё просто, один переход, но в случае с таблицей:
# Страница - таблица (верт нап) - ряд (гор нап) - ячейка (верт)
#
# Чтобы не запутаться, введём набор w/h-методов, отвечающих
# за линейные размеры и интервалы между объектами. Обойтись
# простыми методами long()/shrt(), которые определят размер
# по длинной и короткой сторонам, не получится, т.к. в
# узлах перехода между горизонтальными и вертикальными
# наполнения будут наложения и путанницы.

# w() и h() - ширина и высота - это собственные линейные размеры,
# которые объект будет демонстрировать всем.
sub w { shift()->{w}||0 }
sub h { shift()->{h}||0 }

# wspc() и hspc() - горизонтальные и вертикальные интервалы
# между своими подэлементами
sub wspc { shift()->{wspc}||0 }
sub hspc { shift()->{hspc}||0 }

# wsum() и hsum() - это суммарный размер всех своих подэлементов
# по ширине или по высоте. Внутри этих методов вызываются
# w()/h() для всех своих подэлементов и собственый wspc()/hspc().
sub sumi { DSumIterator->new(@_); }
sub wsum { shift()->sumi('w', shift())->full(); }
sub hsum { shift()->sumi('h', shift())->full(); }

# wmax()/hmax() - максимальный размер из всех своих подэлементов
sub _max {
    my ($self, $f) = @_;
    
    my $max = 0;
    foreach my $c (@{ $self->{chld} }) {
        my $v = ref($c) eq 'HASH' ? $c->{$f} : $c->$f();
        $max = $v if $max < $v;
    }

    return ($self->{$f.'beg'}||0) + $max + ($self->{$f.'end'}||0);
}
sub wmax { shift()->_max('w'); }
sub hmax { shift()->_max('h'); }

sub stage2size {
    my $self = shift;
    $_->stage2size(@_) foreach @{ $self->{chld} };
}

# механизм работы с интервалами и justify за счёт них
sub _spcnt {
    my ($self, $f) = @_;

    my $spcnt = 0;
    my $m = $f.'spc';
    my $spc = $self->$m();
    $m = $f.'spcnt';
    my $p = undef;
    foreach my $c (@{ $self->{chld} }) {
        # между элементами на текущем уровне местом разрыва считается:
        #   - наличие базового интервала у $self
        #   - отсутствие у предыдущего элемента флага nobgend
        #   - отсутствие у текущего элемента флага nobrbeg
        if ($p && $spc && !$p->{nobgend} && !$c->{nobrbeg}) {
            $spcnt ++;
        }
        if ($c->{chld} && (ref($c) ne 'HASH')) {
            $spcnt += $c->$m();
        }
        $p = $c;
    }

    return $spcnt;
}
sub wspcnt { shift()->_spcnt('w') }
sub hspcnt { shift()->_spcnt('h') }

sub spaset {
    my ($self, $f, $spa) = @_;

    foreach my $c (@{ $self->{chld} }) {
        $c->{chld} || next;
        $c->spaset($f, $spa);
    }

    if (defined $spa) {
        $self->{$f.'spa'} = $spa;
    }
    else {
        delete $self->{$f.'spa'};
    }
}

# метод Xchldsplit отрезает от списка нижестоящих элементов
# все, что не влезут в размер $sz
sub _split {
    my ($self, $f, $sz) = @_;
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

    my $m = $f.'split';
    my @chld = ();
    my $s = $self->sumi($f, 0); # принудительно отменяем spa
    my @over = ();
    while (my $c = $s->fetch()) {
        if ($s->{szfull} <= $sz) {
            # если на элемент хватает место целиком, то мы его
            # так и оставляем
            push @chld, $c;
            next;
        }

        # если места на очередной элемент не хватило,
        # просим его уместиться в той же размерности.
        # если элемент не может уместиться, перенесём его целиком
        my $over = ref($c) eq 'HASH' ? undef : $c->$m($sz - $s->{bybeg});

        if (!$over) {
            # Если не уместился даже малой частью, то реализуем
            # опцию nobr.
            @over = $c;
            while (@chld && ($over[0]->{nobrbeg} || $chld[@chld-1]->{nobrend})) {
                unshift @over, pop(@chld);
            }
            last;
        }

        if (@$over) {
            # а вернул нам элемент свой подэлементы, которые не вошли
            # в тот размер, который мы ему передали, поэтому сделаем
            # копию этого элемента и отдадим ему этот остаток.
            # эта копия зайдёт в следующий раз
            my $dup = $c->dup(@$over);
            @over = $dup;
            $dup->splitover();
        }
        
        # текущий элемент, видя, что не смог вместить всё, должен
        # сам обрезать своё содержимое и обновить свой размер.
        # поэтому тут мы его добавляем не глядя
        push @chld, $c;
        # А мы на этом должны уже прерваться, т.к. понятно, что
        # больше в нас ничего не влезет.
        last;
    }
    push @over, $s->avail();

    @chld || return; # если вообще не смогли разделить
    @over || return []; # если вдруг в нас всё влезло

    # Если есть невлезшие элементы, обрежем свой список и обновим размер
    $self->{chld} = [@chld];

    # и возвращаем невлезший остаток
    return [@over];
}
sub wsplit {}
sub hsplit {}
sub splitover {}

# метод layout заставляет все подэлементы влезть в размер $sz
sub layout {
    my ($self, $f, $sz) = @_;
    # этот метод применяется в точке перехода к уровню вертикального
    # или горизонтального заполнения. Например, FContent сам является
    # уровнем вертикального заполнения, но все его подэлементы - это
    # уже уровень горизонтального заполнения.
    #
    # В результате, ответвление от stage3layout внутри FContent выполнит вмещение
    # в горизонтальный размер $w всех более глубоких уровней. Он порежет
    # горизонтальные строчки в нужных местах, сместив их вниз. После этого,
    # у всех нижестоящих элементов зафиксируется их высота, и можно будет
    # на уровне DDocument выполнять аналогичное разделение контента вглубь
    # уже по вертикальному размеру $h (разделение на страницы).
    
    # Например, если мы вызываемся из FContent (содержит внутри себя строки FLine),
    # который является уже блоком вертикального заполнения, то мы:
    # - отрезаем от первого своего chld (FLine) всё, что за границами $sz,
    # - помещаем отрезанное в новый FLine (копия предыдущего),
    # - помещаем новый FLine следом за первым...
    # и т.д.

    my $m = $f.'split';
    my @chld = ();
    my @prev = @{ $self->{chld} };
    while (my $c = shift @prev) {
        push @chld, $c;
        # если элемент не может уместиться, оставим его таким, как есть
        my $over = $c->$m($sz) || next;
        @$over || next; # элемент уместился весь
        
        # Помещаем остаток в такой же экземпляр
        my $dup = $c->dup(@$over);
        # повторно проверим остаток на следующей итерации
        unshift @prev, $dup;
        $dup->splitover();
    }

    $self->{chld} = [@chld];
}

sub stage3layout {
    my $self = shift;
    $_->stage3layout(@_) foreach @{ $self->{chld} };
}

sub stage4draw {
    my $self = shift;
    $_->stage4draw(@_) foreach @{ $self->{chld} };
}


# ============================================================
# ============================================================
package DNodeH;     # узел вертикального заполнения
use base 'DNode';

sub w       { shift()->wsum(shift()); }
sub h       { shift()->hmax(); }
sub wsplit  { shift()->_split('w', @_) }

sub stage4draw {
    my ($self, $x, $y, @p) = @_;

    $y += $self->{hend}||0;

    my $s = $self->sumi('w');
    while (my $c = $s->fetch()) {
        $x += $s->{byprv};
        $c->stage4draw($x, $y, @p);
    }
}


# ============================================================
# ============================================================
package DNodeV;     # узел горизонтального заполнения
use base 'DNode';

sub w       { shift()->wmax(); }
sub h       { shift()->hsum(shift()); }
sub hsplit  { shift()->_split('h', @_) }

sub stage4draw {
    my ($self, $x, $y, @p) = @_;

    $x += $self->{wbeg}||0;

    # тут мы дважды рекурсивно вычисляем размер:
    # сначала нам надо знать полный размер, а потом
    # когда рисуем заного приходится вычислять
    # размерности всех подэлементов, т.к. нам нужно
    # выполнить смещение для каждого элемента отдельно.
    $y += $self->h();
    # тут можно подумать, что делать.
    # Как вариант - использовать в качестве $y -
    # не нижнюю границу элемента, а верхнюю.
    # Указание в качестве $y нижней границы идёт
    # от принципов отрисовки в pdf, но так сильно
    # усложняется вычисление этого значения
    my $s = $self->sumi('h');
    while (my $c = $s->fetch()) {
        $y -= $s->{byprv};
        $c->stage4draw($x, $y - $s->{sz}, @p);
    }
}


# ============================================================
# ============================================================
#
#       Вспомогательный доп-классы (инструменты)
#
# ============================================================
# ============================================================

# ============================================================
# ============================================================
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
# ============================================================
#
#       Структура документа
#
# ============================================================
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
    
    $self->SUPER::stage3layout(%geom);
    $self->layout(h => $geom{h});
}

sub stage4draw { shift()->DNode::stage4draw(@_) }


# ============================================================
# ============================================================
package DPage;
use base 'DNodeV';

sub stage3layout {
    my ($self, %g) = @_;

    $self->{geom}   = { %g };
    $self->{hspc}   = 12;

    $self->SUPER::stage3layout($g{w}, $g{h});
}

sub stage4draw {
    my ($self, $pdf) = @_;
    
    my $page = $pdf->page();
    my $geom = $self->{geom};
    $page->size($geom->{size});

    my $g = $page->graphics();
    $g->move($geom->{x}, $geom->{y});
    $g->hline($geom->{x} + $geom->{w});
    $g->vline($geom->{y} + $geom->{h});
    $g->hline($geom->{x});
    $g->vline($geom->{y});
    $g->stroke();

    my $y = $geom->{y} + $geom->{h};
    my $s = $self->sumi('h');
    while (my $c = $s->fetch()) {
        $y -= $s->{byprv};
        $c->stage4draw($geom->{x}, $y - $s->{sz}, $page, $pdf);
    }
}


# ============================================================
# ============================================================
package DContent;
use base 'DNodeV', 'DParserH';

sub new {
    my $self = shift()->SUPER::new();
    $self->content(@_);
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{hspc} = $p->{style}->height() * 0.2;

    if (my $al = $self->{align}) {
        $_->{align} = $al foreach @{ $self->{chld} };
    }

    $self->SUPER::stage2size($p, @p);
}

sub stage3layout {
    my ($self, $w, $h, @p) = @_;
    $self->SUPER::stage3layout($w, $h, @p);
    $self->layout(w => $w);
}

sub stage4draw {
    my ($self, $x, $y, $page, @p) = @_;

    my $d = PageDraw->new($page);

    $self->SUPER::stage4draw($x, $y, $d, $page, @p);
}

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


# ============================================================
# ============================================================
package DLine;
use base 'DNodeH';

sub stage2size {
    my ($self, $p, @p) = @_;
    
    $self->{wspc} = $p->{style}->width(' ');

    $self->SUPER::stage2size($p, @p);
}


# активация justify для всей строки,
    # Весь этот механизм вставим в метод wsplit - он обрезает строку
    # под нужный размер. Тут нам двойное удобство:
    #   1. Именно тут нам удобно узнать, что строка не поместилась вся, она
    #      обрезана и этот кусок надо растянуть.
    #   2. У нас имеется размер, до которого надо растянуть строку.
sub splitover {
    my $self = shift;
    # удаляем {spa} после предыдущей нарезанной строки,
    # подробнее - ниже.
    delete $self->{wspa};
}
sub wsplit {
    my $self = shift;

    my $over = $self->SUPER::wsplit(@_) || return;
    @$over                      || return $over; # строка вся влезла
    my $spcnt = $self->wspcnt() || return $over; # неразрезаемая строка

    delete $self->{align};

    my ($sz) = @_;
    my $w = $self->w(0); # актуальный размер с принудительным wspa=0
    # Для justify выбрано удобное место для определения,
    # что строка была порезана и её надо растянуть.
    # Однако, когда мы растягиваем её тут, мы задаём spa,
    # и потом этот spa копируется в следующую строку,
    # потому что метод wsplit вызывается методом
    # layout, который нарезает строки по определённому
    # размеру, а копию делает уже после выхода
    # из wsplit, копируя в т.ч. и spa, который
    # устанавливается внутри wsplit.
    # Для этого мы удаляем spa выше (внутри splitover).
    
    # устанавливаем spa по всему дереву от нас вниз
    $self->spaset(w => ($sz - $w) / $spcnt);
    return $over;
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->{ctxw} = $w; # текущая ширина контекста нужна для align

    # вложенные элементы только строчные, они будут порезаны
    # рекурсивно в layout('w'), который вызывает DContent::stage3layout
    # Тут продолжать рекурсию stage3layout уже не требуется.
}

sub stage4draw {
    my ($self, $x, @p) = @_;

    # механизм горизонтального выравнивания строки
    if (($self->{align}||'') eq 'r') {
        $x += $self->{ctxw} - $self->w();
    }
    elsif (($self->{align}||'') eq 'c') {
        $x += ($self->{ctxw} - $self->w()) / 2;
    }

    $self->SUPER::stage4draw($x, @p);
}




# ============================================================
# ============================================================
#
#       Части строк (горизонтальные элементы)
#
# ============================================================
# ============================================================

package DStr;
use base 'DNodeH';

sub new {
    my $self = shift()->SUPER::new();
    $self->addwrd(@_);
    return $self;
}

sub addwrd {
    my $self = shift;

    foreach my $s (@_) {
        my @wrd = split /\s+/, (ref($s) eq 'Str') || (ref($s) eq 'HASH') ? $s->{str} : $s;
        if (@wrd && ($wrd[0] eq '')) {
            shift(@wrd);
        }
        if (@wrd && ($wrd[@wrd-1] eq '')) {
            pop(@wrd);
        }

        $self->add(map { { str => $_ } } @wrd);
    }
}

sub h { shift()->{h} }

sub stage2size {
    my ($self, $p) = @_;

    foreach my $c (@{ $self->{chld} }) {
        $c->{w} = $p->{style}->width($c->{str});
    }
    $self->{h} = $p->{style}->height();

    $self->{wspc} = $p->{style}->width(' ');

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

    if ($self->{wspa}) { # указано дополнительное расстояние между словами
        my $s = $self->sumi('w');
        while (my $c = $s->fetch()) {
            $x += $s->{byprv};
            $d->text($x, $y - $self->{ulpos}, $c->{str});
        }
    }
    else {
        # если текст не надо растягивать, выводим его простой строкой с пробелами
        $d->text($x + ($self->{wbeg}||0), $y - $self->{ulpos}, join(' ', map { $_->{str} } @{ $self->{chld} }));
    }
}


# ============================================================
# ============================================================
package DContentStyle;
use base 'DNodeH', 'DParserH';

sub new {
    my $self = shift()->SUPER::new(
        style => shift()
    );
    $self->content(@_);
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    local $p->{style} = $p->{style}->clone($self->{style} => 1);
    $self->{wspc} = $p->{style}->width(' ');

    $self->SUPER::stage2size($p, @p);
}


# ============================================================
# ============================================================
package DICode;
use base 'DStr';

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{wbeg} = $p->{style}->width(' ');
    $self->{wend} = $self->{wbeg};
    $self->{vpad} = $p->{style}->height() * 0.2 - 1;

    $self->SUPER::stage2size($p, @p);
}

sub stage4draw {
    my ($self, $x, $y, $d, @p) = @_;

    $d->gfxcol('#aaa');
    $d->rrect($x, $y - $self->{vpad}, $self->w(), $self->h() + $self->{vpad}*2, 4);

    $self->SUPER::stage4draw($x, $y, $d, @p);
}


# ============================================================
# ============================================================
package DHref;
use base 'DNodeH', 'DParserH';

sub new {
    my $self = shift()->SUPER::new(
        url => shift()
    );
    $self->content(@_);
    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{wspc} = $p->{style}->width(' ');

    $self->SUPER::stage2size($p, @p);
}

sub stage4draw {
    my ($self, $x, $y, $d, $page, @p) = @_;

    my ($w, $h) = ($self->w(), $self->h());

    $d->gfxcol('#000');
    my $g = $d->gfx();
    $g->move($x, $y);
    $g->hline($x + $w);
    $g->stroke();

    $self->SUPER::stage4draw($x, $y, $d, $page, @p);

    my $an = $page->annotation();
    $an->rect($x, $y, $x + $w, $y + $h);
    $an->uri($self->{url});
}


# ============================================================
# ============================================================
package DImage;

sub new {
    my ($class, $url, $title, $alt) = @_;

    my $self = bless({ url => $url }, $class);
    $self->{title} = $title if $title;
    $self->{alt} = DStr->new('[' . $alt . ']') if $alt;

    return $self;
}

sub w { shift()->{w}; }
sub h { shift()->{h}; }

sub stage2size {
    my ($self, $p, @p) = @_;

    eval { $self->{img} = $p->_image($self->{url}) };
    if (my $img = $self->{img}) {
        $self->{w} = $img->width();
        $self->{h} = $img->height();
    }
    elsif (my $alt = $self->{alt}) {
        $alt->stage2size($p, @p);
        $self->{w}  = $alt->w();
        $self->{h}  = $alt->h();
    }
    else {
        $self->{w} = 0;
        $self->{h} = 0;
    }
}

sub stage3layout {}

sub stage4draw {
    my $self = shift;

    if ($self->{img}) {
        my ($x, $y, $d, $page) = @_;
        $page->object($self->{img}, $x, $y);
    }
    elsif ($self->{alt}) {
        $self->{alt}->stage4draw(@_);
    }
}





# ============================================================
# ============================================================
#
#       Блочные элементы страницы
#
# ============================================================
# ============================================================

package DHeader;
use base 'DContent';

sub new {
    my $class = shift;
    my $deep = shift;

    my $self = $class->SUPER::new(@_);
    $self->{deep} = $deep;
    $self->{nobrend} = 1;

    return $self;
}

sub stage2size {
    my ($self, $p, @p) = @_;

    my @size = ( 22, 18, 14, 12, 11 );
    my $sz = ($self->{deep} > 0) && ($self->{deep} <= @size) ? $size[ $self->{deep} - 1 ] : $size[ @size-1 ];

    local $p->{style} = $p->{style}->clone(bold => 1, size => $sz);
    $self->{hln} = $self->{deep} > 2 ? 0 : $p->{style}->height() * 0.1;
    $self->{hend} = $self->{hln};

    $self->SUPER::stage2size($p, @p);
}

sub hsplit {} # вертикальная неразрывность содержимого

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->{ctxw} = $w;

    $self->SUPER::stage3layout($w, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page, @p) = @_;

    if ($self->{hln}) {
        my $g = $page->graphics();
        $g->stroke_color('#aaa');
        $g->move($x, $y);
        $g->hline($x + $self->{ctxw});
        $g->stroke();
        $g->stroke_color('#000');
    }
    
    $self->SUPER::stage4draw($x, $y + $self->{hln}, $page, @p);
}


# ============================================================
# ============================================================
package DHLine;
use base 'DHeader';

sub new {
    return shift()->SUPER::new(2, @_);
}

sub stage2size {
    my ($self, $p, @p) = @_;
    
    $self->SUPER::stage2size($p, @p);

    $self->{hln} = $self->empty() ? 2 : $p->{style}->height() * 0.1;
}


# ============================================================
# ============================================================
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
        map { { str => (ref eq 'Str') || (ref eq 'HASH') ? $_->{str} : $_ } } @_
    );
}

sub stage2size {
    my ($self, $p, @p) = @_;

    my $style = $p->{style}->clone(font => 'PTMonoBold.ttf');

    $self->{font}   = [ $style->font() ];
    $self->{ulpos}  = $style->ulpos();

    $self->{wbeg} = $style->width(' ');
    $self->{wend} = $self->{wbeg};
    $self->{hbeg} = $style->height() * 0.7;
    $self->{hend} = $self->{hbeg};
    $self->{hspc} = $style->height() * 0.2;

    foreach my $c (@{ $self->{chld} }) {
        $c->{w} = $style->width($c->{str});
        $c->{h} = $style->height();
    }
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->{ctxw} = $w;
}

sub stage4draw {
    my ($self, $x, $y, $page) = @_;

    my $d = PageDraw->new($page);

    $d->gfxcol('#888');
    my $h = $self->h();
    $d->rrect($x, $y, $self->{ctxw}, $h, 4);

    $x += $self->{wbeg};
    $y += $h + $self->{hspc}/2;

    $d->font(@{ $self->{font} });
    my $t = $d->_text();
    $t->fill_color('#fff');

    my $s = $self->sumi('h');
    while (my $c = $s->fetch()) {
        $y -= $s->{byprv};
        $d->text($x, $y - $s->{sz} - $self->{ulpos}, $c->{str});
    }

    $t->fill_color('#000');
}


# ============================================================
# ============================================================
package DQuote;
use base 'DNodeV';

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{hspc}   = 12;
    $self->{pad}    = 12;

    $self->SUPER::stage2size($p, @p);
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->SUPER::stage3layout($w - $self->{pad}, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page, @p) = @_;

    my $h = $self->h();

    my $g = $page->graphics();
    $g->move($x, $y);
    $g->vline($y + $h);
    $g->stroke();
    $g->move($x+2, $y);
    $g->vline($y + $h);
    $g->stroke();
    $g->move($x+4, $y);
    $g->vline($y + $h);
    $g->stroke();

    $self->SUPER::stage4draw($x + $self->{pad}, $y, $page, @p);
}


# ============================================================
# ============================================================
package DListItem;
use base 'DNodeV';

sub new {
    return shift()->SUPER::new(
        num => shift()
    );
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{pad}    = 20;
    $self->{nw}     = $p->{style}->width($self->{num} . '  ');

    $self->{hspc}   = 12;
    $self->{font}   = [ $p->{style}->font() ];
    $self->{ulpos}  = $p->{style}->ulpos();

    $self->SUPER::stage2size($p, @p);
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->SUPER::stage3layout($w - $self->{pad}, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page, @p) = @_;

    my $d = PageDraw->new($page);
    $d->font(@{ $self->{font} });
    $d->text(
        $x + $self->{pad} - $self->{nw},
        $y + $self->h() - $self->{font}->[1] - $self->{ulpos},
        $self->{num}
    );

    $self->SUPER::stage4draw($x + $self->{pad}, $y, $page, @p);
}





# ============================================================
# ============================================================
#
#       Таблица
#
# ============================================================
# ============================================================

package DTable;
use base 'DNodeV';

sub new {
    my $self = shift()->SUPER::new(
        mode    => shift(),
        colw    => shift()||[],     # ширина столбцов
        cols    => 0,               # суммарная ширина всех столбцов
        cola    => shift()||[],     # горизонтальное выравнивание в столбцах
    );

    $self->{cols} += $_ foreach @{ $self->{colw} };

    return $self;
}

sub _addrow {
    my ($self, $class, @col) = @_;
    $self->add( $class->new($self, @col) );
}

sub addhdr { shift()->_addrow(DTblHdr => @_); }
sub addrow { shift()->_addrow(DTblRow => @_); }

sub padchld {
    my $self = shift;

    # отступы сверху и снизу у рядов. Количество
    # рядов в таблице может измениться, т.к. она
    # может быть обрезана страницей и поэтому
    # изменятся первые и крайние ряды, а для
    # отступов в mode=2 это критично. Поэтому
    # делаем эту процедуру всегда при обновлении размеров.
    foreach my $c (@{ $self->{chld} }) {
        delete $c->{hbeg};
        delete $c->{hend};
    }

    my $n = @{ $self->{chld} };
    if ($n && ($self->{mode} > 1)) {
        # расстояние до верхней и нижней границ таблицы.
        $self->{chld}->[0]->{hbeg} = 5;
        $self->{chld}->[$n-1]->{hend} = 5;
    }
    foreach my $c (@{ $self->{chld} }) {
        $c->{hbeg} //= $self->{mode} == 1 ? 5 : 0;
        $c->{hend} //= $self->{mode} == 1 ? 5 : 0;
    }
}

sub stage2size {
    my ($self, $p, @p) = @_;

    $self->{hspc} = $self->{mode} == 1 ? 0 : 5;

    $self->padchld();
    $self->SUPER::stage2size($p, @p);
}

sub hsplit {
    my $self = shift;

    my $over = $self->SUPER::hsplit(@_) || return;

    $self->padchld() if $self->{mode} > 1;

    return $over;
}

sub splitover {
    my $self = shift;
    # Это единственное место, где понадобился данный метод.
    # Он выполняется после разделения элемента на части
    # для over-части. Никаких других обратных связей в этом
    # случае не происходит, а именно тут она нужна:
    # После разделения таблица на части нам нужно у обеих
    # частей пересчитать hbeg/hend для всех рядов.
    $self->padchld() if $self->{mode} > 1;
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->{ctxw} = $w;

    $self->SUPER::stage3layout($w, @p);
}

sub stage4draw {
    my ($self, $x, $y, $page, @p) = @_;

    my $h = $self->h();

    my $g = $page->graphics();
    $g->move($x, $y);
    $g->hline($x + $self->{ctxw});  # использование своей ширины не очень подходит,
                                    # т.к. ширина колонок делается принудительно
                                    # в отношениях к общей ширине, получаются дроби
                                    # суммарная размерность оказывается неточной
                                    # и из-за погрешности может оказаться как уже,
                                    # так и шире на пару пикселей.
    if ($self->{mode} == 1) {
        $g->vline($y + $h);
        $g->hline($x);
        $g->vline($y);
    }
    else {
        $g->stroke();
        $g->move($x, $y + $h);
        $g->hline($x + $self->{ctxw});
    }
    $g->stroke();

    if (($self->{mode} == 1) && !$self->empty()) {
        my @w = @{ $self->{colw} };
        my $x1 = $x + ($self->{ctxw} * shift(@w) / $self->{cols});
        foreach my $w (@w) {
            $g->move($x1-1, $y);
            $g->vline($y + $h);
            $g->stroke();
            $x1 += $self->{ctxw} * $w / $self->{cols};
        }

        my @r = @{ $self->{chld} };
        my $y1 = $y + $h - shift(@r)->h();
        foreach my $r (@r) {
            $g->move($x, $y1);
            $g->hline($x + $self->{ctxw});
            $g->stroke();
            $y1 -= $r->h();
        }
    }

    $self->SUPER::stage4draw($x, $y, $page, @p);
}


# ============================================================
# ============================================================
package DTblRow;
use base 'DNodeH';

sub new {
    my ($class, $tbl, @col) = @_;
    my $self = $class->SUPER::new(
        mode    => $tbl->{mode},
        colw    => $tbl->{colw},    # ширина столбцов
        cols    => $tbl->{cols},    # суммарная ширина всех столбцов
        cola    => $tbl->{cola},    # горизонтальное выравнивание в столбцах
    );

    $self->addcol(@$_) foreach @col;

    return $self;
}

sub addcol {
    my $self = shift;

    my $n = @{ $self->{chld} };
    $self->add( DTblCol->new($self->{colw}->[$n], $self->{cols}, $self->{cola}->[$n], @_) );
}

sub stage2size {
    my ($self, $p, @p) = @_;

    # допотступы слева и справа в колонках.
    # количество колонок у нас неизменно, поэтому
    # делаем однократно в проходе stage2size
    my $n = @{ $self->{chld} };
    if ($n && ($self->{mode} > 1)) {
        $self->{chld}->[0]->{padl} = 0;
        $self->{chld}->[$n-1]->{padr} = 0;
    }
    foreach my $c (@{ $self->{chld} }) {
        $c->{padl} //= 5;
        $c->{padr} //= 5;
    }

    $self->SUPER::stage2size($p, @p);
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->SUPER::stage3layout($w, @p);

    my $h = $self->h() - $self->{hbeg} - $self->{hend};
    $_->{rowh} = $h foreach @{ $self->{chld} };
}


# ============================================================
# ============================================================
package DTblHdr;
use base 'DTblRow';

sub stage2size {
    my ($self, $p, @p) = @_;

    local $p->{style} = $p->{style}->clone(bold => 1);

    $self->SUPER::stage2size($p, @p);
}


# ============================================================
# ============================================================
package DTblCol;
use base 'DContent';

sub new {
    my $self = shift()->SUPER::new();
    $self->{colw} = shift();    # ширина этого столбца
    $self->{cols} = shift();    # суммарная ширина всех столбцов
    $self->{align}= shift();    # горизонтальное выравнивание этого столбца

    $self->content(@_);

    return $self;
}

sub w {
    my $self = shift;
    return $self->{w} // $self->SUPER::w();
}

sub stage3layout {
    my ($self, $w, @p) = @_;

    $self->{w} = $w * $self->{colw} / $self->{cols};

    $self->SUPER::stage3layout($self->{w} - $self->{padl} - $self->{padr}, @p);
}

sub stage4draw {
    my ($self, $x, $y, @p) = @_;

    # нужно подвинуть все ячейки в ряду наверх, для этого мы знаем
    # свою высоту и высоту всей строки.
    $y += $self->{rowh} - $self->h();

    $self->SUPER::stage4draw($x + $self->{padl}, $y, @p);
}

1;
