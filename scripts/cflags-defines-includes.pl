#!/usr/bin/perl -wT
# Filter out CFLAGS
#
# By Evgueni Souleimanov <esoule[at]100500.ca>

use strict;
use warnings;

my $P = $0;
my $V = '0.1';

sub do_cflags_defines_includes(@)
{
	my $tail = '';
	while (@_ > 0) {
		my $a = shift;
		if ($a =~ /^[-][IDU]./) {
			if ($a =~ / / || $a =~ /"/) {
				$a = "'$a'";
			}
			print " $a";
			$tail = "\n";
		} elsif ($a =~ '^[-]isystem') {
			if (@_ > 0) {
				$a = shift;
				print " -I$a";
				$tail = "\n";
			}
		}
	}
	if ($tail) {
		print $tail;
	}
}

do_cflags_defines_includes(@ARGV);
