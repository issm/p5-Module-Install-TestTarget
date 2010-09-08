package Module::Install::TestAssemble;

use 5.006_002;
use strict;
use warnings;
use vars qw($VERSION $TEST_DYNAMIC $TEST_TARGET);
$VERSION = '0.01';

use base qw(Module::Install::Base);
use ExtUtils::MM_Any;
use Config;


$TEST_DYNAMIC = {
    env                => '',
    includes           => '',
    modules            => '',
    before_run_codes   => '',
    after_run_codes    => '',
    before_run_scripts => '',
    after_run_scripts  => '',
};

sub test_assemble {
    my ($self, %args) = @_;
    my $target = $args{target} || 'test'; # for `make test`
    my $alias  = $args{alias}  || '';

    for my $key (qw/includes modules before_run_scripts after_run_scripts before_run_codes after_run_codes tests/) {
        $args{$key} ||= [];
        $args{$key} = [$args{$key}] unless ref $args{$key} eq 'ARRAY';
    }
    $args{env} ||= {};

    my %test;
    $test{includes} = @{$args{includes}} ? join '', map { qq|"-I$_" | } @{$args{includes}} : '';
    $test{modules}  = @{$args{modules}}  ? join '', map { qq|"-M$_" | } @{$args{modules}}  : '';
    $test{tests}    = @{$args{tests}}    ? join '', map { qq|"$_" |   } @{$args{tests}}    : '$(TEST_FILES)';
    for my $key (qw/before_run_scripts after_run_scripts/) {
        $test{$key} = @{$args{$key}} ? join '', map { qq|do '$_'; | } @{$args{$key}} : '';
    }
    for my $key (qw/before_run_codes after_run_codes/) {
        my $codes = join '', map { _build_funcall($_) } @{$args{$key}};
        $test{$key} = _quote($codes);
    }
    $test{env} = %{$args{env}} ? _quote(join '', map {
        my $key = _env_quote($_);
        my $val = _env_quote($args{env}->{$_});
        sprintf "\$ENV{q{%s}} = q{%s}; ", $key, $val
    } keys %{$args{env}}) : '';

    if ($target eq 'test_dynamic') {
        $TEST_DYNAMIC = \%test;
    }
    else {
        my $test = _assemble(%test, perl => '$(FULLPERLRUN)');

        $alias = $alias ? qq{\n$alias :: $target\n\n} : qq{\n};
        $self->postamble(
              $alias
            . qq{$target :: pure_all\n}
            . qq{\t} . $test
        );
    }
}

my $bd;
sub _build_funcall {
    my($code) = @_;
    if(ref $code eq 'CODE') {
        $bd ||= do { require B::Deparse; B::Deparse->new() };
        $code = $bd->coderef2text($code);
    }
    return qq|sub { $code }->(); |;
}

sub _quote {
    my $code = shift;
    $code =~ s/\$/\\\$\$/g;
    $code =~ s/"/\\"/g;
    $code =~ s/\n/ /g;
    if ($^O eq 'MSWin32' and $Config{make} eq 'dmake') {
        $code =~ s/\\\$\$/\$\$/g;
        $code =~ s/{/{{/g;
        $code =~ s/}/}}/g;
    }
    return $code;
}

sub _env_quote {
    my $val = shift;
    $val =~ s/}/\\}/g;
    return $val;
}

