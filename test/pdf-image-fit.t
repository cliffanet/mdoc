#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use File::Path qw(make_path);
use File::Spec;
use PDF::API2;
use Test::More;
use out::pdf;
use txt;

{
    package ImageFitPage;

    sub new { bless {}, shift; }

    # Запоминает размеры, переданные отрисовке PDF-изображения.
    sub object {
        my ($self, $img, $x, $y, $w, $h) = @_;
        $self->{draw} = [$x, $y, $w, $h];
    }
}

my $out = out::pdf->new(root => $Bin);
my $wide = { type => 'image', url => 'img/nature.png' };
my $small = { type => 'image', url => 'img/cats(1).png' };

my $para = DContent->new($wide);
$para->stage2size($out);
$para->stage3layout(150, 700);
my @image = ();
$para->dncall(sub { push @image, $_[0] if ref($_[0]) eq 'DImage' });
is(scalar(@image), 1, 'paragraph contains one image');
is($image[0]->w(), 150, 'wide image fits paragraph width');
is($image[0]->h(), 100, 'paragraph image keeps aspect ratio');

my $mixed = DContent->new(txt->new('Before'), $wide);
$mixed->stage2size($out);
$mixed->stage3layout(150, 700);
is(scalar(@{ $mixed->{chld} }), 2, 'image moves to next line after text');

my $page = ImageFitPage->new();
$image[0]->stage4draw(10, 20, undef, $page);
is_deeply($page->{draw}, [10, 20, 150, 100], 'PDF draw uses fitted dimensions');

$image[0]->fitwidth(300);
is($image[0]->w(), 300, 'repeated fit uses original image width');
is($image[0]->h(), 200, 'repeated fit uses original image height');

my $tiny = DContent->new($small);
$tiny->stage2size($out);
$tiny->stage3layout(300, 700);
@image = ();
$tiny->dncall(sub { push @image, $_[0] if ref($_[0]) eq 'DImage' });
is($image[0]->w(), 120, 'small image is not enlarged');
is($image[0]->h(), 120, 'small image keeps original height');

my $quote = DQuote->new();
$quote->add(DContent->new($wide));
$quote->stage2size($out);
$quote->stage3layout(180, 700);
@image = ();
$quote->dncall(sub { push @image, $_[0] if ref($_[0]) eq 'DImage' });
is($image[0]->w(), 168, 'quote padding reduces available image width');
is($image[0]->h(), 112, 'quote image keeps aspect ratio');

my $table = DTable->new(1, [1, 1, 1], ['l', 'l', 'l']);
$table->addrow([$wide], [txt->new('Other')], [txt->new('Other')]);
$table->stage2size($out);
$table->stage3layout(300, 700);
@image = ();
$table->dncall(sub { push @image, $_[0] if ref($_[0]) eq 'DImage' });
is($image[0]->w(), 90, 'table cell padding reduces available image width');
is($image[0]->h(), 60, 'table image keeps aspect ratio');

my $missing = DImage->new('img/does-not-exist.png', undef, 'Нет файла');
$missing->stage2size($out);
my ($altw, $alth) = ($missing->w(), $missing->h());
$missing->fitwidth(10);
is($missing->w(), $altw, 'missing image keeps fallback width');
is($missing->h(), $alth, 'missing image keeps fallback height');

my $result = File::Spec->catdir($Bin, 'result');
make_path($result);
my $src = File::Spec->catfile($Bin, 'image-fit.md');
my $pdf = File::Spec->catfile($result, 'image-fit.pdf');
my $md = File::Spec->catfile($Bin, '..', 'md');
is(system($^X, $md, $src, $pdf), 0, 'image-fit document converts to PDF');
my $opened = eval { PDF::API2->open($pdf) };
ok($opened, 'generated PDF opens again');
ok($opened && $opened->pages() > 0, 'generated PDF has pages');

done_testing();
