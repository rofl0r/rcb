#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename; 
use Cwd 'abs_path';
#use Data::Dump qw(dump);

my $this_path = abs_path();

sub syntax {
	die "syntax: $0 [--new --force --verbose --step --ignore-errors] mainfile.c [-lc -lm -lncurses]\n" .
	"--new will ignore an existing .rcb file and rescan the deps\n" .
	"--force will force a complete rebuild despite object file presence.\n" .
	"--verbose will print the complete linker output and other info\n" .
	"--step will add one dependency after another, to help finding hidden deps\n";
}

sub expandarr {
	my $res = "";
	while(@_) {
		my $x = shift;
		chomp($x);
		$res .= "$x ";
	}
	return $res;
}

sub expandhash {
	my $res = "";
	my $h = shift;
	for my $x(keys %$h) {
		chomp($x);
		$res .= "$x ";
	}
	return $res;
}

sub name_wo_ext {
	my $x = shift;
	my $l = length($x);
	$l-- while($l && substr($x, $l, 1) ne ".");
	return substr($x, 0, $l + 1) if($l);
	return "";
}

my $colors = {
	"default" => 98,
	"white" => 97,
	"cyan" => 96,
	"magenta" => 95,
	"blue" => 94,
	"yellow" => 93,
	"green" => 92,
	"red" => 91,
	"gray" => 90,
	"end" => 0
};
my $colstr = "\033[%dm";

my %hdep;
my @adep;

sub printc {
	my $color = shift;
	printf $colstr, $colors->{$color};
	for my $x(@_) {
		print $x;
	}
	printf $colstr, $colors->{"end"};
}

sub scandep_doit {
	my ($self, $nf) = @_;
	my $np = dirname($nf);
	my $nb = basename($nf);
	if(!defined($hdep{$nf})) {
		if(! -e $nf) {
			printc("red", "failed to find dependency $nf referenced from $self!\n");
			die unless $nf =~ /\.h$/;
		} else {
			scanfile($np, $nb);
		}
	}
}

sub make_relative {
	my ($basepath, $relpath) = @_;
	#print "$basepath ::: $relpath\n";
	die "both path's must start with /" if(substr($basepath, 0, 1) ne "/" || substr($relpath, 0, 1) ne "/");
	$basepath .= "/" if($basepath !~ /\/$/ && -d $basepath);
	$relpath .= "/" if($relpath !~ /\/$/ && -d $relpath);
	my $l = 0;
	my $l2 = 0;
	my $sl = 0;
	$l++ while(substr($basepath, $l, 1) eq substr($relpath, $l, 1));
	if($l != 0) {
		$l-- while(substr($basepath, $l, 1) ne "/");
	}
        $l++ if substr($relpath, $l, 1) eq "/";
	my $res = substr($relpath, $l);
	$l2 = $l;
	while($l2 < length($basepath)) {
		$sl++ if substr($basepath, $l2, 1) eq "/";
		$l2++;
	}
	my $i;
	for ($i = 0; $i < $sl; $i++) {
		$res = "../" . $res;
	}
	return $res;
}


sub scandep {
	my ($self, $path, $tf) = @_;
	my $absolute = substr($tf, 0, 1) eq "/";
	
	my $nf = $absolute ? $tf : abs_path($path . "/" . $tf);
	printc("red", "[RcB] warning: $tf not found, continuing...\n"), return if !defined($nf);

	
	if ($nf =~ /^\// && $nf !~ /\.h$/) {
		$nf = make_relative($this_path, $nf);
	}
	die "problem processing $self, $path, $tf" if(!defined($nf));
	if($nf =~ /\*/) {
		my @deps = glob($nf);
		for my $d(@deps) {
			scandep_doit($self, $d);
		}
	} else {
		scandep_doit($self, $nf);
	}
}

my $link = "";
my $forcerebuild = 0;
my $verbose = 0;
my $step = 0;
my $ignore_rcb = 0;
my $mainfile = undef;
my $ignore_errors = 0;
my $debug_cflags = 0;