sub _assemble {
    my %args = @_;

    return
          qq{\t$args{perl} "-MExtUtils::Command::MM" }
        . $args{includes}
        . $args{modules}
        . qq{"-e" "}
        . $args{env}
        . $args{before_run_scripts}
        . $args{before_run_codes}
        . qq{test_harness(\$(TEST_VERBOSE), '\$(INST_LIB)', '\$(INST_ARCHLIB)'); }
        . $args{after_run_scripts}
        . $args{after_run_codes}
        . qq{" $args{tests}\n}
    ;
}

# for `make test`

my $orig_tvh = ExtUtils::MM->can('test_via_harness');
sub _test_via_harness {
    my($self, $perl, $tests) = @_;

    if(join '', values %{$TEST_DYNAMIC}) {
        $TEST_DYNAMIC->{perl} = $perl;
        $TEST_DYNAMIC->{tests} ||= $tests;
        return _assemble(%$TEST_DYNAMIC);
    }

    goto &{$orig_tvh}; # fallback to the default code
}

CHECK {
    no warnings 'redefine';
    *ExtUtils::MM::test_via_harness = \&_test_via_harness;
}

1;
__END__

=head1 NAME

Module::Install::TestAssemble - make test maker

=head1 SYNOPSIS

  # in Makefile.PL
  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      includes           => ["$ENV{HOME}/perl5/lib"],
      modules            => [qw/Foo Bar/],
      before_run_scripts => [qw/before.pl/],
      after_run_scripts  => [qw/after.pl/],
      before_run_codes   => ['print "start -> ", scalar localtime, "\n"'],
      after_run_codes    => ['print "end   -> ", scalar localtime, "\n"'],
      tests              => ['t/baz/*t'],
      target             => 'foo',     # create make foo target (default test)
      alias              => 'testall', # make testall is run the make foo
  );
  
  # maybe make test is
  make test_foo
  perl "-MExtUtils::Command::MM" "-I/home/xaicron/perl5/lib" "-MFoo" "-MBar" "-e" "do 'before.pl'; sub { print \"start -> \", scalar localtime, \"\n\" }->(); test_harness(0, 'inc'); do 'after.pl'; sub { print \"end -> \", scalar localtime, \"\n\" }->();" t/baz/*t

=head1 DESCRIPTION

Module::Install::TestAssemble is helps make a variety of processing of during the make test.

=head1 FUNCTIONS

=over

=item assemble_test(%args)

=back

=head2 %args

=over 3

=item tests

Setting running tests.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      tests  => ['t/foo.t', 't/bar.t'],
  );
  
  # maybe make test_pp is
  perl -MExtUtils::Command::MM -e "do 'tool/force-pp.pl'; test_harness(0, 'inc')" t/foo.t t/bar.t

=item includes

Setting include paths.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      include => ['/path/to/inc'],
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM -I/path/to/inc -e "test_harness(0, 'inc')" t/*t

=item modules

Setting preload modules.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      modules => ['Foo', 'Bar::Baz'],
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM -MFoo -MBar::Baz -e "test_harness(0, 'inc')" t/*t

=item before_run_script

Setting scripts to run before running the test.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      before_run_script => ['tool/before_run_script.pl'],
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM -e "do 'tool/before_run_script.pl; test_harness(0, 'inc')" t/*t

=item after_run_script

Setting scripts to run after running the test.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      after_run_script => ['tool/after_run_script.pl'],
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM -e "test_harness(0, 'inc'); do 'tool/before_run_script.pl;" t/*t

=item before_run_codes

Setting perl codes to run before running the test.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      before_run__codes => ['print scalar localtime , "\n"', sub { system qw/cat README/ }],
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM "sub { print scalar localtme, "\n" }->(); sub { system 'cat', 'README' }->(); test_harness(0, 'inc')" t/*t

The perl codes runs before_run_scripts runs later.

=item after_run_codes

Setting perl codes to run after running the test.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      after_run__codes => ['print scalar localtime , "\n"', sub { system qw/cat README/ }],
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM "test_harness(0, 'inc'); sub { print scalar localtme, "\n" }->(); sub { system 'cat', 'README' }->();" t/*t

The perl codes runs after_run_scripts runs later.

=item target

Create a new make test_*.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      before_run_script => 'tool/force-pp.pl',
      target            => 'test_pp',
  );
  
  # maybe make test_pp is
  perl -MExtUtils::Command::MM -e "do 'tool/force-pp.pl'; test_harness(0, 'inc')" t/*t

=item alias

Setting alias of target.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      before_run_script => 'tool/force-pp.pl',
      target            => 'test_pp',
      alias             => 'testall',
  );
  
  # maybe make testall is
  perl -MExtUtils::Command::MM -e "do 'tool/force-pp.pl'; test_harness(0, 'inc')" t/*t

=item env

Setting $ENV option.

  use inc::Module::Install;
  tests 't/*t';
  assemble_test(
      env => {
          FOO => 'bar',
      },
  );
  
  # maybe make test is
  perl -MExtUtils::Command::MM -e "\$ENV{q{FOO}} = q{bar}; test_harness(0, 'inc')" t/*t

=back

=head1 AUTHOR

Yuji Shimada E<lt>xaicron {at} cpan.orgE<gt>

=head1 SEE ALSO

L<Module::Install>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut