#!/usr/bin/perl -wT
# Convert .config to CFLAGS -D flags
#
# Evgueni Souleimanov <esoule[at]100500.ca>

use strict;
use warnings;

my $P = $0;
my $V = '0.1';

use Getopt::Long qw();

my $PREFIX = "CONFIG_";
my $SEPARATOR = " ";
my $HELP = 0;

my @CFLAGS = ();
my $PARSE_FAILED = 0;

our $IDENT = qr{($PREFIX)([a-zA-Z0-9_]+)};

sub help($)
{
	my ($exitcode) = @_;

	print STDERR << "EOM";
Usage: $P [OPTION]... [FILE]...
Version: $V

Convert .config to CFLAGS -D flags.

  --prefix                   prefix (default: CONFIG_)
  --separator                output separator (default: ' ')
  -h, --help, --version      display this help and exit

When prefix is -, means no prefix.

When FILE is - read standard input.
EOM

	exit($exitcode);
}

sub process_file($)
{
	my ($filename) = @_;
	my $fh = undef;
	my $num = 0;

	if ($filename eq '-') {
		open($fh, '<&STDIN');
	} else {
		open($fh, '<', "$filename") ||
			die "$P: $filename: open failed - $!\n";
	}

	while (my $line = <$fh>) {
		$num++;
		chomp($line);
		$line =~ s/\s+$//;
		$line =~ s/^\s+//;

		if ($line =~ /^$IDENT=[ym]$/) {
			# CONFIG_FOO=y
			# CONFIG_FOO=m
			push(@CFLAGS, "-D$1$2=1");
			next;
		}

		if ($line =~ /^$IDENT=n$/) {
			# CONFIG_FOO=n
			push(@CFLAGS, "-U$1$2");
			next;
		}

		if ($line =~ /^# $IDENT is not set$/) {
			# # CONFIG_FOO is not set
			push(@CFLAGS, "-U$1$2");
			next;
		}

		if ($line =~ /^#/) {
			# comment
			next;
		}

		if ($line =~ /^$IDENT=([-]?[0-9]+)$/) {
			# CONFIG_FOO=-12345
			push(@CFLAGS, "-D$1$2=$3");
			next;
		}

		if ($line =~ /^$IDENT=([-]?0[Xx][0-9A-Fa-f]+)$/) {
			# CONFIG_FOO=-0x1234ABCD
			push(@CFLAGS, "-D$1$2=$3");
			next;
		}

		if ($line =~ /^$IDENT=\"([^\"\n]*)\"$/) {
			# CONFIG_FOO="some string"
			push(@CFLAGS, "-D$1$2=\"$3\"");
			next;
		}

		if ($line =~ /^$IDENT=$/) {
			# CONFIG_FOO=
			push(@CFLAGS, "-D$1$2=");
			next;
		}

		if ($line =~ /^(.+)$/) {
			warn "WARNING: can't parse line: $filename:$num:$line\n";
			$PARSE_FAILED = 1;
		}
	}

	close($fh);
}


Getopt::Long::GetOptions(
	'prefix=s'	=> \$PREFIX,
	'separator=s'	=> \$SEPARATOR,
	'h|help'	=> \$HELP,
	'version'	=> \$HELP
) or help(1);

help(0) if ($HELP);

if ($PREFIX eq '-') {
	$PREFIX = '';
}

if ($PREFIX ne '') {
	$IDENT = qr{($PREFIX)([a-zA-Z0-9_]+)};
} else {
	$IDENT = qr{()([a-zA-Z_][a-zA-Z0-9_]*)};
}

#if no filenames are given, emit help
if ($#ARGV < 0) {
	help(1);
}

for my $filename (@ARGV) {
	process_file($filename);
}

if ($PARSE_FAILED) {
	die "$P: config parsing failed\n";
	exit(1);
}

my $CFLAGS_OUT = join($SEPARATOR, @CFLAGS) . $SEPARATOR;
print "$CFLAGS_OUT\n";
exit(0);
