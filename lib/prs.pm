package prs;

use strict;
use warnings;
use utf8;
use feature qw(fc unicode_strings);

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
my $textend = qr/(?: {0,3}\t| {4})? {0,3}(?:[\*\-\+]|\d+[\.\)])[ \t]+| {0,3}(?:___+|-+)?[ \t\r]*(?:\n|$)| {0,3}(?:\`\`\`)/;

# ASCII-знаки пунктуации, которые CommonMark разрешает экранировать обратной
# косой чертой. $escaped дополнительно включает саму косую черту перед знаком.
my $punctuation = qr/[\x21-\x2f\x3a-\x40\x5b-\x60\x7b-\x7e]/;
my $escaped = qr/\\$punctuation/;

# URL ссылочного определения без угловых скобок. Баланс круглых скобок
# проверяется отдельно, чтобы не ограничивать глубину вложенности шаблоном.
my $refurl = qr/(?:$escaped|[^\s\<\>])+/;

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
# Без аргументов возвращает последнюю ошибку парсинга. С аргументами сохраняет
# новое сообщение, при необходимости дополняя его координатами исходного текста.
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

# Преобразует простой txt-фрагмент в строку: отклоняет фрагмент, начинающийся
# с пустой строки, и удаляет пробелы по краям.
sub str {
    my $s = shift() || return;

    return if $s->match(qr/\n\s*\n/);
    $s = $s->{txt};
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

# Удаляет обратную косую черту только перед экранируемой ASCII-пунктуацией.
# Применяется к строковым полям, которые не разбираются через inline().
sub unescape {
    my $s = shift;
    $s =~ s/\\($punctuation)/$1/g;
    return $s;
}

# Разбирает URL и необязательный Markdown-title внутри круглых скобок.
# Title поддерживает двойные, одинарные и круглые ограничители.
sub inline_target {
    my ($s, $glb) = @_;

    my ($url, $title);
    if (
            match(
                $s,
                $url, my $title1, my $title2, my $title3,
                qr/\(\s*((?:$escaped|[^\(\)\"])+?)\s+(?:\"((?:$escaped|[^\"])*)\"|\'((?:$escaped|[^\'])*)\'|\(((?:$escaped|[^\(\)])*)\))\s*\)/
            )
        ) {
        $title = $title1 || $title2 || $title3;
    }
    elsif (
            !match(
                $s,
                $url,
                qr/\(\s*((?:$escaped|[^\(\)\"\']|(?<!\s)\')+?)\s*\)/
            )
        ) {
        return;
    }

    my $urlstr = str($url) || return;
    $urlstr = unescape($urlstr);

    my $r = { url => $urlstr };
    if ($title) {
        return if $title->match(qr/\n\s*\n/);
        $r->{title} = unescape($title->{txt});
    }

    $_[0] = $s;
    return $r;
}

# Добавляет элемент в content. Последовательные элементы listitem с одинаковым
# типом маркера объединяются в общий list, остальные добавляются без преобразования.
sub contadd {
    my ($c, $e) = @_;

    if ($e->{type} eq 'listitem') {
        my ($prv) = @$c ? $c->[ @$c-1 ] : undef;
        if (
                $prv && ($prv->{type} eq 'list') &&
                ($prv->{mode} eq $e->{mode}) &&
                (
                    ($e->{mode} ne 'ord') ||
                    (($prv->{mark} // '.') eq ($e->{mark} // '.'))
                )
            ) {
            push @{ $prv->{content} }, $e;
            return $c;
        }
        $e = {
            type    => 'list',
            mode    => $e->{mode},
            $e->{mode} eq 'ord' ? (mark => $e->{mark}) : (),
            content => [$e]
        };
    }
    push @$c, $e;
    $c;
}

# Возвращает видимый текст inline-элементов без форматирования. Применяется
# при формировании идентификатора заголовка.
sub txt2str {
    my $s = '';

    foreach my $c (@_) {
        if (ref($c) eq 'txt') {
            $s .= $c->{txt};
        }
        elsif (ref($c) eq 'HASH') {
            my $text = $c->{text};
            if (ref($text) eq 'ARRAY') {
                $s .= txt2str(@$text);
            }
            elsif (ref($text) eq 'txt') {
                $s .= $text->{txt};
            }
            elsif (defined($text) && !ref($text)) {
                $s .= $text;
            }
        }
    }

    return $s;
}

# Нормализует ссылочную метку по правилам CommonMark: Unicode case folding,
# удаление крайних пробелов и объединение внутреннего whitespace.
sub _badgenorm {
    my $s = fc(unescape(shift() // ''));

    $s =~ s/^[\x20\t\r\n]+//;
    $s =~ s/[\x20\t\r\n]+$//;
    $s =~ s/[\x20\t\r\n]+/ /g;
    return $s;
}

# Проверяет баланс неэкранированных круглых скобок в URL.
sub _badgeurl {
    my $s = shift;
    my $deep = 0;

    while (length($s)) {
        if ($s =~ s/^\\$punctuation//) {
            next;
        }
        my $c = substr($s, 0, 1, '');
        $deep ++ if $c eq '(';
        return if ($c eq ')') && !$deep;
        $deep -- if $c eq ')';
    }

    return $deep == 0;
}

# Заменяет ссылочные изображения найденными определениями. Неизвестная метка
# восстанавливается исходным txt-фрагментом и выводится буквально. Проход выполняется
# после полного разбора, так как ссылочное определение может находиться после его использования.
sub _badgeresolve {
    my ($v, $glb) = @_;
    my $ball = $glb->{ball} || {};

    if (ref($v) eq 'ARRAY') {
        foreach my $n (0 .. $#$v) {
            my $e = $v->[$n];
            if ((ref($e) eq 'HASH') && (($e->{type} || '') eq 'badge')) {
                my $def = $ball->{ _badgenorm($e->{code}) };
                if (!$def) {
                    $v->[$n] = $e->{raw};
                    next;
                }

                $v->[$n] = {
                    type    => 'image',
                    pos     => $e->{pos},
                    url     => $def->{url},
                    text    => $e->{text} || [],
                    alt     => txt2str(@{ $e->{text} || [] }),
                    exists($def->{title}) ?
                        (title  => $def->{title}) : (),
                };
                next;
            }
            _badgeresolve($e, $glb);
        }
    }
    elsif (ref($v) eq 'HASH') {
        foreach my $e (values %$v) {
            _badgeresolve($e, $glb) if ref($e) eq 'ARRAY' || ref($e) eq 'HASH';
        }
    }
}


# ----------------------------------------------------------------------
# ---
# ---   doc
# ---
# Разбирает документ верхнего уровня. В отличие от level(), здесь разрешены
# модификаторы документа и заголовки; каждому заголовку назначается уникальный id.
# Общие данные документа хранятся в %glb, передаваемом во все ветви парсера;
# вложенные списки и хеши создаются лениво в месте их первого использования. Модификаторы
# выравнивания удаляются и переносятся в следующий текстовый абзац.
sub doc {
    my ($s) = @_;

    my $content = [];
    my %glb = ();
    my %align = ();
    my $alignpos;

    while (!$s->empty()) {
        # Предполагается, что тут только получение элементов.
        #
        # Не следует сюда добавлять логику, особенно поэлементную.
        # Логику по обработке определённых элементов следует размещать
        # внутри формирователей этих элементов (modificator, header и т.д.).
        #
        # Глобальные данные документа накапливаются внутри %glb самими
        # распознающими функциями.
        my $e =
            modificator ($s, \%glb) || # Специальные модификаторы и
            header      ($s, \%glb) || # заголовки могут быть только на верхнем уровне
            paragraph   ($s, \%glb);
        
        $e || return err($s->{pos}, 'doc > Can\t parse symbol');

        # С модификаторами \align и \valign особый случай, поэтому их
        # логика размещена именно здесь, а не внутри modificator/paragraph.
        # Эти модификаторы не должны попадать в список $content (хотя,
        # не вижу никаких проблем, если оно там окажется).
        # Эти модификаторы должны вызывать ошибку, если следом будет
        # что-то, кроме text и этих же модификаторов. Чтобы нормально
        # эту ситуацию обработать, лучше размещать логику тут, а не внутри
        # парсящих функций.

        if (
                ($e->{type} eq 'modifier') &&
                (($e->{name} eq 'center') || ($e->{name} eq 'vcenter'))
            ) {
            $alignpos ||= $e->{pos};
            $align{ $e->{name} eq 'center' ? 'align' : 'valign' } = 'c';
            next;
        }

        if (%align) {
            if ($e->{type} ne 'text') {
                my ($row, $col) = @{ $e->{pos} || $alignpos };
                return err(
                    sprintf(
                        '[ln: %d, col: %d] doc > Alignment modifier requires text paragraph',
                        $row, $col
                    )
                );
            }
            $e->{align} = $align{align} if $align{align};
            $e->{valign} = $align{valign} if $align{valign};
            %align = ();
            undef($alignpos);
        }

        contadd($content, $e);
    }

    if (%align) {
        my ($row, $col) = @$alignpos;
        return err(
            sprintf(
                '[ln: %d, col: %d] doc > Alignment modifier requires text paragraph',
                $row, $col
            )
        );
    }

    # Определения собраны во время основного прохода. После полного разбора
    # разрешаем ссылки, которые могут находиться раньше своих определений.
    _badgeresolve($content, \%glb);

    # Оглавлению нужен полный список заголовков независимо от положения
    # модификатора в документе. Элементы списка не изменяются рендерерами.
    foreach my $e (@$content) {
        next if ($e->{type} ne 'modifier') || ($e->{name} ne 'toc');
        $e->{content} = [ @{ $glb{hall} || [] } ];
    }

    $_[0] = $s;
    return $content;
}

sub modificator {
    my ($s, $glb) = @_;

    my $ln = line($s, 1, 1) || return;
    match($ln, my $beg, my $m, qr/ {0,3}(\\(pagebreak|toc|center|vcenter))\s*$/) || return;

    $_[0] = $s;
    return {
        type    => 'modifier',
        pos     => [$beg->pos()],
        name    => $m->{txt}
    };
}

sub header {
    my ($s, $glb) = @_;

    my $ln = line($s, 1, 1) || return;
    match($ln, my $p, my $t, qr/ {0,3}(\#+)(?:[ \t]+(.*))?$/) || return;
    my $text = (!$t || ($t->{txt} eq '')) ? [] : inline($t, $glb) || return;

    # Формируем GitHub-совместимый уникальный идентификатор заголовка.
    my $id = lc txt2str(@$text);
    $id =~ s/^\s+|\s+$//g;
    $id =~ s/ /-/g;
    $id =~ s/[^\p{L}\p{M}\p{N}_\-]//g;

    my $idall = ($glb->{idall} ||= {});
    my $base = $id;
    my $n = 0;
    $id = $base . '-' . ++$n while exists $idall->{$id};
    $idall->{$id} = 1;

    # список всех заголовков для toc
    my $hall = ($glb->{hall} ||= []);
    push @$hall, {
        deep    => length($p->{txt}),
        id      => $id,
        title   => txt2str(@$text)
    };

    $_[0] = $s;
    return {
        type    => 'header',
        pos     => [$p->pos()],
        deep    => length($p->{txt}),
        id      => $id,
        text    => $text
    };
}


# ----------------------------------------------------------------------
# ---
# ---   Paragraph
# ---
# Разбирает вложенный уровень документа, состоящий только из абзацных элементов.
sub level {
    my ($s, $glb) = @_;

    my $content = [];

    while (!$s->empty()) {
        my $e = paragraph($s, $glb);
        $e || return err($s->{pos}, 'level > Can\t parse symbol');
        contadd($content, $e);
    }

    $_[0] = $s;
    return $content;
}

# Пропускает разделяющие пустые строки и запускает подходящий распознаватель
# одного блочного элемента.
sub paragraph {
    my ($s, $glb) = @_;

    # Сразу пропустим все пустые строки, т.к. они в этом месте всегда игнорируются
    while (($s->{txt} ne '') && (my ($ln, $tail) = $s->line(1))) {
        $ln->empty() || last;
        $s = $tail;
    }

    my $e =
        list        ($s, $glb) ||
        hline       ($s, $glb) ||
        code        ($s, $glb) ||
        quote       ($s, $glb) ||
        textblock   ($s, $glb) ||
        badge       ($s, $glb) ||
        table1      ($s, $glb) ||
        table2      ($s, $glb) ||
        text        ($s, $glb);
    
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
    my ($s, $glb) = @_;

    return if $s->empty();

    my $txt = match($s, qr/[^\n]*(?:\n((?!$textend)[ \t]*\S[^\n]*(?:\n|$))*|$)/) || return;

    # стравим пробельные символы вначале и вконце, они точно не нужны
    match($txt, qr/\s+/);
    $txt->{txt} =~ s/[\r\n]+$//;

    my $pos = [$txt->pos()];
    my $cont = inline($txt, $glb) || return;

    $_[0] = $s;
    return {
        type    => 'text',
        pos     => $pos,
        text    => $cont
    };
}

# Распознаёт один элемент маркированного или нумерованного списка вместе
# с его вложенным блоком. Первым блоком может быть ссылочное определение.
# Объединение соседних пунктов выполняет contadd().
sub list {
    my ($s, $glb) = @_;

    match($s, my $mark, qr/ {0,3}([\*\-\+]|\d+[\.\)])[ \t]+/) || return;
    my @content = badge($s, $glb) || text($s, $glb) || return;

    if (my $ind = indent($s, qr/(?: {4}| {0,3}\t)/, 1)) {
        my $sub = level($ind, $glb) || return;
        push @content, @$sub;
    }

    $_[0] = $s;
    return {
        type    => 'listitem',
        pos     => [$mark->pos()],
        $mark->{txt} =~ /(\d+)([\.\)])/ ? (
            mode    => 'ord',
            num     => int($1),
            mark    => $2
        ) : (
            mode    => $mark->{txt}
        ),
        content   => [@content]
    };
}

# Три варианта горизонтальной линии: отдельная строка из дефисов, заголовок
# с подчёркиванием дефисами и отдельная строка из символов подчёркивания.
sub hline1 {
    my ($s, $glb) = @_;

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
    my ($s, $glb) = @_;

    my $text = text($s, $glb) || return;

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
    my ($s, $glb) = @_;

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
    my ($s, $glb) = @_;

    my $e =
        hline1($s, $glb) ||
        hline2($s, $glb) ||
        hline3($s, $glb);

    $e || return;
    $_[0] = $s;
    return $e;
}

# Распознаёт fenced-блок между строками ```, сохраняя необязательное имя языка.
sub code {
    my ($s, $glb) = @_;

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

# Вырезает строки с префиксом > и рекурсивно разбирает их как вложенный уровень.
sub quote {
    my ($s, $glb) = @_;

    my @pos = $s->pos();
    my $ind = indent($s, qr/ {0,3}\>/) || return;
    my $cont = level($ind, $glb) || return;

    $_[0] = $s;
    return {
        type    => 'quote',
        pos     => [@pos],
        content => $cont,
    };
}

# Распознаёт блок строк с отступом в четыре пробела или одну табуляцию.
sub textblock {
    my ($s, $glb) = @_;

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

# Разбирает определение ссылочной метки: код, URL и необязательный заголовок.
# URL может быть заключён в угловые скобки, а title может занимать несколько
# строк, но не содержит пустого абзаца.
sub badge {
    my ($s, $glb) = @_;

    my @pos = $s->pos();
    match(
        $s,
        my $code, my $url1, my $url2,
        my $title1, my $title2, my $title3,
        qr/ {0,3}\[((?:$escaped|[^\[\]\r\n])+?)\][ \t]*\:[ \t]*(?:\r?\n[ \t]*)?(?:\<((?:$escaped|[^\<\>\r\n])*)\>|($refurl))(?:(?:[ \t]+|[ \t]*\r?\n[ \t]*)(?:\"((?:$escaped|[^\"])*)\"|\'((?:$escaped|[^\'])*)\'|\(((?:$escaped|[^\(\)])*)\)))?[ \t]*(?:\r?\n|$)/
    ) || return;

    return if $code->{txt} !~ /[^\s]/;

    my $url = $url1 || $url2;
    my $title = $title1 || $title2 || $title3;
    return if $url2 && !_badgeurl($url2->{txt});
    return if $title && ($title->{txt} =~ /\n[ \t\r]*\n/);

    my $e = {
        type    => 'badgedef',
        pos     => [@pos],
        code    => $code->{txt},
        url     => unescape($url->{txt}),
        $title ?
            (title   => unescape($title->{txt})) : (),
    };

    my $ball = ($glb->{ball} ||= {});
    my $key = _badgenorm($e->{code});
    $ball->{$key} = $e if !exists($ball->{$key});

    $_[0] = $s;
    return $e;
}

# Разбирает одну строку pipe-таблицы и возвращает список inline-ячеек.
# Крайние символы | необязательны, но в строке должен быть хотя бы один |.
sub _table1_line {
    my ($s, $glb) = @_;

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
        my $cont = inline($ln, $glb, qr/\|/) || return;
        push @$row, $cont;
    }

    # Убедимся, что в строке есть хотябы одна |
    # Если колонок две и более, это значи, что первая колонка точно заканчивается на |
    # Если колонок меньше, то должен быть | в начале строки или в конце ($f = true)
    return if (@$row < 2) && !$f;

    $_[0] = $s;
    return $row;
}

# Разбирает pipe-таблицу с обязательной строкой-разделителем, из которой
# извлекаются ширина и выравнивание столбцов.
sub table1 {
    my ($s, $glb) = @_;

    my @pos = $s->pos();
    my $hdr = _table1_line($s, $glb) || return;

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
        my $row = _table1_line($s, $glb) || last;
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

# Следующие функции считают экранные позиции символов для таблицы с фиксированной
# разметкой: табуляция переводит позицию к следующей границе в четыре символа.
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

# Разбирает таблицу, где границы столбцов задаются группами дефисов. Ячейка может
# занимать несколько строк; её содержимое после нарезки разбирается через inline().
sub table2 {
    my ($s, $glb) = @_;

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
            $txt = inline($txt, $glb) || return;
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
    my ($s, $glb, $end) = @_;
    # Если указан шаблон $end, то поиск будет остановлен по достижению этого шаблона,
    # а валидный возврат будет только в случае, если было совпадение с данным шаблоном.
    # Экранированная пунктуация обрабатывается раньше $end и остальных конструкций,
    # поэтому сохраняет буквальное значение даже на границе вложенного элемента.
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

        # от inline_XXX функций мы не будем ожидать pos в ответе,
        # сформируем его сами после вызова
        my @pos = $s->pos();

        my $f = inline_escape($s, $glb);

        if (!$f && $end && match($s, my $s1, $end)) {
            # сработал $end
            # если в нём применялся фрагмент, то его надо дописать к текстовой строке.
            $txt->{txt} .= $s1->{txt} if $s1;
            undef $end;
            last;
        }

        $f ||=
            inline_strike   ($s, $glb) ||
            inline_underline($s, $glb) ||
            inline_mark     ($s, $glb) ||
            inline_bold1    ($s, $glb) ||
            inline_bold2    ($s, $glb) ||
            inline_italic1  ($s, $glb) ||
            inline_italic2  ($s, $glb) ||
            inline_code     ($s, $glb) ||
            inline_image    ($s, $glb) ||
            inline_href     ($s, $glb) ||
            inline_badge    ($s, $glb);
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

# Распознаватели inline-элементов изменяют исходный txt-объект только при полном
# совпадении и возвращают элемент для общего массива содержимого inline().
sub inline_escape {
    my ($s, $glb) = @_;

    my $nobrbeg = $s->{prev} && ($s->{prev} =~ /\S$/);
    match($s, my $text, qr/\\($punctuation)/) || return;
    my $nobrend = $s->{txt} =~ /^\S/;

    $_[0] = $s;
    return {
        type    => 'escape',
        text    => $text->{txt},
        $nobrbeg ? (nobrbeg => 1) : (),
        $nobrend ? (nobrend => 1) : (),
    };
}

sub inline_strike {
    my ($s, $glb) = @_;

    match($s, qr/\~\~/) || return;
    my $text = inline($s, $glb, qr/\~\~/) || return;

    $_[0] = $s;
    return {
        type    => 'strike',
        text    => $text
    };
}

sub inline_underline {
    my ($s, $glb) = @_;

    match($s, qr/\+\+/) || return;
    my $text = inline($s, $glb, qr/\+\+/) || return;

    $_[0] = $s;
    return {
        type    => 'underline',
        text    => $text
    };
}

sub inline_mark {
    my ($s, $glb) = @_;

    match($s, qr/\=\=/) || return;
    my $text = inline($s, $glb, qr/\=\=/) || return;

    $_[0] = $s;
    return {
        type    => 'mark',
        text    => $text
    };
}

sub inline_bold1 {
    my ($s, $glb) = @_;

    match($s, qr/__/) || return;
    my $text = inline($s, $glb, qr/__/) || return;

    $_[0] = $s;
    return {
        type    => 'bold',
        text    => $text
    };
}

sub inline_bold2 {
    my ($s, $glb) = @_;

    match($s, qr/\*\*/) || return;
    my $text = inline($s, $glb, qr/\*\*/) || return;

    $_[0] = $s;
    return {
        type    => 'bold',
        text    => $text
    };
}

sub inline_italic1 {
    my ($s, $glb) = @_;
    
    return if $s->{prev} && ($s->{prev} =~ /[a-zA-Z0-9а-яА-Я\_]$/);
    match($s, qr/_/) || return;
    return if $s->{txt} =~ /^\_/;
    my $text = inline($s, $glb, qr/_\b/) || return;

    $_[0] = $s;
    return {
        type    => 'italic',
        text    => $text
    };
}

sub inline_italic2 {
    my ($s, $glb) = @_;

    match($s, qr/\*/) || return;
    return if $s->{txt} =~ /^\*/;
    my $text = inline($s, $glb, qr/\*/) || return;

    $_[0] = $s;
    return {
        type    => 'italic',
        text    => $text
    };
}

sub inline_code {
    my ($s, $glb) = @_;

    # вроде б как inlinecode не должен внутри себя парсить форматтеры
    match($s, my $text, qr/\`(.+?)\`/) || return;

    $_[0] = $s;
    return {
        type    => 'inlinecode',
        text    => $text->{txt}
    };
}

# Разбирает изображение с форматируемым описанием, URL и необязательным title.
sub inline_image {
    my ($s, $glb) = @_;

    match($s, qr/\!\[(?:[ \t\r]*\n)?/) || return;
    my $text = inline($s, $glb, qr/\]/) || return;

    my $target = inline_target($s, $glb) || return;

    $_[0] = $s;
    return {
        type    => 'image',
        url     => $target->{url},
        @$text ?
            (text   => $text)           : (),
        exists($target->{title}) ?
            (title  => $target->{title}): (),
    };
}

# Разбирает ссылку с форматируемым текстом, URL и необязательным title.
sub inline_href {
    my ($s, $glb) = @_;

    match($s, qr/\[(?:[ \t\r]*\n)?/) || return;
    my $text = inline($s, $glb, qr/\]/) || return;

    my $target = inline_target($s, $glb) || return;

    $_[0] = $s;
    return {
        type    => 'href',
        url     => $target->{url},
        text    => $text,
        exists($target->{title}) ?
            (title  => $target->{title}) : (),
    };
}

# Разбирает полную, свёрнутую и короткую формы ссылочного изображения.
sub inline_badge {
    my ($s, $glb) = @_;

    my $src = $s->copy();

    match($s, qr/\!\[(?:[ \t\r]*\n)?/) || return;
    my $desc = $s->{txt};
    my $text = inline($s, $glb, qr/\]/) || return;

    my $used = length($desc) - length($s->{txt});
    my $code = substr($desc, 0, $used);
    $code =~ s/\]$//;

    # Полная форма имеет собственную метку, свёрнутая и короткая используют
    # исходное содержимое описания изображения.
    if (match($s, my $label, qr/\[((?:$escaped|[^\[\]\r\n])+)\]/)) {
        $code = $label->{txt};
    }
    else {
        match($s, qr/\[\]/);
    }

    return if $code !~ /[^\s]/;

    my $len = length($src->{txt}) - length($s->{txt});
    my $raw = $src->copy(txt => substr($src->{txt}, 0, $len));

    $_[0] = $s;
    return {
        type    => 'badge',
        code    => $code,
        raw     => $raw,
        text    => $text,
    };
}

1;
