#!/bin/bash

# Perl Package Installer - prototype shell implementation
#
# (c) 2006-2007 Piotr Roszatycki <dexter@debian.org>, Artistic
#
# $Id$

# Requires:
#   Shell:
#     grep -q -s
#     id -u
#     md5sum -c
#     sed -i
#     unzip -qq -d
#   Perl:
#     ExtUtils::MM
#     File::Spec
#     XML::Parser
#     YAML

PI="pi.sh"

command=$1
shift


compare_versions () {
    perl -l -- - "$@" << 'END'

sub compare_versions {
    my $a = shift || 0;
    my $b = shift || 0;

    $a =~ s/^\s+//;
    $a =~ s/\s+$//;
    $a =~ s/[_+]/./g;
    $a =~ s/([^0-9\.]+)/.$1./g;
    $a =~ s/\.\././g;
    @a = split /\./, $a;
    
    $b =~ s/^\s+//;
    $b =~ s/\s+$//;
    $b =~ s/[_+]/./g;
    $b =~ s/([^0-9\.]+)/.$1./g;
    $b =~ s/\.\././g;
    @b = split /\./, $b;

    shift @a while ($a[0] eq '');
    shift @b while ($b[0] eq '');
    
    for ($i = 0, $x = ($#a > $#b ? $#a : $#b); $i <= $x; $i++) {
        next if ($a[$i] eq $b[$i]);
        $ia = $a[$i];
        $ib = $b[$i];
        return $ia <=> $ib if ($ia =~ /^\d+$/ && $ib =~ /^\d+$/);
	return $ia cmp $ib;
    }
    return 0;
}

print compare_versions(@ARGV);
END
}


xml2yaml () {
    perl -- - "$@" << 'END'

use XML::Parser;

our $l = 0;
our @tag;
our $tag, $attr, $val, $data;
our $name;
our %package;

binmode STDIN, ':utf8';
binmode STDOUT, ':utf8';

## use YAML;
## $YAML::Indent = 2;
## $YAML::UseHeader = 0;
## $YAML::UseVersion = 0;


# YAML coder routines based on YAML module.

# Check whether or not a scalar should be emitted as an plain scalar.
sub is_valid_plain {
    return 0 unless length $_[0];
    # refer to YAML::Loader::parse_inline_simple()
    return 0 if $_[0] =~ /^[\s\{\[\~\`\'\"\!\@\#\>\|\%\&\?\*\^]/;
    return 0 if $_[0] =~ /[\{\[\]\},]/;
    return 0 if $_[0] =~ /[:\-\?]\s/;
    return 0 if $_[0] =~ /\s#/;
    return 0 if $_[0] =~ /\:(\s|$)/;
    return 0 if $_[0] =~ /[\s\|\>]$/;
    return 1;
}

# Escapes for unprintable characters
my @escapes = qw(\z   \x01 \x02 \x03 \x04 \x05 \x06 \a
                 \x08 \t   \n   \v   \f   \r   \x0e \x0f
                 \x10 \x11 \x12 \x13 \x14 \x15 \x16 \x17
                 \x18 \x19 \x1a \e   \x1c \x1d \x1e \x1f
                );

# Escape the unprintable characters
sub escape {
    my ($text) = @_;
    $text =~ s/\\/\\\\/g;
    $text =~ s/([\x00-\x1f])/$escapes[ord($1)]/ge;
    return $text;
}

# Emit escape if is necessary
sub emit_string {
    my ($text) = @_;
    return $text if is_valid_plain $text;
    (my $escaped = escape($text)) =~ s/"/\\"/g;
    return qq{"$escaped"};
}


my $p = new XML::Parser;
$p->setHandlers(
    Start => sub {
	shift;
	$tag = shift;
	push @tag, $tag;
	$data = "";
	die if ($l == 0 && $tag !~ /^REPOSITORYSUMMARY$/i);
	if ($l == 1) {
	    die if ($tag !~ /^SOFTPKG$/i);
	    ($NAME, $VERSION) = undef;
	    while ($attr = shift) {
		$val = shift;
		if ($attr =~ /^NAME$/i) {
		    $NAME = $val;
		}
		elsif ($attr =~ /^VERSION$/i) {
		    $VERSION = $val;
		}
	    }
	    $name = $NAME;
	    %package = ();
	    $package{version} = $VERSION if defined $VERSION;
	}
	elsif ($l == 2 && $tag =~ /^PROVIDE$/i) {
	    ($NAME, $VERSION) = undef;
	    while ($attr = shift) {
		$val = shift;
		if ($attr =~ /^NAME$/i) {
		    $NAME = $val;
		}
		elsif ($attr =~ /^VERSION$/i) {
		    $VERSION = $val;
		}
	    }
	    $package{provide}{$NAME} = $VERSION;
	}
	elsif ($l == 2 && $tag =~ /^REQUIRE$/i) {
	    ($NAME, $VERSION) = undef;
	    while ($attr = shift) {
		$val = shift;
		if ($attr =~ /^NAME$/i) {
		    $NAME = $val;
		}
		elsif ($attr =~ /^VERSION$/i) {
		    $VERSION = $val;
		}
	    }
	    $package{require}{$NAME} = $VERSION;
	}
	elsif ($l == 3 && $tag[2] =~ /^IMPLEMENTATION$/i) {
	    if ($tag =~ /^ARCHITECTURE$/i) {
		$NAME = undef;
		while ($attr = shift) {
		    $val = shift;
		    if ($attr =~ /^NAME$/i) {
			$NAME = $val;
		    }
		}
		$package{architecture} = $NAME if defined $NAME;
	    }
	    elsif ($tag =~ /^CODEBASE$/i) {
		$HREF = undef;
		while ($attr = shift) {
		    $val = shift;
		    if ($attr =~ /^HREF$/i) {
			$HREF = $val;
		    }
		}
		$package{codebase} = $HREF if defined $HREF;
	    }
	}
	$l++;
    },
    End => sub {
	shift;
	if ($l == 2) {
	    printf "%s:\n", $name;
	    printf "  abstract: %s\n", emit_string($package{abstract}) if defined $package{abstract};
	    printf "  architecture: %s\n", emit_string($package{architecture}) if defined $package{architecture};
	    printf "  author: %s\n", emit_string($package{author}) if defined $package{author};
	    printf "  codebase: %s\n", emit_string($package{codebase}) if defined $package{codebase};
	    printf "  version: %s\n", emit_string($package{version}) if defined $package{version};
	    if (defined $package{require}) {
		printf "  require:\n";
		foreach (sort keys %{$package{require}}) {
		    printf "    %s: %s\n", emit_string($_), emit_string($package{require}{$_});
		}
	    }
	    if (defined $package{provide}) {
		printf "  provide:\n";
		foreach (sort keys %{$package{provide}}) {
		    printf "    %s: %s\n", emit_string($_), emit_string($package{provide}{$_});
		}
	    }
	    ## print Dump { $name => \%package };
	}
	elsif ($l == 3) {
	    if ($tag =~ /^ABSTRACT$/i) {
		$package{abstract} = $data if $data;
	    }
	    elsif ($tag =~ /^AUTHOR$/i) {
		$package{author} = $data if $data;
	    }
	}
	($tag, $attr, $val) = undef;
	pop @tag;
	$l--;
    },
    Char => sub {
	shift;
	$data .= shift;
    },
);

$p->parsefile($ARGV[0]);

END
}


yaml2ppd () {
    perl -- - "$@" << 'END'

use YAML;

binmode STDOUT, ':utf8';

$c = YAML::LoadFile($ARGV[0]);

die "bad yml file" if ref $c ne 'HASH' || scalar keys %{$c} != 1;

foreach (keys %{$c}) {
    die "bad yml file" if not defined $c->{$_}->{version};
    print  '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
    printf '<SOFTPKG NAME="%s" VERSION="%s">' . "\n", $_, $c->{$_}->{version};
    printf '  <TITLE>%s</TITLE>' . "\n", $_;
    printf '  <ABSTRACT>%s</ABSTRACT>' . "\n", $c->{$_}->{abstract} if defined $c->{$_}->{abstract};
    printf '  <AUTHOR>%s</AUTHOR>' . "\n", $c->{$_}->{author} if defined $c->{$_}->{author};
    print  '  <IMPLEMENTATION>' . "\n";
    printf '    <ARCHITECTURE NAME="%s" />' . "\n", $c->{$_}->{architecture} if defined $c->{$_}->{architecture};
    printf '    <CODEBASE HREF="%s" />' . "\n", $c->{$_}->{codebase} if defined $c->{$_}->{codebase};
    print  '  </IMPLEMENTATION>' . "\n";
    print  '</SOFTPKG>' . "\n";
}

END
}


# Load Perl configuration
eval `perl -V:.*`
#eval `perl -MConfig -e 'foreach (keys %Config) { printf "%s=\047%s\047\n", $_, $Config{$_}; }'`

# Find PI's main directory
if ! [ -n "$PERL_PI_DIR" ]; then
    for d in "$HOME/.pi.pl" "/etc/pi.pl"; do
        if [ -d "$d" ]; then
            PERL_PI_DIR="$d"
            break
        fi
    done
    if ! [ -n "$PERL_PI_DIR" ]; then
        if [ "`id -u`" = 0 ]; then
            PERL_PI_DIR="/etc/pi.pl"
        else
            for d in "$HOME/.pi.pl"; do
                if [ -w `dirname "$d"` ]; then
                    PERL_PI_DIR="$d"
                    break
                fi
            done
        fi
    fi
fi

# Create configuration directory if missing
if ! [ -d "$PERL_PI_DIR" ]; then
    echo "$PI: Missing main configuration."
    printf "Do you want to create %s directory? [y/n] " $PERL_PI_DIR
    read r
    case "$r" in
        [Yy])
            printf "Creating main configuration directory... "
            mkdir -p "$PERL_PI_DIR" || exit $?
            echo "done"
            ;;
        *)
            echo "Aborted."
            exit 1
    esac
fi

# Create configuration file if missing
if ! [ -f "$PERL_PI_DIR/config.yml" ]; then
    printf "Creating main configuration file... "
    (
        cat << END
# This is the configuration file for PI.
# Please note, that this file can be modified by calling \`pi' command.

END
        if [ "`id -u`" = 0 ]; then
            cat << END
default_area: site
END
        else
            cat << END
default_area: home_perl
END
        fi
        # TODO: autodetect architecture for proper repository
        cat << END
area:
  perl: $installarchlib
  vendor: $installvendorarch
  site: $installsitearch
  usr_local: /usr/local/lib/site_perl
  usr_local_perl: /usr/local/perl/lib
  home: $HOME/site_perl
  home_perl: $HOME/perl/lib
repo:
  ActiveState:
    name: ActiveState Package Repository
    url: http://ppm.activestate.com/PPMPackages/5.8-linux/package.xml.gz
    enabled: yes
END
    ) > "$PERL_PI_DIR/config.yml" || exit 1
    echo "done"
fi

if [ "$command" = "area" ]; then
    subcommand=$1
    shift

    if ! [ -n "$subcommand" ] || [ "$subcommand" = "list" ]; then
        echo "name,pkgs,libs"
        default_area=`perl -MYAML -le '
            $c=YAML::LoadFile($ARGV[0]);
            print $_, $c->{default_area};' "$PERL_PI_DIR/config.yml"`
        perl -MYAML -le '
            $,="\t";
            $c=YAML::LoadFile($ARGV[0]);
            foreach (sort keys %{$c->{area}}) {
                print $_, $c->{area}->{$_};
            }' "$PERL_PI_DIR/config.yml" | while read area blib_arch; do
                if [ "$area" = "$default_area" ]; then
                    area_default="*"
                else
                    area_default=""
                fi
                if ! [ -w "$blib_arch/auto/.pi.pl-area/_area.yml" ] || ! [ -f "$blib_arch/auto/.pi.pl-area/_area.yml" ]; then
                    printf "(%s%s)," "$area" "$area_default"
                else
                    printf "%s%s," "$area" "$area_default"
                fi
                if [ -f "$blib_arch/auto/.pi.pl-area/_area.yml" ]; then
                    printf "%d," `find "$blib_arch/auto/.pi.pl-area" -name '*.ppd' | wc -l`
                else
                    printf "n/a,"
                fi
                printf "%s\n" "$blib_arch"
            done
        exit 0
    fi

    # ppm area add <area> <blib_arch>
    if [ "$subcommand" = "add" ]; then
        area=$1
        shift
        blib_arch=$1
        shift

        if [ -z "$area" ] || [ -z "$blib_arch" ]; then
            echo "Usage: pi.sh area add <area> <blib_arch>"
            exit 1
        fi

        sed -i "s/^repo:/  $area: $blib_arch\n&/" "$PERL_PI_DIR/config.yml" || exit 1
        echo "ppm area $area added: $blib_arch"
        exit 0
    fi

    # ppm area delete <area>
    if [ "$subcommand" = "delete" ]; then
        area=$1
        shift

        if [ -z "$area" ]; then
            echo "Usage: pi.sh area delete <area>"
            exit 1
        fi

        if ! grep -qs "^  $area: " "$PERL_PI_DIR/config.yml"; then
            echo "ppm area delete: The area $area does not exist"
            exit 1
        fi

        grep -v "^  $area: " "$PERL_PI_DIR/config.yml" > "$PERL_PI_DIR/config.yml.new" || exit 1
        if ! [ -s "$PERL_PI_DIR/config.yml.new" ]; then
            echo "ppm area delete: The new configuration file is empty"
            rm -f "$PERL_PI_DIR/config.yml.new"
            exit 1
        fi
        mv -f "$PERL_PI_DIR/config.yml.new" "$PERL_PI_DIR/config.yml"
        echo "ppm area $area deleted"
        exit 0
    fi

    # ppm area init <area>
    if [ "$subcommand" = "init" ]; then
        area=$1
        shift

        if ! [ -n "$area" ]; then
            echo "Usage: pi.sh area init <area>"
            exit 1
        fi

        blib_arch=`perl -MYAML -le '
            $c=YAML::LoadFile($ARGV[0]);
            print $c->{area}->{$ARGV[1]};' \
            "$PERL_PI_DIR/config.yml" "$area"`

        # Already exists
        if [ -f "$blib_arch/auto/.pi.pl-area/_area.yml" ]; then
            exit 0
        fi

        # Create _area.yml
        if ! [ -d "$blib_arch/auto/.pi.pl-area" ]; then
            if ! [ -d "$blib_arch/auto/" ]; then
                echo "The area directory $blib_arch/auto/ does not exist"
                exit 1
            fi
            if ! [ -w "$blib_arch/auto/" ]; then
                echo "The area directory $blib_arch/auto/ is not writable"
                exit 1
            fi
            mkdir -p "$blib_arch/auto/.pi.pl-area" || exit 1
        fi
        # Guess blib_* paths based on area name
        case "$area" in
            perl)
                prefix=$prefix
                blib_bin=$installbin
                blib_html=$installhtmldir
                blib_lib=$installprivlib
                blib_man1=$installman1dir
                blib_man3=$installman3dir
                blib_script=$installscript
                ;;
            vendor)
                prefix=$vendorprefix
                blib_bin=$installvendorbin
                blib_html=$installhtmldir
                blib_lib=$installvendorlib
                blib_man1=$installvendorman1dir
                blib_man3=$installvendorman3dir
                blib_script=$installvendorscript
                ;;
            site)
                prefix=$siteprefix
                blib_bin=$installsitebin
                blib_html=$installhtmldir
                blib_lib=$installsitelib
                blib_man1=$installsiteman1dir
                blib_man3=$installsiteman3dir
                blib_script=$installsitescript
                ;;
            usr_local)
                prefix=/usr/local
                blib_bin=/usr/local/bin
                blib_html=$installhtmldir
                blib_lib=/usr/local/lib/site_perl
                blib_man1=/usr/local/man/man1
                blib_man3=/usr/local/man/man3
                blib_script=/usr/local/bin
                ;;
            usr_local_perl)
                prefix=/usr/local/perl
                blib_bin=/usr/local/perl/bin
                blib_html=$installhtmldir
                blib_lib=/usr/local/perl/lib
                blib_man1=/usr/local/perl/man/man1
                blib_man3=/usr/local/perl/man/man3
                blib_script=/usr/local/perl/bin
                ;;
            home)
                prefix=$HOME
                blib_bin=$HOME/bin
                blib_html=$installhtmldir
                blib_lib=$HOME/site_perl
                blib_man1=$HOME/man/man1
                blib_man3=$HOME/man/man3
                blib_script=$HOME/bin
                ;;
            home_perl)
                prefix=$HOME/perl
                blib_bin=$HOME/perl/bin
                blib_html=$installhtmldir
                blib_lib=$HOME/perl/lib
                blib_man1=$HOME/perl/man/man1
                blib_man3=$HOME/perl/man/man3
                blib_script=$HOME/perl/bin
                ;;
            *)
                prefix=$(basename "$blib_arch")
                blib_bin=$prefix/bin
                blib_html=$installhtmldir
                blib_lib=$blib_arch
                blib_man1=$prefix/man/man1
                blib_man3=$prefix/man/man3
                blib_script=$prefix/bin
        esac
        if [ -z "$blib_html" ] || ! [ -w "$blib_html" ]; then
            blib_html=$prefix/html
        fi
        cat << END > "$blib_arch/auto/.pi.pl-area/_area.yml"
