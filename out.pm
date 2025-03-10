package out;

use strict;
use warnings;

sub new {
    my $class = shift;

    return bless { opt => { @_ } }, $class;
}

sub make {
    my $self = shift;

    foreach my $p (@_) {
        if (ref($p) eq 'Str') {
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

sub save {
    my ($self, $fname) = @_;

    open(my $fh, '>', $fname) || return;
    print $fh $self->data();
    close $fh;

    return 1;
}

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
