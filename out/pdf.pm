package out::pdf;

use strict;
use warnings;

use base 'out';

use PDF::API2;

sub new {
    my $self = shift()->SUPER::new(@_);

    my $pdf = ($self->{pdf} = PDF::API2->new());

    if (my $s = $self->{opt}->{title}) {
        $pdf->title($s);
    }
    if (my $s = $self->{opt}->{author}) {
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

    $pdf->mediabox('A4');
    $self->{page} = $pdf->page();

    return $self;
}

sub data { return shift()->{pdf}->stringify(); }

1;
