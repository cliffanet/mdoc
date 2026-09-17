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
