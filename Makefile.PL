#!/usr/bin/perl
use ExtUtils::MakeMaker;
use strict;

WriteMakefile (
    NAME            => 'PIPL',
    VERSION         => '0.0020070614',
    EXE_FILES       => [
        'pi.sh',
        'makeppd',
    ],
    dist            => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    PMLIBDIRS       => [ 'lib' ],
    PREREQ_PM       => {
        'ExtUtils::MM'  => 0,
        'File::Spec'    => 0,
        'XML::Parser'   => 0,
        'YAML'          => 0,
    },
    AUTHOR          => 'Piotr Roszatycki <dexter@debian.org>',
    ABSTRACT        => 'Package Installer for Perl',
);


package MY;

sub metafile {
    my $self = shift;
    my $inject = << "END";
name: $self->{DISTNAME}
abstract: $self->{ABSTRACT}
version: $self->{VERSION}
author:
  - $self->{AUTHOR}
license: perl
distribution_type: module
requires:
  perl: 5.006
  ExtUtils::MM: 0
  File::Spec: 0
  XML::Parser: 0
  YAML: 0
urls:
  license: http://dev.perl.org/licenses/
meta-spec:
  version: 1.3
  url: http://module-build.sourceforge.net/META-spec-v1.3.html
generated_by: $self->{AUTHOR}
END

    $inject = join "\n\t",  map { '$(NOECHO) $(ECHO) \''.$_.'\' >> META_new.yml' }
                            split /(?:\012\015?|\015\012?)/, $inject;

    my $t = $self->SUPER::metafile_target(@_);
    my $echoCmd = '$(NOECHO) $(ECHO) \'--- #YAML:1.0\' > META_new.yml';
    my $mvCmd = q|-$(NOECHO) $(MV)|;
    my $pat = '(Generating META.yml\n\t).*' . quotemeta($mvCmd);
    $t =~ s/$pat/$1$echoCmd\n\t$inject\n\t$mvCmd/s;
    return $t;
}

1;
