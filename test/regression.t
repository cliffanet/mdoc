#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use FindBin qw($Bin);
use Test::More;

my $root = abs_path(File::Spec->catdir($Bin, '..'));
my $test = File::Spec->catdir($root, 'test');
my $exp = File::Spec->catdir($test, 'expected');
my $out = File::Spec->catdir($test, 'result', 'regression');
my $md = File::Spec->catfile($root, 'md');
my $update = $ENV{MDOC_UPDATE_EXPECTED};

make_path($out);
make_path($exp) if $update;

# HTML-файлы в result/regression используют ../img; ссылка ведёт к
# единственному набору тестовых изображений и не перезаписывает чужой путь.
my $img = File::Spec->catfile($test, 'result', 'img');
symlink('../img', $img) || die "Can't link '$img': $!" if !-e $img && !-l $img;
abs_path($img) eq abs_path(File::Spec->catdir($test, 'img')) ||
    die "Unexpected image path '$img'";

opendir(my $dh, $test) || die "Can't read '$test': $!";
my @src = sort grep {
    /\.md\z/ && -f File::Spec->catfile($test, $_)
} readdir($dh);
closedir($dh);

ok(@src, 'test documents found');

my %src = map {
    (my $name = $_) =~ s/\.md\z//;
    $name => 1;
} @src;
my @orphan = ();
if (-d $exp) {
    opendir(my $edh, $exp) || die "Can't read '$exp': $!";
    foreach my $file (sort readdir($edh)) {
        next if $file !~ /\.html\z/;
        (my $name = $file) =~ s/\.html\z//;
        push @orphan, $file if !$src{$name};
    }
    closedir($edh);
}
is_deeply(\@orphan, [], 'expected results have source documents');

foreach my $file (@src) {
    (my $name = $file) =~ s/\.md\z//;

    subtest $name => sub {
        my $src = File::Spec->catfile($test, $file);
        my $dst = File::Spec->catfile($out, $name.'.html');
        my $expected = File::Spec->catfile($exp, $name.'.html');

        unlink($dst) if -e $dst;
        my $status = system($^X, $md, $src, $dst);
        is($status, 0, 'conversion completed successfully');
        return if $status != 0;

        ok(-f $dst, 'result file created');
        return if !-f $dst;

        if ($update) {
            _write($expected, _read($dst));
            pass('expected result updated');
        }
        else {
            ok(-f $expected, 'expected result exists');
            return if !-f $expected;
            my $same = _read($dst) eq _read($expected);
            ok($same, 'result matches expected HTML');
            diag("compare '$dst' with '$expected'") if !$same;
        }
    };
}

done_testing();

# Читает файл целиком в бинарном режиме, чтобы сравнение учитывало каждый байт.
sub _read {
    my $file = shift;

    open(my $fh, '<:raw', $file) || die "Can't read '$file': $!";
    local $/ = undef;
    my $data = <$fh>;
    close($fh);

    return $data;
}

# Перезаписывает эталон фактическим результатом только в режиме обновления.
sub _write {
    my ($file, $data) = @_;

    open(my $fh, '>:raw', $file) || die "Can't write '$file': $!";
    print $fh $data;
    close($fh) || die "Can't close '$file': $!";
}