sub scanfile {
	my ($path, $file) = @_;
	my $fp;
	my $self = $path . "/" . $file;
	my $tf = "";

	$hdep{$self} = 1;
	open($fp, "<", $self) or die "could not open file $self: $!";
	while(<$fp>) {
		my $line = $_;
		if ($line =~ /^\/\/RcB: (\w{3,6}) \"(.+?)\"/) {
			my $command = $1;
			my $arg = $2;
			if($command eq "DEP") {
				$tf = $arg;
				print "found RcB DEP $tf : $self\n" if $verbose;
				scandep($self, $path, $tf);
			} elsif ($command eq "LINK") {
				print "found RcB LINK $arg\n" if $verbose;
				$link .= $arg . " ";
			}
		} elsif($line =~ /^\s*#\s*include\s+\"([\w\.\/_\-]+?)\"/) {
			$tf = $1;
			scandep($self, $path, $tf);
		} else {

			$tf = "x";
		}
	}
	close $fp;
	push @adep, $self if $file =~ /[\w_-]+\.[c]{1}$/; #only add .c files to deps...
}

argscan:
my $arg1 = shift @ARGV or syntax;
if($arg1 eq "--force") {
	$forcerebuild = 1;
	goto argscan;
} elsif($arg1 eq "--verbose") {
	$verbose = 1;
	goto argscan;
} elsif($arg1 eq "--new") {
	$ignore_rcb = 1;
	goto argscan;
} elsif($arg1 eq "--step") {
	$step = 1;
	goto argscan;
} elsif($arg1 eq "--ignore-errors") {
	$ignore_errors = 1;
	goto argscan;
} elsif($arg1 eq "--debug") {
	$debug_cflags = 1;
	goto argscan;
} else {
	$mainfile = $arg1;
}

$mainfile = shift unless defined($mainfile);
syntax unless defined($mainfile);

my $cc;
if (defined($ENV{CC})) {
	$cc = $ENV{CC};
} else {
	$cc = "cc";
	printc "blue", "[RcB] \$CC not set, defaulting to cc\n";
}

my $cflags = defined($ENV{CFLAGS}) ? $ENV{CFLAGS} : "";
$cflags .= $debug_cflags ? "-O0 -g" : "";

my $nm;
if (defined($ENV{NM})) {
	$nm = $ENV{NM};
} else {
	$nm = "nm";
	printc "blue", "[RcB] \$NM not set, defaulting to nm\n";
}

sub compile {
	my ($cmdline) = @_;
	printc "magenta", "[CC] ", $cmdline, "\n";
	my $reslt = `$cmdline 2>&1`;
	if($!) {
		printc "red", "ERROR ", $!, "\n";
		exit 1;
	}
	print $reslt;
	return $reslt;
}

$link = expandarr(@ARGV) . " ";

my $cnd = name_wo_ext($mainfile);
my $cndo = $cnd . "o";
my $bin = $cnd . "out";

my $cfgn = name_wo_ext($mainfile) . "rcb";
my $haveconfig = (-e $cfgn);
if($haveconfig && !$ignore_rcb) {
	printc "blue", "[RcB] config file found. trying single compile.\n";
	@adep = `cat $cfgn | grep "^DEP " | cut -b 5-`;
	my @rcb_links = `cat $cfgn | grep "^LINK" | cut -b 6-`;
	my $cs = expandarr(@adep);
	my $ls = expandarr(@rcb_links);
	$link = $ls if (defined($ls) && $ls ne "");
	my $res = compile("$cc $cflags $cs $link -o $bin");
	if($res =~ /undefined reference to/) {
		printc "red", "[RcB] undefined reference[s] found, switching to scan mode\n";
	} else {
		if($?) {
			printc "red", "[RcB] error. exiting.\n";
		} else {
			printc "green", "[RcB] success. $bin created.\n";
		}
		exit $?;
	}
} 

printc "blue",  "[RcB] scanning deps...";

scanfile dirname(abs_path($mainfile)), basename($mainfile);

printc "green",  "done\n";

my %obj;
printc "blue",  "[RcB] compiling main file...\n";
my $op = compile("$cc $cflags -c $mainfile -o $cndo");
exit 1 if($op =~ /error:/g);
$obj{$cndo} = 1;
my %sym;

my $i = 0;
my $success = 0;
my $run = 0;
my $relink = 1;
my $rebuildflag = 0;
my $objfail = 0;