prefix: $prefix
blib_arch: $blib_arch
blib_bin: $blib_bin
blib_html: $blib_html
blib_lib: $blib_lib
blib_man1: $blib_man1
blib_man3: $blib_man3
blib_script: $blib_script
END
        exit 0
    fi

    # ppm area sync [<area>]
    if [ "$subcommand" = "sync" ] || [ "$subcommand" = "init" ]; then
        if [ -z "$area" ]; then
            area=$1
            shift
        fi
        area_opt=$area

        perl -MYAML -le '
            $,="\t";
            $c=YAML::LoadFile($ARGV[0]);
            foreach (sort keys %{$c->{area}}) {
                print $_, $c->{area}->{$_};
            }' "$PERL_PI_DIR/config.yml" | while read area blib_arch; do
                if ! [ -d "$blib_arch/auto/.pi.pl-area" ]; then
                    if [ "$area" = "$area_opt" ]; then
                        echo "ppm area failed: Uninitialized area $area"
                        exit 1
                    fi
                else
                    if ! [ -w "$blib_arch/auto/.pi.pl-area" ]; then
                        if [ "$area" = "$area_opt" ]; then
                            echo "ppm area failed: Not writable area $area"
                            exit 1
                        fi
                    else
                        printf "Syncing %s PPM database with .packlists..." "$area"
                        # TODO: removing orphaned packages
                        find "$blib_arch/auto" -name .packlist | while read packlist; do
                            fullext=${packlist#$blib_arch/auto/}
                            fullext=${fullext%/.packlist}
                            distname=$(echo $fullext | tr '/' '-')
                            name=$(echo $fullext | sed 's,/,::,g')
                            # Update if .packlist is newer
                            if [ "$packlist" -nt "$blib_arch/auto/.pi.pl-area/$distname.ppd" ] || \
                               [ "$packlist" -nt "$blib_arch/auto/.pi.pl-area/$distname.ls" ] || \
                               [ "$packlist" -nt "$blib_arch/auto/.pi.pl-area/$distname.md5sum" ] || \
                               [ "$packlist" -nt "$blib_arch/auto/.pi.pl-area/$distname.yml" ]
                            then
                                # packlist is newer: regenerate ppd and files list
                                # TODO: regenerate PPD only if VERSION does not match
                                # TODO: leave TITLE ABSTRACT AUTHOR untouched
                                modfile=$fullext.pm
                                version=`perl -MFile::Spec -MExtUtils::MM -le '
                                    my $modfile = $ARGV[0];
                                    foreach my $dir (@INC) {
                                        my $p = File::Spec->catfile($dir, $modfile);
                                        if (-r $p) {
                                            $version = MM->parse_version($p);
                                            last;
                                        }
                                    }
                                    print $version;' "$modfile"`
                                #version_ppd=`perl -le '
                                #    print join ",", (split (/\./, $ARGV[0]), (0)x4)[0..3];' $version`
                                os=`perl -le 'print $^O'`
                                arch=`perl -MConfig -le 'printf "%s-%d-%d", $Config{archname}, $Config{api_revision}, $Config{api_version}'`
                                (
                                    cat << END
<?xml version="1.0" encoding="UTF-8"?>
<SOFTPKG NAME="$distname" VERSION="$version">
    <TITLE>$distname</TITLE>
    <ABSTRACT>$distname PPM package</ABSTRACT>
    <AUTHOR></AUTHOR>
    <IMPLEMENTATION>
        <OS NAME="$os" />
        <ARCHITECTURE NAME="$arch" />
        <CODEBASE HREF="" />
    </IMPLEMENTATION>
    <PROVIDE NAME="$name" VERSION="$version" />
</SOFTPKG>
END
                                ) > "$blib_arch/auto/.pi.pl-area/$distname.ppd"
                                (cat $packlist; echo "$packlist") | tr '\012' '\000' | LC_ALL=C xargs -0r ls -ldn --time-style=long-iso 2>/dev/null \
                                  > "$blib_arch/auto/.pi.pl-area/$distname.ls"
                                (cat $packlist; echo "$packlist") | tr '\012' '\000' | LC_ALL=C xargs -0r md5sum 2>/dev/null \
                                  > "$blib_arch/auto/.pi.pl-area/$distname.md5sum"
                                size=`(cat $packlist; echo "$packlist") | tr '\012' '\000' | LC_ALL=C du --files0-from=- -c 2>/dev/null | tail -n1 | sed 's/[[:space:]].*//'`
                                size=$((`printf "%d" $size` * 1024))
                                files=`wc -l < "$blib_arch/auto/.pi.pl-area/$distname.ls"`
                                (
                                    cat << END
version: $version
files: $files
size: $size
END
                                ) > "$blib_arch/auto/.pi.pl-area/$distname.yml"

                            fi
                        done
                        echo "done"
                    fi
                fi
            done
        exit 0
    fi

    # ppm area default <area>
    if [ "$subcommand" = "default" ]; then
        area=$1
        shift

        if [ -z "$area" ]; then
            echo "Usage: pi.sh area default <area>"
            exit 1
        fi

        if ! grep -qs "^  $area: " "$PERL_PI_DIR/config.yml"; then
            echo "ppm area default: The area $area does not exist"
            exit 1
        fi

        sed "s/^\(default_area: \).*$/\1$area/" "$PERL_PI_DIR/config.yml" > "$PERL_PI_DIR/config.yml.new" || exit 1
        if ! [ -s "$PERL_PI_DIR/config.yml.new" ]; then
            echo "ppm area delete: The new configuration file is empty"
            rm -f "$PERL_PI_DIR/config.yml.new"
            exit 1
        fi
        mv -f "$PERL_PI_DIR/config.yml.new" "$PERL_PI_DIR/config.yml"
        echo "ppm area $area is default"
        exit 0
    fi

    echo "Usage: pi.sh area list|default|add|delete|init|sync"
    exit 1
fi


if [ "$command" = "repo" ]; then
    subcommand=$1
    shift

    # initialize repo directory
    perl -MYAML -le '
        $,="\t";
        $c=YAML::LoadFile($ARGV[0]);
        foreach (sort keys %{$c->{repo}}) {
            print $_, $c->{repo}->{$_}->{enabled}, $c->{repo}->{$_}->{url}, $c->{repo}->{$_}->{name};
        }' "$PERL_PI_DIR/config.yml" | while read repo enabled url name; do
            if [ "$enabled" = "yes" ]; then
                repodir="$PERL_PI_DIR/repo/$repo"
                if ! [ -d "$repodir/cache" ]; then
                    if ! mkdir -p "$repodir/cache"; then
                        echo "ppm repo: can not initialize repository directory $repodir/cache"
                        exit 1
                    fi
                    touch "$repodir/packages.yml"
                fi
            fi
        done

    # ppm repo list
    if ! [ -n "$subcommand" ] || [ "$subcommand" = "list" ]; then
        echo "id,pkgs,name"
        perl -MYAML -le '
            $,="\t";
            $c=YAML::LoadFile($ARGV[0]);
            foreach (sort keys %{$c->{repo}}) {
                print $_, $c->{repo}->{$_}->{enabled}, $c->{repo}->{$_}->{url}, $c->{repo}->{$_}->{name};
            }' "$PERL_PI_DIR/config.yml" | while read repo enabled url name; do
                printf "%s," "$repo"
                if [ "$enabled" = "yes" ]; then
                    repodir="$PERL_PI_DIR/repo/$repo"
                    printf "%d," `grep '^[^ ].*:' "$repodir/packages.yml" | wc -l`
                else
                    printf "n/a,"
                fi
                printf "%s\n" "$name"
            done
	exit 0
    fi

    # ppm repo describe <repo>
    if [ "$subcommand" = "describe" ]; then
        repo=$1
        shift

        if [ -z "$repo" ]; then
            echo "Usage: pi.sh repo describe <repo>"
            exit 1
        fi

        if ! [ -d "$PERL_PI_DIR/repo/$repo" ]; then
            echo "ppm repo describe: The repository $repo does not exist"
            exit 1
        fi

        perl -MYAML -le '
            $c=YAML::LoadFile($ARGV[0]);
	    $r=$ARGV[1];
	    printf "Id: %s\n", $r;
	    printf "Name: %s\n", $c->{repo}->{$r}->{name};
	    printf "URL: %s\n", $c->{repo}->{$r}->{url};
	    printf "Enabled: %s\n", $c->{repo}->{$r}->{enabled};
	    ' "$PERL_PI_DIR/config.yml" "$repo"
        exit 0
    fi

    # ppm repo add <url> <id> <name>
    if [ "$subcommand" = "add" ]; then
        url=$1
        shift
	repo=$1
	shift
	name="$*"

        if [ -z "$name" ]; then
            echo "Usage: pi.sh repo add <url> <id> <name>"
            exit 1
        fi

        if [ -d "$PERL_PI_DIR/repo/$repo" ]; then
            echo "ppm repo add: The repository $repo already exists"
            exit 1
        fi

	cat << END >> "$PERL_PI_DIR/config.yml"
  $repo:
    name: $name
    url: $url
    enabled: yes
END
        echo "ppm repository $repo added: $url"
        exit 0
    fi

    # ppm repo delete <repo>
    if [ "$subcommand" = "delete" ]; then
        repo=$1
        shift

        if [ -z "$repo" ]; then
            echo "Usage: pi.sh repo delete <repo>"
            exit 1
        fi

        if ! [ -d "$PERL_PI_DIR/repo/$repo" ]; then
            echo "ppm repo delete: The repository $repo does not exist"
            exit 1
        fi

	rm -rf "$PERL_PI_DIR/repo/$repo"
        sed -i "/^  $repo:$/,/    enabled:/d" "$PERL_PI_DIR/config.yml" || exit 1
        echo "ppm repository $repo deleted"
        exit 0
    fi

    # ppm repo sync [<repo>]
    if [ "$subcommand" = "sync" ]; then
	repo_opt=$1
	shift
	
	if [ -n "$repo_opt" ]; then
	    if ! [ -d "$PERL_PI_DIR/repo/$repo_opt" ]; then
		echo "ppm repo sync: The repository $repo_opt does not exist"
		exit 1
	    fi
	    enabled=`perl -MYAML -le '
        	$c=YAML::LoadFile($ARGV[0]);
		$r=$ARGV[1];
		print $c->{repo}->{$r}->{enabled};
	    ' "$PERL_PI_DIR/config.yml" "$repo_opt"`
	    if [ "$enabled" != "yes" ]; then
		echo "ppm repo sync: The repository $repo_opt is disabled"
		exit 1
	    fi
	    repo_list="$repo_opt"
	else
	    repo_list=`perl -MYAML -le '
        	$c=YAML::LoadFile($ARGV[0]);
		foreach $r (sort keys %{$c->{repo}}) {
		    print $r if $c->{repo}->{$r}->{enabled} eq "yes";
		}
	    ' "$PERL_PI_DIR/config.yml"`
	fi
	
	if [ -z "$repo_list" ]; then
	    echo "ppm repo sync: There is no any enabled repository"
	    exit 1
	fi
	
	for repo in $repo_list; do
	    url=`perl -MYAML -le '
        	$c=YAML::LoadFile($ARGV[0]);
		$r=$ARGV[1];
		print $c->{repo}->{$r}->{url};
	    ' "$PERL_PI_DIR/config.yml" "$repo"`
	    
	    # download the index
	    cd "$PERL_PI_DIR/repo/$repo/cache" || exit 1
	    case "$url" in
		ftp://*|http://*)
		    wget -c "$url"
		    ;;
		*)
		    cp -p "$url" .
	    esac
	    file=`basename $url`
	    
	    # uncompress the downloaded index
	    case "$file" in
		*.gz)
		    file=${file%.gz}
		    gzip -c -d $file.gz > $file
		    ;;
		*.bz2)
		    file=${file%.bz2}
		    bzip2 -c -d $file.bz2 > $file
		    ;;
	    esac
	    
	    # generate the packages.yml index
	    if grep -qs '<REPOSITORYSUMMARY' "$file"; then
		# PPM repository index
		xml2yaml "$file" > "$PERL_PI_DIR/repo/$repo/packages.yml" || exit 1
	    fi
	done
	
	exit 0
    fi

    echo "Usage: pi.sh repo list|describe|add|delete|sync"
    exit 1

