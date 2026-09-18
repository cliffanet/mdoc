package out::html;

use strict;
use warnings;

use base 'out';

use Encode;

# HTML-рендерер сначала собирает дерево строк и вложенных DNode, а data()
# рекурсивно преобразует его в готовый документ.

# Создаёт корневой узел документа и устанавливает его текущим контекстом вывода.
sub new {
    my $self = shift()->SUPER::new(@_);

    $self->{doc} = DNode->new();
    $self->{ctx} = $self->{doc};

    return $self;
}

# Сериализует дерево документа. Если указан html-template, читает шаблон как
# необработанные байты и подставляет метаданные, пользовательские переменные
# и сформированное содержимое в предусмотренные маркеры.
sub data {
    my $self = shift;

    my $out = $self->{doc}->out();

    if (my $fname = $self->{opt}->{'html-template'}) {
        my $tmpl;
        if (open(my $fh, '<:raw', $fname)) {
            local $/ = undef;
            $tmpl = <$fh>;
            close $fh;
        }
        else {
            print STDERR 'Can\' open \''.$fname.'\': ' . $! . "\n";
            return;
        }

        my %opt = %{ $self->{opt} };
        # Значения приходят как из UTF-8 документа, так и из командной строки;
        # перед байтовыми подстановками шаблона их флаги кодировки выравниваются.
        Encode::_utf8_off($_) foreach values %opt;

        $tmpl =~ s/%producer%/mdoc v1.0/ig;
        $tmpl =~ s/%author%/$opt{author}||''/ige;
        $tmpl =~ s/%title%/$opt{title}||''/ige;
        
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime(CORE::time());
        my $created = sprintf('%04d-%02d-%02d %2d:%02d:%02d', $year+1900, $mon+1, $mday, $hour, $min, $sec);
        $tmpl =~ s/%created%/$created/ige;

        my $mtime = (stat $self->{opt}->{src})[9];
        ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime($mtime);
        my $fchanged = sprintf('%04d-%02d-%02d %2d:%02d:%02d', $year+1900, $mon+1, $mday, $hour, $min, $sec);
        $tmpl =~ s/%fchanged%/$fchanged/ige;

        my $tmplpath = $fname;
        $tmplpath =~ s/[^\/\\]+$//;
        #$tmplpath =~ s/[\/\\]$//;
        $tmpl =~ s/%tmplpath%/$tmplpath/ige;

        my %var = %{ $opt{var}||{} };
        Encode::_utf8_off($_) foreach values %var;
        $tmpl =~ s/%var\(([a-zA-Z0-9_\-]+)\)%/$var{$1}\/\/''/ige;

        if (my $fname = $opt{src} || $opt{dst}) {
            $fname =~ s/^.*[\/\\]//;
            $fname =~ s/\.(md|txt|html|pdf)$//i;
            $tmpl =~ s/%fname%/$fname/ige;
        }

        $tmpl =~ s/%CONTENT%/$out/ige;
        $out = $tmpl;
    }
    
    return $out;
}

# Создаёт дочерний узел и временно направляет в него вывод make(). После выхода
# локальный ctx автоматически восстанавливает родительский контекст.
sub subnode {
    my $self = shift;

    my $node = DNode->new();
    local $self->{ctx} = $node;

    $self->make( @_ ) if @_;

    return $node;
}

# Блочные обработчики получают поля элемента парсера и добавляют HTML-фрагменты
# в текущий ctx. Вложенное содержимое строится в отдельных узлах через subnode().
sub modifier {
    my ($self, %p) = @_;

    if ($p{name} eq 'pagebreak') {
    }
}

sub header {
    my ($self, %p) = @_;

    my $id = html_escape($p{id});
    
    $self->{ctx}->add(
        '<h'.int($p{deep}).' id="'.$id.'">',
        $self->subnode( @{ $p{ text } } ),
        '</h'.int($p{deep}).'>',
    );
}

