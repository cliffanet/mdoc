package prs;

use strict;
use warnings;
use utf8;

=pod
    ======================================================================
        Модуль парсинга на базе класса txt
    ======================================================================
        Все функции модуля вызываются с txt-объектом в качестве аргумента
        и должны вернуть какой-то определённый элемент.
        Если в данном месте искомый элемент есть, то:
            - этот элемент будет удалён в исходном txt-объекте
            - возвращена информация об объекте
        Если элемент не найден:
            - исходный аргумент останется нетронутым
            - вернётся undef
    ======================================================================
=cut

# шаблон завершения текстового абзаца - в какой момент надо прервать текстовый блок
# применяется к началу строки, указывать ^ тут не надо
# шаблон учитывает все варианты начала разных нетекстовых блоков.
my $textend = qr/(?: {0,3}\t| {4})? {0,3}(?:[\*\-]|\d+\.)[ \t]+| {0,3}(?:___+|-+)?[ \t\r]*(?:\n|$)| {0,3}(?:\`\`\`)/;

=pod

    Парсеры возвращают либо структуру {}, либо список структур [{}, {} ...]
    Стандартные поля:
        - type - тип объекта
        - pos [$row, $col] - позиция в исходном тексте
        - text [список] - содержимое абзаца (ссылки, картинки, форматирование или чистый txt-объект)
                В некоторых элементах, где не применяется форматирование текста, text - это единичный
                txt-объект без упаковки в список
        - content [список] - набор параграфов (абзац, список, линии разметки,заголовки и т.д.)

=cut

my $err;
sub err {
    @_ || return $err;
    $err = shift();
    if (ref($err) eq 'txt::posinf') {
        my $pos = $err;
        $err = sprintf '[ln: %d, col: %d] %s', $pos->{row}, $pos->{col}, shift();
    }
    $err = sprintf($err, @_) if @_;
    return;
}


# ----------------------------------------------------------------------
# ---
# ---   служебные методы поиска
# ---

sub match {
    my ($s) = @_;
    my $regex = pop;
    # более удобный вызов $s->match(...), чтобы его можно было применять в скалярном контексте
    # вызов: my $found = match($s, $frag1, $frag2 ..., $regex);
    # При совпадении с шаблоном $regex, $s будет модифизирован на $tail, а $fragХ - на фрагменты
    # $regex всегда указывается последним

    my ($found, $tail, @frag) = $s->match($regex);
    $tail || return;

    $_[0] = $tail;
    shift();
    while (@_) {
        my $frag = shift @frag;
        $_[0] = $frag;
        shift();
    }

    return $found;
}

sub line {
    my ($s, $chomp, $skip_empty) = @_;
    # более удобный вызов $s->line(...), чтобы его можно было применять в скалярном контексте
    # При совпадении с шаблоном $regex, $s будет модифизирован на $tail
    # Если указан $skip_empty будут пропущены все пустые строки, и успешным результат будет
    # только при наличии непустой строки.

    my ($ln, $tail) = $s->line($chomp);
    while ($skip_empty && $ln->empty()) {
        return if $tail->empty();
        ($ln, $tail) = $tail->line($chomp);
    }

    $_[0] = $tail;
    return $ln;
}

sub indent {
    my ($s, $regex, $allow_empty_line) = @_;
    # более удобный вызов $s->indent(...), чтобы его можно было применять в скалярном контексте
    # При совпадении с шаблоном $regex, $s будет модифизирован на $tail

    my ($ind, $tail) = $s->indent($regex, $allow_empty_line);
    $tail || return;

    $_[0] = $tail;
    return $ind;
}

sub str {
    my $s = shift() || return;

    return if $s->match(qr/\n\s*\n/);
    $s = $s->{txt};
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub contadd {
    my ($c, $e) = @_;

    if ($e->{type} eq 'listitem') {
        my ($prv) = @$c ? $c->[ @$c-1 ] : undef;
        if (
                $prv && ($prv->{type} eq 'list') &&
                ($prv->{mode} eq $e->{mode})
            ) {
            push @{ $prv->{content} }, $e;
            return $c;
        }
        $e = {
            type    => 'list',
            mode    => $e->{mode},
            content => [$e]
        };
    }
    push @$c, $e;
    $c;
}


# ----------------------------------------------------------------------
# ---
# ---   doc
# ---
sub doc {
    my ($s) = @_;

    my $content = [];

    while (!$s->empty()) {
        my $e =
            modificator ($s) || # Специальные модификаторы и
            header      ($s) || # заголовки могут быть только на верхнем уровне
            paragraph   ($s);
        
        $e || return err($s->{pos}, 'doc > Can\t parse symbol');
        contadd($content, $e);
    }

    $_[0] = $s;
    return $content;
}

sub modificator {
    my ($s) = @_;

    my $ln = line($s, 1, 1) || return;
    match($ln, my $beg, my $m, qr/ {0,3}(\\(pagebreak))\s*$/) || return;

    $_[0] = $s;
    return {
        type    => 'modifier',
        pos     => [$beg->pos()],
        name    => $m->{txt}
    };
}

sub header {
    my ($s) = @_;

    my $ln = line($s, 1, 1) || return;
    match($ln, my $p, my $t, qr/ {0,3}(\#+)\s+(.*)$/) || return;
    my $text = inline($t) || return;

    $_[0] = $s;
    return {
        type    => 'header',
        pos     => [$p->pos()],
        deep    => length($p->{txt}),
        text    => $text
    };
}


# ----------------------------------------------------------------------
# ---
# ---   Paragraph
# ---
sub level {
    my ($s) = @_;

    my $content = [];

    while (!$s->empty()) {
        my $e = paragraph($s);
        $e || return err($s->{pos}, 'level > Can\t parse symbol');
        contadd($content, $e);
    }

    $_[0] = $s;
    return $content;
}
sub paragraph {
    my ($s) = @_;

    # Сразу пропустим все пустые строки, т.к. они в этом месте всегда игнорируются
    while (($s->{txt} ne '') && (my ($ln, $tail) = $s->line(1))) {
        $ln->empty() || last;
        $s = $tail;
    }

    my $e =
        list        ($s) ||
        hline       ($s) ||
        code        ($s) ||
        quote       ($s) ||
        textblock   ($s) ||
        badge       ($s) ||
        table1      ($s) ||
        table2      ($s) ||
        text        ($s);
    
    $e || return;

    $_[0] = $s;
    return $e;
}

# текстовый блок
#
# первая строка всегда считается текстовой
# следом пристыкаются все строки, кроме:
#   - пустой
#   - списка
sub text {
    my ($s) = @_;

    return if $s->empty();

    my $txt = match($s, qr/[^\n]*(?:\n((?!$textend)[ \t]*\S[^\n]*(?:\n|$))*|$)/) || return;

    # стравим пробельные символы вначале и вконце, они точно не нужны
    match($txt, qr/\s+/);
    $txt->{txt} =~ s/[\r\n]+$//;

    my $pos = [$txt->pos()];
    my $cont = inline($txt) || return;

    $_[0] = $s;
    return {
        type    => 'text',
        pos     => $pos,
        text    => $cont
    };
}

sub list {
    my ($s) = @_;

    match($s, my $mode, qr/ {0,3}([\*\-]|\d+\.)[ \t]+/) || return;
    my @content = text($s) || return;

    if (my $ind = indent($s, qr/(?: {4}| {0,3}\t)/, 1)) {
        my $sub = level($ind) || return;
        push @content, @$sub;
    }

    $_[0] = $s;
    return {
        type    => 'listitem',
        pos     => [$mode->pos()],
        $mode->{txt} =~ /(\d+)/ ? (
            mode    => 'ord',
            num     => int($1)
        ) : (
            mode    => $mode->{txt}
        ),
        content   => [@content]
    };
}

sub hline1 {
    my ($s) = @_;

    my $ln = line($s, 1) || return;
    match($ln, my $beg, qr/ {0,3}(-{3,})/) || return;
    $ln->empty() || return;

    $_[0] = $s;
    return {
        type    => 'hline',
        pos     => [$beg->pos()]
    };
}

sub hline2 {
    my ($s) = @_;

    my $text = text($s) || return;

    my $ln = line($s, 1) || return;
    match($ln, qr/ {0,3}-+/) || return;
    $ln->empty() || return;

    $_[0] = $s;
    return {
        type    => 'hline',
        pos     => $text->{pos},
        text    => $text->{text},
    };
}

sub hline3 {
    my ($s) = @_;

    my $ln = line($s, 1) || return;
    match($ln, my $beg, qr/ {0,3}(_{3,})/) || return;
    $ln->empty() || return;

    $_[0] = $s;
    return {
        type    => 'hline',
        pos     => [$beg->pos()]
    };
}

sub hline {
    return
        hline1(@_) ||
        hline2(@_) ||
        hline3(@_);
}

sub code {
    my ($s) = @_;

    my $lang = line($s, 1) || return;
    match($lang, my $beg, qr/ {0,3}(\`\`\`)/) || return;
    $lang = str($lang);

    my $code = $s->copy(txt => '');
    my $ok;
    while (!$s->empty()) {
        my $ln = line($s);
        if ($ln->match(qr/ {0,3}\`\`\`/)) {
            $ok = 1;
            last;
        }
        $code->{txt} .= $ln->{txt};
    }
    $ok || return;

    $code->{txt} =~ s/\n$//;

    $_[0] = $s;
    return {
        type    => 'code',
        pos     => [$beg->pos()],
        $lang ?
            (lang   => $lang) : (),
        text    => $code,
    };
}

sub quote {
    my ($s) = @_;

    my @pos = $s->pos();
    my $ind = indent($s, qr/ {0,3}\>/) || return;
    my $cont = level($ind) || return;

    $_[0] = $s;
    return {
        type    => 'quote',
        pos     => [@pos],
        content => $cont,
    };
}

sub textblock {
    my ($s) = @_;

    my @pos = $s->pos();
    my $ind = indent($s, qr/ {0,3}\t| {4}/, 1) || return;
    $ind->{txt} =~ s/\n$//;

    $_[0] = $s;
    return {
        type    => 'textblock',
        pos     => [@pos],
        text    => $ind,
    };
}

sub badge {
    my ($s) = @_;

    # code
    match($s, my $code, qr/^ {0,3}\[([^\[\]]+)\]\s*\:/) || return;
    $code = str($code) || return;

    # url
    match($s, my $url, qr/\s*(\S+)/) || return;

    # title
    my $title;
    if (match($s, my $title1, my $title2, qr/\s+(?:\"([^\"]*)\"|\'([^\']*)\')/)) {
        $title = $title1 || $title2;
        return if $title->match(qr/\n\s*\n/);
        undef($title) if $title->empty();
    }

    # завершаем строку, она должна быть пустой
    my $ln = line($s);
    $ln->empty() || return;

    $_[0] = $s;
    return {
        type    => 'badgedef',
        pos     => [$s->pos()],
        code    => $code,
        url     => $url->{txt},
        $title ?
            (title   => $title) : (),
    };
}

sub _table1_line {
    my ($s) = @_;

    my $ln = line($s, 1) || return;
    return if $ln->empty();
    
    my $f = match($ln, qr/ {,3}\|/); # $f укажет, была ли хотябы одна | в строке
    if ($ln->{txt} =~ /\|\s*$/) {
        $f ||= 1;
    }
    else {
        # для корректной работы inline() обязательно
        # присутствие стоп-шаблона в конце строки - это символ |
        # а для таблицы необязательно, чтобы этот символ присутствовал
        $ln->{txt} .= '|';
    }

    my $row = [];
    while (!$ln->empty()) {
        my $cont = inline($ln, qr/\|/) || return;
        push @$row, $cont;
    }

    # Убедимся, что в строке есть хотябы одна |
    # Если колонок две и более, это значи, что первая колонка точно заканчивается на |
    # Если колонок меньше, то должен быть | в начале строки или в конце ($f = true)
    return if (@$row < 2) && !$f;

    $_[0] = $s;
    return $row;
}

sub table1 {
    my ($s) = @_;

    my @pos = $s->pos();
    my $hdr = _table1_line($s) || return;

    my $ln = line($s, 1) || return;
    my $p = str(match($ln, qr/ {,3}\|?(?:\s*\:?\-+\:?\s*\|)+(?:\s*\:?\-+\:?\s*\|?)?/)) || return;
    $ln->empty() || return;
    $p =~ s/^\|//;
    $p =~ s/\|$//;
    my @p = split '\|', $p;
    my @width = map { length($_) } @p;
    my @align =
        map {
            my $l = /^\s*\:/;
            my $r = /\:\s*$/;
            $l && $r    ? 'c' :
            $l          ? 'l' :
            $r          ? 'r' : ''
        }
        @p;

    my @row = ();
    while (!$s->empty()) {
        my $row = _table1_line($s) || last;
        push @row, $row;
    }
    
    $_[0] = $s;
    return {
        type    => 'table',
        pos     => [$s->pos()],
        mode    => 1,
        width   => [ @width ],
        align   => [ @align ],
        hdr     => $hdr,
        row     => [ @row ]
    };
}

sub _cinc {
    my ($len, $c) = @_;

    if ($c eq "\t") {
        $len += 4;
        $len -= $len % 4;
    }
    elsif (ord($c) >= 32) {
        $len ++;
    }

    $_[0] = $len;
}

sub _clen {
    my $s = shift;
    my $len = 0;
    _cinc($len, $_) foreach split(//, $s);
    return $len;
}
sub _ccut {
    my ($s, $beg, $len) = @_;
    my $end = $beg + $len;
    my @c = split(//, $s);
    
    my $n = 0;
    while (@c && ($n < $beg)) {
        my $c = shift @c;
        _cinc($n, $c);
    }

    my @s = ();
    while (@c && ($n < $end)) {
        my $c = shift @c;
        push @s, $c;
        _cinc($n, $c);
    }

    my $r = join('', @s);
    $r =~ s/\s+$//;

    return $r;
}

sub table2 {
    my ($s) = @_;

    my @pos = $s->pos();
    my $ln = line($s, 1) || return;
    match($ln, my $pos, my $w, qr/( {0,3})(\-[\- \t]{3,})/) || return;
    $ln->empty() || return;

    # Определяем параметры ячеек в строке
    my @beg = ();                   # @beg - номера символов начала подстроки ячейки
    my $beg = length $pos->{txt};
    my @p = ();                     # @p - позиция в строке с учётом табуляторных сдвигов
    $pos = $beg;
    my @width = ();                 # @width
    $w = $w->{txt};
    while ($w =~ s/^((\-+)\s*)//) {
        push @beg, $beg;
        $beg += length $1;
        push @p, $pos;
        $pos += _clen($1);
        push @width, length $2;
    }

    # Получаем ячейки
    my ($row, $subrowi);
    my @row = ();
    while (!$s->empty()) {
        my $ln = line($s, 1) || return;

        # пустая строка означает - отделение следующего ряда в таблице
        if ($ln->empty()) {
            undef $row;
            next;
        }
        # Завершение всей таблица
        last if $ln->{txt} =~ /^ {0,3}\-[\- ]*$/;

        if (!$row) {
            # подготовим txt-объекты по всём ряду таблицы
            $subrowi = -1;
            push @row, $row = [];
            for (my $i = 0; $i < @beg; $i++) {
                my $txt = $ln->copy(txt => '');
                $txt->{pos}->{col} += $beg[$i];
                $row->[$i] = $txt;
            }
        }
        
        # надо бы ещё сдвинуть значения в списке $txt->{pos}->{ind},
        # Это приходится делать в каждой новой строке текущего ряда
        $subrowi ++;
        for (my $i = 0; $i < @beg; $i++) {
            my $ind = $row->[$i]->{pos}->{ind};
            $ind->[$subrowi] ||= 1;
            $ind->[$subrowi] += $beg[$i];
        }
        
        # Заполняем $row содержимым
        for (my $i = 0; $i < @p; $i++) {
            my $c = _ccut($ln->{txt}, $p[$i], $width[$i]);
            next if $c =~ /^\s*$/;

            my $txt = $row->[$i];
            $txt->{txt} .= "\n" if $txt->{txt} ne '';
            $txt->{txt} .= $c;
        }
    }

    # Осталась финишная операция - надо отформатировать содержимое
    foreach my $row (@row) {
        foreach my $txt (@$row) {
            $txt = inline($txt) || return;
        }
    }
    
    $_[0] = $s;
    return {
        type    => 'table',
        mode    => 2,
        pos     => [ @pos ],
        width   => [ @width ],
        row     => [ @row ]
    };
}

# ----------------------------------------------------------------------
# ---
# ---   inline
# ---
sub inline {
    my ($s, $end) = @_;
    # Если указан шаблон $end, то поиск будет остановлен по достижению этого шаблона,
    # а валидный возврат будет только в случае, если было совпадение с данным шаблоном.
    #
    # Без указания шаблона $end этот метод предназначен только для применения к фрагменту,
    # т.к. захавает всё содержимое без остатка

    ##  Есть несколько вариантов парсинга блочных элементов внутри строк:
    ##
    ##  1. Перебирать блок списком разным шаблонов, например: qr/_([^_]+)_/
    ##  Основной минус такого подхода - когда строки разбиваются на части
    ##  после одного фильтра, то другой шаблон уже не получится применить,
    ##  т.к. строка разбита.
    ##
    ##  Например, если будет такая строка: **bold _italic_**
    ##  и первым обработается часть _italic_, то получится список:
    ##  "строка: **bold ", italic-объект, "строка**"
    ##  и к ней уже никак не применить шаблон **bold**
    ##
    ##  2. Двигаться по строке посимвольно, каждый раз прогоняя весь список
    ##  шаблону к текущей позиции в строке. Шаблон при этом применяется
    ##  целиковый (захватывающий весь блок), например: qr/_([^_]+)_/
    ##
    ##  Этот метод хорош тем, что каждый шаблон можно обернуть в отдельную
    ##  функцию, в которой выполнить все дополнительные действия. Например,
    ##  повторно пройтись таким методом по всем вложенным строкам.
    ##
    ##  Минус в том, что надо каждый раз откусывать от основной строки по символу,
    ##  а по остатку проходить всем набором шаблонов - довольно большая нагрузка.
    ##  Но получается, что иначе никак не обработать нормально вложенные элементы.
    ##
    ##  Ещё один большой минус из-за применения шаблона, охватывающего весь блок
    ##  целиком. Он может давать сбой, если два однотипных блока пложены один
    ##  в другой. Очень высокие требования к проработке таких шаблонов.
    ##
    ##  3. Аналогично п.2, но проходить уже не списком шаблонов, а списков функций,
    ##  каждая из которых будет пытаться обнаруживать свой блок. Такой же подход
    ##  реализован в mult-парсере. Но там более строгое содержимое, а тут будет
    ##  попадаться простой текст.

    # в тексте не должно быть пустой строки
    return if $s->match(qr/\s*(?:\n|$)/);

    my $cont = [];
    my $txt = $s->copy(txt => '');
    while ($s->{txt} ne '') {
        # в тексте не должно быть пустой строки,
        # а начало новой строки не должно быть списком
        return if $s->{txt} =~ /\n$textend/;

        if ($end && match($s, my $s1, $end)) {
            # сработал $end
            # если в нём применялся фрагмент, то его надо дописать к текстовой строке.
            $txt->{txt} .= $s1->{txt} if $s1;
            undef $end;
            last;
        }

        # от inline_XXX функций мы не будем ожидать pos в ответе,
        # сформируем его сами после вызова
        my @pos = $s->pos();

        my $f =
            inline_bold     ($s) ||
            inline_italic   ($s) ||
            inline_code     ($s) ||
            inline_image    ($s) ||
            inline_href     ($s) ||
            inline_badge    ($s);
        if ($f) {   # сработал один из шаблонов
            # $txt - это текст перед найденным элементом
            if ($txt->{txt} ne '') {
                $txt->{nobrend} = 1 if $txt->{txt} =~ /\S$/;
                push @$cont, $txt;
            }
            $txt = $s->copy(txt => ''); # новая точка старта для $txt

            $f->{pos} = [@pos];
            push @$cont, $f;
            next;
        }

        # шаблоны не сработали, двигаемся к следующему символу
        if (my $s1 = match($s, qr/(?:.|\n)/)) {  # . не срабатывает на \n
            $txt->{nobrbeg} = 1 if ($txt->{txt} eq '') && ($s1->{txt} =~ /^\S/);
            $txt->{txt} .= $s1->{txt};
        }
        else {
            # какая-то непонятная ошибка, qr/./ в этом месте должен
            # всегда срабатывать
            return err($s->{pos}, 'inline > unknown match fail');
        }
    }

    # Если был указан $end и он не сработал - это ошибка
    $end && return err($s->{pos}, 'inline > end of block not found');

    $_[0] = $s;

    # Непустая строка, её надо добавить в $cont
    push(@$cont, $txt) if $txt->{txt} ne '';

    return $cont;
}

sub inline_bold {
    my ($s) = @_;

    my $text =
        match($s, qr/__/) ?
            inline($s, qr/__/) :
        match($s, qr/\*\*/) ?
            inline($s, qr/\*\*/) :
            return;

    $_[0] = $s;
    return {
        type    => 'bold',
        text    => $text
    };
}

sub inline_italic {
    my ($s) = @_;

    my $text =
        match($s, qr/_/) ?
            inline($s, qr/_/) :
        match($s, qr/\*/) ?
            inline($s, qr/\*/) :
            return;

    $_[0] = $s;
    return {
        type    => 'italic',
        text    => $text
    };
}

sub inline_code {
    my ($s) = @_;

    # вроде б как inlinecode не должен внутри себя парсить форматтеры
    match($s, my $text, qr/\`(.+?)\`/) || return;

    $_[0] = $s;
    return {
        type    => 'inlinecode',
        text    => $text->{txt}
    };
}

sub inline_image {
    my ($s) = @_;

    match($s, qr/\!\[(?:[ \t\r]*\n)?/) || return;
    my $text = inline($s, qr/\]/) || return;

    match($s, my $url, my $title, qr/\(\s*([^\(\)\"]+?)\s*(?:\s+\"(.*?)\")?\)/) || return;
    $url = str($url) || return;

    $_[0] = $s;
    return {
        type    => 'image',
        url     => $url,
        @$text ?
            (text   => $text)           : (),
        $title && length($title->{txt}) ?
            (title  => $title->{txt})   : (),
    };
}

sub inline_href {
    my ($s) = @_;

    match($s, qr/\[(?:[ \t\r]*\n)?/) || return;
    my $text = inline($s, qr/\]/) || return;

    match($s, my $url, qr/\(([^\(\)\"]+?)\)/) || return;
    $url = str($url) || return;

    $_[0] = $s;
    return {
        type    => 'href',
        url     => $url,
        text    => $text
    };
}

sub inline_badge {
    my ($s) = @_;

    match($s, qr/\!\[(?:[ \t\r]*\n)?/) || return;
    my $text = inline($s, qr/\]/) || return;

    match($s, my $code, qr/\[([^\[\]]+)\]/) || return;
    $code = str($code) || return;

    $_[0] = $s;
    return {
        type    => 'badge',
        code    => $code,
        @$text ?
            (text   => $text)           : (),
    };
}

1;