fi


if [ "$command" = "list" ]; then
    area_opt=$1
    shift

        perl -MYAML -le '
            $,="\t";
            $c=YAML::LoadFile($ARGV[0]);
            foreach (sort keys %{$c->{area}}) {
                print $_, $c->{area}->{$_};
            }' "$PERL_PI_DIR/config.yml" | while read area blib_arch; do
                if ! [ -d "$blib_arch/auto/.pi.pl-area" ]; then
                    if [ "$area" = "$area_opt" ]; then
                        echo "*** area $area is not initialized ***"
                        exit 1
                    fi
                else
                    echo "name,version,files,size,area"
                    find "$blib_arch/auto/.pi.pl-area" -name '*.ppd' | while read ppd; do
                        distname=$(basename "$ppd" .ppd)
                        if ! [ -f "$blib_arch/auto/.pi.pl-area/$distname.ls" ] || \
                           ! [ -f "$blib_arch/auto/.pi.pl-area/$distname.md5sum" ] || \
                           ! [ -f "$blib_arch/auto/.pi.pl-area/$distname.yml" ]
                        then
                            echo "*** missing metadata for package '$distname' ***"
                            continue
                        fi
                        version=`grep ^version: "$blib_arch/auto/.pi.pl-area/$distname.yml" | sed 's/.*: //'`
                        files=`grep ^files: "$blib_arch/auto/.pi.pl-area/$distname.yml" | sed 's/.*: //'`
                        size=`grep ^size: "$blib_arch/auto/.pi.pl-area/$distname.yml" | sed 's/.*: //'`
                        printf "%s,%s,%d,%d,%s\n" "$distname" "$version" "$files" "$size" "$area"
                    done
                fi
            done

    exit 0
fi


if [ "$command" = "files" ]; then
    pkg=$1
    shift

    if [ -z "$pkg" ]; then
        echo "Usage: ppm files <pkg>"
        exit 1
    fi

    n=0
    for blib_arch in `perl -MYAML -le '
            $,="\t";
            $c=YAML::LoadFile($ARGV[0]);
            foreach (sort keys %{$c->{area}}) {
                print $c->{area}->{$_};
            }' "$PERL_PI_DIR/config.yml"`
    do
        ppd="$blib_arch/auto/.pi.pl-area/$pkg.ppd"
        ls="$blib_arch/auto/.pi.pl-area/$pkg.ls"
        if [ -f "$ppd" ]; then
            if ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.ls" ] || \
               ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.md5sum" ] || \
               ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.yml" ]
            then
                echo "*** missing metadata for package '$pkg' ***"
                exit 1
            fi
            n=$(($n+1))
            awk '{ print $8 }' "$ls"
        fi
    done

    if [ $n = 0 ]; then
        echo "ppm files failed: Package '$pkg' is not installed"
        exit 1
    fi

    exit 0
fi


if [ "$command" = "verify" ]; then
    pkg_opt=$1
    shift

    if [ -n "$pkg_opt" ]; then
        pkg_name="$pkg_opt"
    else
        pkg_name="*"
    fi

    # TODO: check if package is installed
    # TODO: check $pkg.ls file
    for blib_arch in `perl -MYAML -le '
            $,="\t";
            $c=YAML::LoadFile($ARGV[0]);
            foreach (sort keys %{$c->{area}}) {
                print $c->{area}->{$_};
            }' "$PERL_PI_DIR/config.yml"`
    do
        if [ -d "$blib_arch/auto/.pi.pl-area" ]; then
            find "$blib_arch/auto/.pi.pl-area" -name "$pkg_name.ppd" | while read ppd; do
                pkg=$(basename "$ppd" .ppd)
                md5sum="$blib_arch/auto/.pi.pl-area/$pkg.md5sum"
                if [ -f "$ppd" ]; then
                    if ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.ls" ] || \
                       ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.md5sum" ] || \
                       ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.yml" ]
                    then
                        echo "*** missing metadata for package '$pkg' ***"
                        exit 1
                    fi
                    LC_ALL=C md5sum -c "$md5sum" 2>&1 | grep ': FAILED'
                fi
            done
        fi
    done

    exit 0
