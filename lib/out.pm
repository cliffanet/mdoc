package out;

use strict;
use warnings;

# Базовый класс выходных модулей. Наследник реализует data() и нужные
# обработчики элементов, полученных от парсера.

# Создаёт рендерер и сохраняет все переданные параметры в opt.
sub new {
    my $class = shift;

    return bless { opt => { @_ } }, $class;
}

# При включённой опции меняет расширение относительной Markdown-ссылки
# с якорем на расширение текущего выходного формата.
sub _urlbyfmt {
    my ($url, $fmt, $opt) = @_;

    return $url if !$opt->{'lnk-fmt'};
    return $url if $url =~ /^(?:[a-z][a-z0-9+\.\-]*\:|\/\/|\/|\#)/i;

    my $ext = '.' . $fmt;
    $url =~ s/\.md(?=(?:\?[^\#]*)?\#[^\#]+$)/$ext/i;
    return $url;
}

# Применяет _urlbyfmt() с настройками текущего рендерера.
# Такая сложная конструкция с вложением одного в другое из-за out::pdf: там вызов _urlbyfmt
# происходит из stage4draw, внутри которой есть $opt, но нет объекта out (там своя структура объектов).
# И поэтому сделать простой вызов $self->urlbyfmt($url, $fmt) не получается. Там приходится вызывать:
# out::_urlbyfmt($self->{url}, 'pdf', $opt);
# Вообще, передачу out внутри работы pdf-классов надо пересмотреть. Там при текущей реализации
# регулярно не хватает элементов из out. Но пока вот такой костыль.
sub urlbyfmt {
    my ($self, $url, $fmt) = @_;

    return _urlbyfmt($url, $fmt, $self->{opt});
}

# Фильтрует элементы оглавления настройками рендерера и строит дерево.
# Родителем становится ближайший предыдущий заголовок меньшей глубины.
sub tocdata {
    my ($self, $content) = @_;

    my $hmax = 6;
    if (defined(my $v = $self->{opt}->{'toc-hmax'})) {
        if ($v =~ /^[\+\-]?\d+$/) {
            $hmax = int($v);
            $hmax = 1 if $hmax < 1;
            $hmax = 6 if $hmax > 6;
        }
    }

    # вложенное дерево content состоит только из элементов toc,
    # content содержит заголовки более глубокого уровня, чем текущий
    my @toc = ();
    my @stack;
    foreach my $h (@{ $content || [] }) {
        next if $self->{opt}->{'toc-noh1'} && ($h->{deep} == 1);
        next if $h->{deep} > $hmax;

        my $node = {
            %$h,
            content => []
        };
        pop @stack while @stack && ($stack[@stack-1]->{deep} >= $h->{deep});
        if (@stack) {
            push @{ $stack[@stack-1]->{content} }, $node;
        }
        else {
            push @toc, $node;
        }
        push @stack, $node;
    }

    return @toc;
}

# Последовательно передаёт текстовые и структурные элементы соответствующим
# обработчикам рендерера. Неизвестные типы элементов пропускаются.
sub make {
    my $self = shift;

    foreach my $p (@_) {
        if (ref($p) eq 'txt') {
            $self->str(%$p);
        }
        elsif (ref($p) eq 'HASH') {
            my $type = $p->{type} || next;
            $self->can($type) || next;
            $self->$type(%$p);
        }
    }

    return 1;
}

# Записывает результат data(), сформированный выходным модулем, в файл.
sub save {
    my ($self, $fname) = @_;

    open(my $fh, '>', $fname) || return;
    print $fh $self->data();
    close $fh;

    return 1;
}

# Необязательные точки расширения для блочных элементов. Выходной модуль
# переопределяет только поддерживаемые обработчики; str() и data() должны
# быть предоставлены наследником в соответствии с форматом результата.
sub modifier    {}
sub header      {}
sub listitem    {}
sub hline       {}
sub table       {}
sub code        {}
sub quote       {}
sub textblock   {}
sub paragraph   {}

1;
