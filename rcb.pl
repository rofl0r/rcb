#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename; 
use Cwd 'abs_path';

sub syntax {
	die "syntax: $0 mainfile.c";
}

my %hdep;
my @adep;

sub scanfile {
	my ($path, $file) = @_;
	my $fp;
	my $self = $path . "/" . $file;

	$hdep{$self} = 1;
	open($fp, "<", $self) or die "could not open file $self: $!";
	while(<$fp>) {
		if (/^\/\/RcB: (\w{3,6}) \"(.+?)\"/) {
			my $command = $1;
			my $arg = $2;
			if($command eq "DEP") {
				my $absolute = substr($arg, 0, 1) eq "/";
				my $nf = $absolute ? $arg : abs_path($path . "/" . $arg);
				my $np = dirname($nf);
				my $nb = basename($nf);
				if(!defined($hdep{$nf})) {
					die("failed to find dependency $nf referenced from $self") if(! -e $nf);
					scanfile($np, $nb);
				}
			}
		}
	}
	close $fp;
	push @adep, $self;
}

my $mainfile = $ARGV[0] or syntax;
scanfile dirname(abs_path($mainfile)), basename($mainfile);
for(@adep) {
	print "$_ ";
}