my %glob_missym;
my %missym;
my %rebuilt;
printc "blue",  "[RcB] resolving linker deps...\n";
while(!$success) {
	my @opa;
	if($i + 1 >= @adep) { #last element of the array is the already build mainfile
		$run++;
		$i = 0;
	}
	if(!$i) {
		%glob_missym = %missym, last unless $relink;
		# trying to link
		my %missym_old = %missym;
		%missym = ();
		my $ex = expandhash(\%obj);
		printc "blue",  "[RcB] trying to link ...\n";
		my $cmd = "$cc $cflags $ex $link -o $bin";
		printc "cyan", "[LD] ", $cmd, "\n";
		@opa = `$cmd 2>&1`;
		for(@opa) {
			if(/undefined reference to [\'\`\"]{1}([\w\._]+)[\'\`\"]{1}/) {
				my $temp = $1;
				print if $verbose;
				$missym{$temp} = 1;
			} elsif(
				/([\/\w\._\-]+): file not recognized: File format not recognized/ ||
				/architecture of input file [\'\`\"]{1}([\/\w\._\-]+)[\'\`\"]{1} is incompatible with/ ||
				/fatal error: ([\/\w\._\-]+): unsupported ELF machine number/ ||
				/ld: ([\/\w\._\-]+): Relocations in generic ELF/
			) {
				$cnd = $1;
				$i = delete $obj{$cnd};
				printc "red", "[RcB] incompatible object file $cnd, rebuilding...\n";
				print;
				$cnd =~ s/\.o/\.c/;
				$rebuildflag = 1;
				$objfail = 1;
				%missym = %missym_old;
				goto rebuild;
			} elsif(
			/collect2: ld returned 1 exit status/ ||
			/In function [\'\`\"]{1}[\w_]+[\'\`\"]{1}:/ ||
			/more undefined references to/
			) {
			} else {
				printc "red", "[RcB] FATAL: unexpected linker output!\n";
				print;
				exit 1;
			}
		}
		if(!scalar(keys %missym)) {
			for(@opa) {print;}
			$success = 1; 
			last;
		}
		$relink = 0;
	}
	$cnd = $adep[$i];
	goto skip unless defined $cnd;
	$rebuildflag = 0;
	rebuild:
	chomp($cnd);
	$cndo = name_wo_ext($cnd) . "o";
	if(($forcerebuild || $rebuildflag || ! -e $cndo) && !defined($rebuilt{$cndo})) {
		my $op = compile("$cc $cflags -c $cnd -o $cndo");
		if($op =~ /error:/) {
			exit 1 unless($ignore_errors);
		} else {
			$rebuilt{$cndo} = 1;
		}
	}
	@opa = `$nm -g $cndo 2>&1`;
	my %symhash;
	my $matched = 0;
	for(@opa) {
		if(/[\da-fA-F]{8,16}\s+[TWRBCD]{1}\s+([\w_]+)/) {
			my $symname = $1;
			$symhash{$symname} = 1;
			$matched = 1;
		} elsif (/File format not recognized/) {
			printc "red",  "[RcB] nm doesn't recognize the format of $cndo, rebuilding...\n";
			$rebuildflag = 1;
			goto rebuild;
		}
	}
	if($matched){
		$sym{$cndo} = \%symhash;
		my $good = 0;
		for(keys %missym) {
			if(defined($symhash{$_})) {
				$obj{$cndo} = $i;
				$adep[$i] = undef;
				$relink = 1;
				if($objfail || $step) {
					$objfail = 0;
					$i = -1;
					printc "red", "[RcB] adding $cndo to the bunch...\n" if $step;
				}
				last;
			}
		}
	}
	skip:
	$i++;
}

if(!$success) {
	printc "red", "[RcB] failed to resolve the following symbols, check your DEP tags\n";
	for(keys %glob_missym) {
		print "$_\n";
	}
} else {
	printc "green", "[RcB] success. $bin created.\n";
	printc "blue", "saving required dependencies to $cfgn\n";
	my $fh;
	open($fh, ">", $cfgn);
	for(keys %obj) {
		print { $fh } "DEP ", name_wo_ext($_), "c\n";
	}
	print { $fh } "LINK ", $link, "\n" if($link);
	close($fh);
}