fi


if [ "$command" = "install" ]; then
    area_opt=
    if [ "$1" = "--area" ]; then
        shift
        area_opt=$1
        shift
    fi

    if [ -z "$1" ]; then
        echo "Usage: ppm install <pkg>|<file.ppd>|<file.zip>|<url>"
        exit 1
    fi

    while [ -n "$1" ]; do
        pkg=$1
        shift

        # Read the configuration
        default_area=`grep '^default_area: ' "$PERL_PI_DIR/config.yml" | sed 's/.*: //'`
        area=${area_opt:-$default_area}
        blib_arch=`grep "^  $area: " "$PERL_PI_DIR/config.yml" | sed 's/.*: //'`
        if ! [ -f "$blib_arch/auto/.pi.pl-area/_area.yml" ]; then
            echo "ppm install: area $area is uninitialized"
            exit 1
        fi
        if ! [ -w "$blib_arch/auto/.pi.pl-area/_area.yml" ]; then
            echo "ppm install: area $area is not writable"
            exit 1
        fi

        for i in prefix blib_arch blib_bin blib_html blib_lib blib_man1 blib_man3 blib_script; do
            v=`grep "^$i: " "$blib_arch/auto/.pi.pl-area/_area.yml" | sed 's/.*: //'`
            if [ -z "$v" ]; then
                echo "ppm install: area $area has wrong path \`$v' for $i"
                exit 1
            fi
            eval $i="$v"
        done

        # Create temporary directory
        tmp="${TMPDIR:-/tmp}/pi-$$-$(date +%s)"
        # Clean up after exit or signals
        trap "cd /; rm -rf \"$tmp\"; exit 0" HUP INT QUIT TERM EXIT
        mkdir -p "$tmp" || exit 1
        if ! [ -w "$tmp" ]; then
            echo "ppm install: can not create temporary directory $tmp"
            exit 1
        fi

	# Find URL if the package name was given
	case "$pkg" in
	    ftp://*|http://*|*.*)
		:;; # This is not a package name
	    *)
		# Find the package
                mkdir "$tmp/download"
                cd "$tmp/download"
		version=
    		for repo in `perl -MYAML -le '
        	    $c=YAML::LoadFile($ARGV[0]);
	            foreach (sort keys %{$c->{repo}}) {
        	        print $_ if $c->{repo}->{$_}->{enabled};
	            }' "$PERL_PI_DIR/config.yml"`
		do
		    sed -n "/^$pkg:/,/^  version:/p" "$PERL_PI_DIR/repo/$repo/packages.yml" \
			> "$tmp/package-new.yml"
		    version_new=`grep '^  version:' "$tmp/package-new.yml" | sed 's/.*: //'`
		    if ! [ -f "$tmp/package.yml" ] || [ `compare_versions "$version_new" "$version"` = 1 ]; then
			mv -f "$tmp/package-new.yml" "$tmp/package.yml"
			version=$version_new
		    fi
		done
		if [ -z "$version" ]; then
		    echo "ppm install: can not find $pkg package"
		fi
		url=`perl -MYAML -le '
        	    $c=YAML::LoadFile($ARGV[0]);
		    print $c->{repo}->{$ARGV[1]}->{url}' "$PERL_PI_DIR/config.yml" "$repo"`
		archive=`grep '^  codebase:' "$tmp/package.yml" | sed 's/.*: //'`
		pkg="$pkg.ppd"
		yaml2ppd "$tmp/package.yml" > "$pkg"
                mkdir -p "$(dirname $archive)"
                wget -O "$archive" "$(dirname $url)/$archive"
	esac

        # Download from URL
        case "$pkg" in
            ftp://*|http://*)
                # Download the ppd first
                url="$pkg"
                mkdir "$tmp/download"
                cd "$tmp/download"
                wget "$url"
                pkg=$(echo *)
                case "$pkg" in
                    *.[pP][pP][dD])
                    # Download also archive
                    ppd="$pkg"
                    archive=`grep '<CODEBASE.* HREF=' "$ppd" | sed 's/.*HREF="//; s/".*//'`
                    case "$archive" in
                        /*)
                            echo "ppm install: archive base have to be relative to PPD"
                            exit 1
                    esac
                    mkdir -p "$(dirname $archive)"
                    wget -O "$archive" "$(dirname $url)/$archive"
                    ;;
                esac
                ;;
        esac
        # Prepare the PPD and archive
        case "$pkg" in
            *.[pP][pP][dD])
                # Already done
                ppd="$pkg"
                ;;
            *.[zZ][iI][pP])
                # Unzip to the tmp
                unzip -qq "$pkg" -d "$tmp/pkg"
                cd "$tmp/pkg"
                ppd=`echo *.[pP][pP][dD]`
                ;;
        esac
        ppd="`pwd`/$ppd"

        if ! [ -s "$ppd" ]; then
            echo "ppm install: can not find PPD file $ppd for package $pkg"
            exit 1
        fi

        ppddir=`dirname $ppd`
        distname=`grep '<SOFTPKG.* NAME=' $ppd | sed 's/.*NAME="//; s/".*//'`
        fullext=`echo "$distname" | tr "-" "/"`
        version=`grep '<SOFTPKG.* VERSION=' $ppd | sed 's/.*VERSION="//; s/".*//'`
        archive=`grep '<CODEBASE.* HREF=' "$ppd" | sed 's/.*HREF="//; s/".*//'`

        if ! [ -s "$ppddir/$archive" ]; then
            echo "ppm install: can not find archive file $archive for package $pkg"
            exit 1
        fi

        # Unpack the archive
        mkdir -p "$tmp/archive" || exit 1
        echo "Unpacking the archive $archive for package $pkg"
        if ! tar -zx -C "$tmp/archive" -f "$ppddir/$archive"; then
            echo "ppm install: can not unpack the archive $archive for package $pkg"
            exit 1
        fi

        if ! [ -d "$tmp/archive/blib" ]; then
            echo "ppm install: the archive $archive for package $pkg does not contain blib directory"
            exit 1
        fi

        # Install new files
        # TODO: check if /auto/ dir exists
        cd "$tmp/archive"
        packlistdir="blib/arch/auto/$fullext"
        packlist="$blib_arch/${packlistdir#blib/arch/}/.packlist"
        fullext=${packlist#$blib_arch/auto/}
        fullext=${fullext%/.packlist}
        distname=$(echo $fullext | tr '/' '-')
        name=$(echo $fullext | sed 's,/,::,g')
        rollback=no
        upgrade=no
        : > "$tmp/newdirs.list" || exit 1
        : > "$tmp/newfiles.list" || exit 1
        : > "$tmp/oldfiles.list" || exit 1
        if [ -f "$blib_arch/auto/.pi.pl-area/$distname.ppd" ]; then
            upgrade=yes
            oldversion=`grep ^version "$blib_arch/auto/.pi.pl-area/$distname.yml" | sed 's/^.*: //'`
            echo "Replace the package $distname $oldversion"
        fi
        if [ -f "$packlist" ]; then
            cat "$packlist" >> "$tmp/oldfiles.list" || exit 1
        fi
        find blib -type f ! -name .exists | while read src; do
            case "$src" in
                blib/arch/*) dst="$blib_arch/${src#blib/arch/}";;
                blib/bin/*) dst="$blib_bin/${src#blib/bin/}";;
                blib/html/*) dst="$blib_html/${src#blib/html/}";;
                blib/lib/*) dst="$blib_lib/${src#blib/lib/}";;
                blib/man1/*) dst="$blib_man1/${src#blib/man1/}";;
                blib/man3/*) dst="$blib_man3/${src#blib/man3/}";;
                blib/script/*) dst="$blib_script/${src#blib/script/}";;
                *) dst=
            esac
            dstdir=`dirname "$dst"`
            if [ -d "$dstdir" ]; then
                if ! [ -w "$dstdir" ]; then
                    echo "ppm install: the directory $dstdir is not writable"
                    exit 100
                fi
            else
                echo "$dstdir" >> "$tmp/newdirs.list"
                # TODO: list created subdirs also
                if ! mkdir -p "$dstdir"; then
                    echo "ppm install: can not create $dstdir directory"
                    exit 100
                fi
            fi
            echo "$dst" >> "$tmp/newfiles.list"
            if ! cp -f "$src" "$dst.pi.pl-new"; then
                echo "ppm install: problem occured (cp)"
                exit 100
            fi
            if [ -f "$dst" ]; then
                if ! ln -f "$dst" "$dst.pi.pl-tmp"; then
                    echo "ppm install: problem occured (ln)"
                    exit 100
                fi
            fi
            if ! mv -f "$dst.pi.pl-new" "$dst"; then
                echo "ppm install: problem occured (mv)"
                exit 100
            fi
        done || rollback=yes

        # Rollback
        if [ "$rollback" = "yes" ]; then
            echo "Rollback after problem"
            cat "$tmp/newfiles.list" | while read dst; do
                if [ -f "$dst.pi.pl-tmp" ]; then
                    mv -f "$dst.pi.pl-tmp" "$dst"
                fi
                rm -f "$dst.pi.pl-new"
            done
            cat "$tmp/newdirs.list" | while read dst; do
                if [ -d "$dst" ]; then
                    rmdir -p "$dst" >/dev/null 2>/dev/null || true
                fi
            done
            exit 2
        fi

        # Creating metainformations
        modfile=$fullext.pm
        # Detect version if it is in a,b,c,d format
        case "$version" in
            *,*,*,*)
                newversion=`perl -MFile::Spec -MExtUtils::MM -le '
                    my $modfile = $ARGV[0];
                    foreach my $dir (@INC) {
                        my $p = File::Spec->catfile($dir, $modfile);
                        if (-r $p) {
                            $version = MM->parse_version($p);
                            last;
                        }
                    }
                    print $version;' "$modfile"`
                if [ -n "$newversion" ]; then
                    version=$newversion
                else
                    version=`echo $version | tr ',' '.' | sed 's/\.0$//' | sed 's/\.0$//'`
                fi
            ;;
        esac

        echo "Creating metainformations for package $distname $version"

	mkdir -p "`dirname "$packlist"`"
        cat "$tmp/newfiles.list" > $packlist
        # TODO: generate PROVIDE tag if is missing
        sed 's/\(<CODEBASE HREF="\)[^"]*\("\)/\1\2/;
             s/\(<SOFTPKG NAME="\)[^"]*\(" VERSION="\)[^"]*\("\)/\1'"$distname"'\2'"$version"'\3/;
             s/\(<TITLE>\).*\(<\/TITLE>\)/\1'"$distname"'\2/;' $ppd \
            > "$blib_arch/auto/.pi.pl-area/$distname.ppd"
        (cat $packlist; echo "$packlist") | tr '\012' '\000' | LC_ALL=C xargs -0r ls -ldn --time-style=long-iso 2>/dev/null \
            > "$blib_arch/auto/.pi.pl-area/$distname.ls"
        (cat $packlist; echo "$packlist") | tr '\012' '\000' | LC_ALL=C xargs -0r md5sum 2>/dev/null \
            > "$blib_arch/auto/.pi.pl-area/$distname.md5sum"
        size=`(cat $packlist; echo "$packlist") | tr '\012' '\000' | LC_ALL=C du --files0-from=- -c 2>/dev/null | tail -n1 | sed 's/[[:space:]].*//'`
        size=$((`printf "%d" $size` * 1024))
        files=`wc -l < "$blib_arch/auto/.pi.pl-area/$distname.ls"`
        (
            cat << END
version: $version
files: $files
size: $size
END
        ) > "$blib_arch/auto/.pi.pl-area/$distname.yml"

        # Cleanup after install
        echo "Cleanup after install"
        if [ $upgrade = yes ]; then
            # HACK: finding removed files
            sort -u "$tmp/oldfiles.list" > "$tmp/oldfiles.sorted"
            sort -u "$tmp/newfiles.list" > "$tmp/newfiles.sorted"
            diff -u "$tmp/oldfiles.sorted" "$tmp/newfiles.sorted" | sed 1,3d | grep '^-' | sed 's/^.//' | while read dst; do
                rm -f "$dst"
            done
        fi
        cat "$tmp/newfiles.list" | while read dst; do
            rm -f "$dst.pi.pl-tmp"
        done

        # Done
        echo "Done."
    done

    exit 0
fi


if [ "$command" = "remove" ]; then
    area_opt=
    if [ "$1" = "--area" ]; then
        shift
        area_opt=$1
        shift
    fi

    if [ -z "$1" ]; then
        echo "Usage: ppm remove <pkg>"
        exit 1
    fi

    while [ -n "$1" ]; do
        pkg=$1
        shift


        n=0
        for area in `perl -MYAML -le '
                $,="\t";
                $c=YAML::LoadFile($ARGV[0]);
                foreach (sort keys %{$c->{area}}) {
                    print $_;
                }' "$PERL_PI_DIR/config.yml"`
        do
            blib_arch=`grep "^  $area: " "$PERL_PI_DIR/config.yml" | sed 's/.*: //'`
            if [ -n "$area_opt" ] && [ "$area" != "$area_opt" ]; then
                continue
            fi
            ppd="$blib_arch/auto/.pi.pl-area/$pkg.ppd"
            ls="$blib_arch/auto/.pi.pl-area/$pkg.ls"
            yml="$blib_arch/auto/.pi.pl-area/$pkg.yml"
            if [ -f "$ppd" ]; then
                if ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.ls" ] || \
                   ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.md5sum" ] || \
                   ! [ -f "$blib_arch/auto/.pi.pl-area/$pkg.yml" ]
                then
                    echo "*** missing metadata for package '$pkg' ***"
                    exit 1
                fi
                n=$(($n+1))
                version=`grep ^version "$yml" | sed 's/^.*: //'`
                echo "Remove the package $pkg $version"
                awk '{ printf "%s%c", $8, 0 }' "$ls" | xargs -0r rm -f
		# TODO: remove empty directories
                rm -f "$blib_arch/auto/.pi.pl-area/$pkg".*

                # Done
                echo "Done."
            fi
        done

        if [ $n = 0 ]; then
            echo "ppm remove failed: Package '$pkg' is not installed"
            exit 1
        fi
    done

    exit 0
fi


echo "Usage: pi.sh area|repo|install|remove|files|list|verify|help"
if [ "$command" = "help" ] || [ "$command" = "" ]; then
    exit 0
fi
exit 1
