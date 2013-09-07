#!/usr/bin/env perl

# program to automatically generate an optimized Makefile from an rcb file
# it is optimized because it only compiles *used* stuff
# use like this: cat myprog.rcb | rcb2make myprog > Makefile

use strict;
use warnings;

my $progname = $ARGV[0] or 
	die ("pass name of executable the makefile has to build");

my @libs;
my @c;

while(<STDIN>) {
	chomp;
	if(/^DEP ([\w_\-\/\.]+)$/) {
		push @c, $1;
	} elsif (/^LINK ([\w_\-\/\.]+)$/) {
		push @libs, $1;
	}
}

sub make_list {
	my @a = @_;
	my $res = "";
	for(@a) {
		$res .= " \\\n" . $_;
	}
	return $res;
}

my $mak_template = << 'EOF';
prefix = /usr/local
bindir = $(prefix)/bin

PROG = #PROG#
SRCS = #SRCS#
LIBS = #LIBS#
OBJS = $(SRCS:.c=.o)

CFLAGS += -Wall -D_GNU_SOURCE

-include config.mak

all: $(PROG)

install: $(PROG)
	install -d $(DESTDIR)/$(bindir)
	install -D -m 755 $(PROG) $(DESTDIR)/$(bindir)/

clean:
	rm -f $(PROG)
	rm -f $(OBJS)

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(INC) $(PIC) -c -o $@ $<

$(PROG): $(OBJS)
	 $(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $@

.PHONY: all clean install

EOF

$mak_template =~ s/#PROG#/$progname/;
my $lc = make_list(@c);
$mak_template =~ s/#SRCS#/$lc/;
my $ll = make_list(@libs);
$mak_template =~ s/#LIBS#/$ll/;

print $mak_template;

