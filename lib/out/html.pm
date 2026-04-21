package out::html;

use strict;
use warnings;

use base 'out';

use Encode;

sub new {
    my $self = shift()->SUPER::new(@_);

    $self->{doc} = DNode->new();
    $self->{ctx} = $self->{doc};

    return $self;
}

sub data {
    my $self = shift;

    my $out = $self->{doc}->out();

    if (my $fname = $self->{opt}->{'html-template'}) {
        open(my $fh, '<', $fname) || return;
        local $/ = undef;
        my $tmpl = <$fh>;
        close $fh;

        my %opt = %{ $self->{opt} };
        Encode::_utf8_off($_) foreach values %opt;

        $tmpl =~ s/%producer%/mdoc v1.0/ig;
        $tmpl =~ s/%author%/$opt{author}||''/ige;
        $tmpl =~ s/%title%/$opt{title}||''/ige;
        
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime(CORE::time());
        my $created = sprintf('%04d-%02d-%02d %2d:%02d:%02d', $year+1900, $mon+1, $mday, $hour, $min, $sec);
        $tmpl =~ s/%created%/$created/ige;

        my $tmplpath = $fname;
        $tmplpath =~ s/[^\/\\]+$//;
        #$tmplpath =~ s/[\/\\]$//;
        $tmpl =~ s/%tmplpath%/$tmplpath/ige;

        $tmpl =~ s/%CONTENT%/$out/ige;
        $out = $tmpl;
    }
    
    return $out;
}

sub subnode {
    my $self = shift;

    my $node = DNode->new();
    local $self->{ctx} = $node;

    $self->make( @_ ) if @_;

    return $node;
}

sub modifier {
    my ($self, %p) = @_;

    if ($p{name} eq 'pagebreak') {
    }
}

sub header {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<h'.int($p{deep}).'>',
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
        '<pre class="code"><code>',#."\n",
        $self->subnode( $p{ text } ),
        '</code></pre>',
    );
}

sub textblock {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<pre class="textblock"><code>',#."\n",
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
            # первый text не будем заворачивать в <p>
            $self->subnode( @{ $f->{text} } ),
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
    my @w = @{ $p{width} };
    my @a = @{ $p{align} };
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
        my @a = @{ $p{align} };
        foreach my $col (@$row) {
            my $al = shift @a;
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

sub str {
    my ($self, %p) = @_;

    $self->{ctx}->add( $p{txt} );
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

sub inlinecode {
    my ($self, %p) = @_;
    
    $self->{ctx}->add(
        '<code>',
        $p{ text },
        '</code>',
    );
}

sub image {
    my ($self, %p) = @_;

    my $title = $p{title} ? ' alt="'.$p{title}.'" title="'.$p{title}.'"' : '';
    
    $self->{ctx}->add(
        '<img src="'.$p{url}.'"'.$title.'>',
    );
}

sub href {
    my ($self, %p) = @_;

    my $url = $p{url};
    if (($url !~ /^[a-z]{2,5}\:\/\//i) && (my $base = $self->{opt}->{'html-base-uri'})) {
        $url = $base . $url;
    }
    
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