sub hline {
    my ($self, %p) = @_;
    
    if (my @txt = @{ $p{ text } || [] }) {
        $self->{ctx}->add(
            '<h2 class="horizontal-line">',
            $self->subnode( @txt ),
            '</h2>',
        );
    }
    else {
        $self->{ctx}->add('<hr/>');
    }
}

sub code {
    my ($self, %p) = @_;
    # для code хорошо бы сделать парсинг кода,
    # но пока просто доблируем работу textblock
    
    $self->{ctx}->add(
        '<pre class="code"><code class="block">',#."\n",
        $self->subnode( $p{ text } ),
        '</code></pre>',
    );
}

sub textblock {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<pre class="textblock"><code class="block">',#."\n",
        $self->subnode( $p{ text } ),
        '</code></pre>',
    );
}

sub quote {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<blockquote>',
        $self->subnode( @{ $p{ content } } ),
        '</blockquote>',
    );
}

sub list {
    my ($self, %p) = @_;

    my $l = $p{mode} eq 'ord' ? 'ol' : 'ul';
    
    $self->{ctx}->add(
        '<'.$l.'>',
        $self->subnode( @{ $p{ content } } ),
        '</'.$l.'>',
    );
}

sub listitem {
    my ($self, %p) = @_;

    my $v = $p{mode} eq 'ord' ? ' value="'.int($p{num}).'"' : '';

    my ($f, @content) = @{ $p{ content } };
    
    $self->{ctx}->add(
        '<li'.$v.'>',
        $f->{type} eq 'text' ? (
            # Первый текстовый абзац пункта не заворачивается в <p>, чтобы
            # не создавать лишний вертикальный интервал внутри <li>.
            '<div>', # иногда всё-таки требуется выделять первый абзац,
                     # поэтому хоть в какой-нибудь блок его завенуть надо
            $self->subnode( @{ $f->{text} } ),
            '</div>',
            $self->subnode( @content )
        ) : (
            $self->subnode( @{ $p{ content } } )
        ),
        '</li>',
    );
}

sub text {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<p>',
        $self->subnode( @{ $p{ text } } ),
        '</p>',
    );
}

sub table {
    my ($self, %p) = @_;
    
    my @hdr = ();
    # Ширина и выравнивание назначаются по порядку столбцов. Ширина нужна
    # только первой выведенной строке: браузер применит её ко всему столбцу.
    my @w = @{ $p{width}||[] };
    my @a = @{ $p{align}||[] };
    foreach my $h (@{ $p{hdr}||[] }) {
        my $al = shift @a;
        my $align =
            $al eq 'r'  ? ' class="align-right"' :
            $al eq 'c'  ? ' class="align-center"' :
            #$al eq 'l'  ? ' class="align-left"' :
                        '';
        push @hdr,
            '<th'.$align.' style="width: '.int(shift @w).'">',
            $self->subnode( @$h ),
            '</th>';
    }
    if (@hdr) {
        @hdr = ( '<thead>', @hdr, '</thead>' );
        @w = ();
    }
    
    my @body = ();
    foreach my $row (@{ $p{row}||[] }) {
        push @body, '<tr>';
        my @a = @{ $p{align}||[] };
        foreach my $col (@$row) {
            my $al = shift(@a) // 'l';
            my $align =
                $al eq 'r'  ? ' class="align-right"' :
                $al eq 'c'  ? ' class="align-center"' :
                #$al eq 'l'  ? ' class="align-left"' :
                            '';
            my $width = '';
            if (my $w = shift @w) {
                $width = ' style="width: '.$w.'"';
            }
            push @body,
                '<td'.$align.$width.'>',
                $self->subnode( @$col ),
                '</td>';
        }
        push @body, '</tr>';
        @w = ();
    }
    $self->{ctx}->add(
        '<table class="table'.int($p{mode}).'">',
            @hdr,
            '<tbody>',
                @body,
            '</tbody>',
        '</table>'
    );
}

#   -------------
#   inline
#   -------------

# Кодирует текст для безопасного размещения в HTML-тексте или атрибуте.
sub html_escape {
    my $s = shift // '';

    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/\"/&quot;/g;
    $s =~ s/\'/&#39;/g;

    return $s;
}

# Строчные обработчики добавляют текст или HTML-теги в текущий узел; вложенная
# разметка форматируемых элементов также собирается через subnode(). Элемент
# escape кодируется отдельно, чтобы обычный текст сохранил прежнее поведение.
sub str {
    my ($self, %p) = @_;

    $self->{ctx}->add( $p{txt} );
}

sub escape {
    my ($self, %p) = @_;

    $self->{ctx}->add( html_escape($p{text}) );
}

sub bold {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<strong>',
        $self->subnode( @{ $p{ text } } ),
        '</strong>',
    );
}

sub italic {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<em>',
        $self->subnode( @{ $p{ text } } ),
        '</em>',
    );
}

sub strike {
    my ($self, %p) = @_;

    $self->{ctx}->add(
        '<del>',
        $self->subnode( @{ $p{ text } } ),
        '</del>',
    );
}

sub underline {
    my ($self, %p) = @_;

    $self->{ctx}->add(
        '<u>',
        $self->subnode( @{ $p{ text } } ),
        '</u>',
    );
}

sub mark {
    my ($self, %p) = @_;

    $self->{ctx}->add(
        '<mark>',
        $self->subnode( @{ $p{ text } } ),
        '</mark>',
    );
}

sub inlinecode {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<code class="inline">',
        $p{ text },
        '</code>',
    );
}

# Выводит изображение, кодируя URL и существующий заголовок для HTML-атрибутов.
sub image {
    my ($self, %p) = @_;

    my $url = html_escape($p{url});
    my $title = $p{title} ? html_escape($p{title}) : '';
    my $attr = $title ? ' alt="'.$title.'" title="'.$title.'"' : '';
    
    $self->{ctx}->add(
        '<img src="'.$url.'"'.$attr.'>',
    );
}

# Выводит ссылку: при необходимости меняет расширение Markdown-документа,
# дополняет внешний относительный URL настройкой base-uri и кодирует атрибут.
# Внутридокументный fragment настройкой base-uri не дополняется.
sub href {
    my ($self, %p) = @_;

    # При необходимости (опции) сменим формат документу
    my $url = $self->urlbyfmt($p{url}, 'html');
    # Если путь получился относительный, добавим ему html-base-uri
    if (
            ($url !~ /^(?:[a-z][a-z0-9+\.\-]*\:|\/\/|\#)/i) &&
            (my $base = $self->{opt}->{'html-base-uri'})
        ) {
        $url = $base . $url;
    }
    $url = html_escape($url);
    
    $self->{ctx}->add(
        '<a href="'.$url.'">',
        $self->subnode( @{ $p{ text } } ),
        '</a>',
    );
}


#   -------------
#   DNode
#   -------------

package DNode;

# Узел промежуточного HTML-дерева. Потомки могут быть строками или другими
# DNode, что позволяет собирать вложенную разметку без ручного управления стеком.
sub new {
    my $class = shift();
    return bless({ @_, chld => [] }, $class);
}

sub add {
    my $self = shift;
    push @{ $self->{chld} }, @_;
}

sub empty   { return  @{ shift()->{chld} } == 0; }

sub chld    { return @{ shift()->{chld} }; }

# Рекурсивно сериализует дочерние узлы и объединяет их в одну байтовую строку.
sub out {
    my $self = shift;

    my @txt =
        map {
            ref($_) eq 'DNode' ?
                $_->out() :
                $_;
        }
        $self->chld();
    
    Encode::_utf8_off($_) foreach @txt;
    
    return join('', @txt);
}

1;
