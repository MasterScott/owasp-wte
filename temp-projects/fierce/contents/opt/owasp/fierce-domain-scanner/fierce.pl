#!/usr/bin/perl

#########################################
# Fierce v1.0.3 - Beta 03/23/2008
# By RSnake http://ha.ckers.org/fierce/
# Threading by IceShaman
# Zone transfer and additional patches by Jabra
#########################################

use strict; #warnings off after testing
use Net::hostent;
use Net::DNS;
use IO::Socket;
use Socket;
use Getopt::Long;

# command line options
my $class_c;
my $delay = 0;
my $dns;
my $dns_file;
my $dns_server;
my @dns_servers;
my $filename;  
my $full_output;
my $help; 
my $http_connect;  
my $nopattern;  
my $range;
my $search;
my $suppress;
my $stop;
my $tcp_timeout;
my $threads;
my $traverse;   
my $version;   
my $wide;    		
my $wordlist;		
                  			
my @common_cnames;
my $count_hostnames = 0;
my $count = 0;
my @domain_ns;
my $h;
my %known_ips;
my %known_names;
my @ip_and_hostname;
my $logging;
my %options = ();
my @output;
my $res = Net::DNS::Resolver->new;
my $search_found;
my %subnets;
my %tested_names;
my $this_ip;
my $thread_support;
my @thread;
my $version_num = 'Version 1.0.3 - 03/23/2008';
my $webservers = 0;
my $wildcard_dns;
my @wildcards;
my @zone;

# ignore all errors while trying to load up thead stuff
BEGIN {
  $SIG{__DIE__}  = sub { };
  $SIG{__WARN__} = sub { };
}
  
# try and load thread modules, if it works import their functions
BEGIN { 
  eval {
    require threads;
    require threads::shared;
    require Thread::Queue;
    $thread_support = 1;
  };
  if ($@) { # got errors, no ithreads :(
    $thread_support = 0;
  } else { #safe to haul in the threadding functions
    import threads;
    import threads::shared;
    import Thread::Queue;
  }
}

# turn errors back on
BEGIN {
  $SIG{__DIE__}  = 'DEFAULT';
  $SIG{__WARN__} = 'DEFAULT';
}

my $result = GetOptions (	
        			'dns=s'		=> \$dns, 
	                'file=s'	=> \$filename,
                  	'suppress'	=> \$suppress,
                  	'help'		=> \$help, 
                  	'connect=s'	=> \$http_connect,
                  	'range=s'	=> \$range,
                  	'wide'		=> \$wide,
                  	'delay=i'	=> \$delay,
                  	'dnsfile=s'	=> \$dns_file,
                  	'dnsserver=s'	=> \$dns_server,
                  	'version'	=> \$version,
                  	'search=s'	=> \$search,
                  	'stop'	=> \$stop,
                  	'wordlist=s'	=> \$wordlist,
                  	'fulloutput'	=> \$full_output,
                  	'nopattern'	=> \$nopattern,
                  	'tcptimeout=i'	=> \$tcp_timeout,
                  	'traverse=i'	=> \$traverse,
                  	'threads=i'	=> \$threads,
                        );

help()                   if $help;
quit_early($version_num) if $version;

if (!$dns && !$range) {
  output("You have to use the -dns switch with a domain after it.");
  quit_early("Type: perl fierce.pl -h for help");
} elsif ($dns && $dns !~ /[a-z\d.-]\.[a-z]*/i) {
  output("\n\tUhm, no. \"$dns\" is gimp. A bad domain can mess up your day.");
  quit_early("\tTry again.");
}

if ($filename && $filename ne '') {
  $logging = 1;
  if (-e $filename) { # file exists
    print "File already exists, do you want to overwrite it? [Y|N] ";
    chomp(my $overwrite = <STDIN>);
    if ($overwrite =~ /y/i) {
      open FILE, '>', $filename 
        or quit_early("Having trouble opening $filename anyway");
    } else {
      quit_early('Okay, giving up');
    } 
  } else {
    open FILE, '>', $filename 
      or quit_early("Having trouble opening $filename");
  }
  output('Now logging to ' . $filename);
} 

if ($http_connect) {
  unless (-r $http_connect) {
    quit_early("Having trouble opening $http_connect");
  } 
} 

# if user doesn't provide a number, they both end up at 0
quit_early('Your delay tag must be a positive integer')  
  if (defined $delay && $delay != 0 && $delay !~ /^\d*$/);
quit_early('Your thread tag must be a positive integer') 
  if (defined $threads && $threads != 0 && $threads !~ /^\d*$/);

if ($threads and not $thread_support) {
  quit_early('Perl is not configured to support ithreads');
}
  
if ($dns_file) {
  open (DNSFILE, '<', $dns_file) 
   or quit_early("Can't open $dns_file");
   for (<DNSFILE>) {
     chomp;
     push @dns_servers, $_;
   }  
   if (@dns_servers) {
     output("Using DNS servers from $dns_file");
   } else {
     output("DNS file $dns_file is empty, using default options");
   }
}

if ($full_output && !$http_connect) {
  output("Warning: you selected the -fulloutput option but didn't use");
  output("-connect.\n\tNot sure what to do with that, so continuing...");
}

if ($suppress && !$filename) {
  quit_early("You need to use the -s switch with the -f switch.\n
             . Otherwise all will perish...");
}

$res->tcp_timeout($tcp_timeout || 10);

if ($range) {
  $nopattern = 1;
  quit_early('-range must be combined with -dnsserver', $logging, $suppress) 
    if !$dns_server;
  $res->nameservers($dns_server);
  find_nearby($range);
  exit;
}

if ($traverse) {
  unless ($traverse =~ /\d{1,3}/ && ( $traverse >= 0 || $traverse <= 255 ) && $traverse !~ /0\d{1,2}/){
    quit_early('The -t flag must contain an integer 0-255');
  }
} else {
  $traverse = 5;
}

my @search_strings = split(/\x2C/, $search) if $search;
my $query          = $res->query($dns, 'NS');

if ($query) {
  output("DNS Servers for $dns:");
  foreach my $rr (grep { $_->type eq 'NS' } $query->answer) {
    my $dnssrv = $rr->nsdname;
    output("\t$dnssrv");
    push (@domain_ns, $rr->nsdname);
  }
}

output("\nTrying zone transfer first...");

if ($dns_server) {
  @zone = $res->axfr($dns);
} else {
  for (@domain_ns) {
    $res->nameservers($_);
    output("\tTesting $_");
    @zone = $res->axfr($dns);
    @zone ? last : output("\t\tRequest timed out or transfer not allowed.");
  }
}

if ($dns_server) {
  $res->nameservers($dns_server);
} else {
  $res->nameservers(@domain_ns);
}

# DNS server gave us everything so we don't have to guess
if (@zone) {
  output("\nWhoah, it worked - misconfigured DNS server found:");
  output($_->string) for (@zone);
  if ($stop) {
    quit_early("\nThere isn't much point continuing, you have everything.\n"
                 . "Have a nice day.");
  }
} elsif ($dns) {
  output("\nUnsuccessful in zone transfer (it was worth a shot)");
}
  output("Okay, trying the good old fashioned way... brute force");
  $wordlist = $wordlist || 'hosts.txt';
  if (-e $wordlist) {
    open (WORDLIST, '<', $wordlist)   or
    open (WORDLIST, '<', 'hosts.txt') or
    quit_early("Can't open $wordlist or the default wordlist");
    for (<WORDLIST>){
      chomp;
      push @common_cnames, $_;
    }
    close WORDLIST;
  } else {
    quit_early("Can't open $wordlist or the default wordlist");
  }
  output("\nChecking for wildcard DNS...");
  srand;
  $wildcard_dns = 1e11 - int(rand(1e10));
  if ($h = gethost("$wildcard_dns.$dns")) {
    my $wildcard_addr = inet_ntoa($h->addr);
    output("\t** Found $wildcard_dns.$dns at $wildcard_addr.");
    output("\t** High probability of wildcard DNS.");
    $wildcard_dns = $wildcard_addr;
  } else {
    output('Nope. Good.');
    $wildcard_dns = q{};
  }
  my $total_cnames = @common_cnames;
  output("Now performing $total_cnames test(s)...");
  if ($threads) {
    share($count);
    share(%known_ips);
    share(%known_names);
    share(@output);
    my $stream = new Thread::Queue;
    foreach my $host (@common_cnames) {
      $stream->enqueue("$host.$dns");
    }
    for (0..$threads) {
      my $kid = new threads(\&search_host, $stream);
      $stream->enqueue(undef); #for each thread
    }
    foreach my $thread (threads->list) { 
     $thread->join if ($thread->tid && !threads::equal($thread, threads->self)); 
    } 
  } else {
    foreach my $host (@common_cnames) {
      search_host("$host.$dns");
    }  
  }
  # write to file any output generated by child threads
  print FILE for @output;

foreach my $current_name (sort keys(%known_names)) {
  @ip_and_hostname = split (/\x2C/, $current_name);
  my @bytes        = split (/\x2E/, $ip_and_hostname[0]);
  if ( $subnets{"$bytes[0].$bytes[1].$bytes[2]"} ) {
    $subnets{"$bytes[0].$bytes[1].$bytes[2]"}++;
  } else {
    $subnets{"$bytes[0].$bytes[1].$bytes[2]"} = 1;
  }
}

output("\nSubnets found (may want to probe here using nmap or unicornscan):");

foreach my $athroughc (sort keys(%subnets)) {
  $count_hostnames += $subnets{$athroughc};
  output("\t$athroughc.0-255 : $subnets{$athroughc} hostnames found.");
}

&http_connect if $http_connect;

output("\nDone with Fierce scan: http://ha.ckers.org/fierce/\n"
        . "Found $count entries.\n" 
        . ($http_connect ? "and $webservers webservers." : ""));
          
output('Have a nice day.');
close FILE if $logging;

# subs
sub set_nameservers {
  my $res = shift;
  my @servers;
  push @servers, @dns_servers if @dns_servers;
  push @servers, $dns_server  if $dns_server;
  push @servers, @domain_ns   if !@servers;
  $$res->nameservers(@servers);
}

# print_reverse: domain(Scalar) ip_list(Ref HASH) -> 
# prints the ip_list hash with the domain
sub print_reverse {
    my ($domain, $ip_list) = @_;
    
    for my $key ( keys %$ip_list ) {
        my $value = $$ip_list{$key};
        print "$domain\taddress\t$key\n";
    }
}

# reverse_lookup: domain(Scalar) -> number_IPs_found(Scalar) 
# lookup the domain and determine all the IPs for it
sub reverse_lookup {
    my $domain = shift;
    $domain =~ s/\.$//g;
    my $inet = inet_aton("$domain");
    my %ip_list = ();
    my $loop = 1;
    while($loop < 20) {
        my $inet = inet_aton("$domain");
        if (defined $inet){
            my $ip = inet_ntoa($inet);
            if (defined($ip_list{$ip})) {
                $loop++;
            }
            else {
                $ip_list{$ip} = 1;
            }
        }
    }
    print_reverse($domain,\%ip_list);    
    return scalar(keys %ip_list);
}

sub search_host {
  sleep $delay;
  my $upstream;
  my $tid;
  my $resbf;
  if ($threads && threads->self->tid()) {
    $upstream = shift;
    $tid      = threads->self->tid();
    $resbf    = Net::DNS::Resolver->new;
    set_nameservers(\$resbf);
  } else {
    $resbf = $res;
  }

  # only runs once if not threaded
  while (my $search_item = $threads ? $upstream->dequeue : shift) {    
    next unless my $packet = $resbf->search($search_item);
    foreach my $answer ($packet->answer) {
      my @name = split (/\t/, $answer->string);
      if ($name[3] eq 'CNAME') {
        chop($name[4]);
        print "$search_item\t\talias\t\t$name[4]\n";
        
        my @name = split (/\t/, $answer->string);
        next unless ( $name[3] eq 'A'     ||
                      $name[3] eq 'PTR'   ||
                      $name[3] eq 'CNAME'
                    );
        my @name = split (/\t/, $answer->string);
        $count += reverse_lookup($name[4]);
      }
      next unless ( $name[3] eq 'A'     || 
                    $name[3] eq 'PTR'
                  );
      chop $name[0];
      if ($name[4] eq $wildcard_dns) {
        $this_ip = $name[4];
        find_nearby($this_ip) if !$known_ips{$this_ip};
        $known_ips{$answer->address} = 1;
        push @wildcards, "$wildcard_dns\t$search_item"; #may do something later 
        next;
      } 
      
      $this_ip = $name[4];
      find_nearby($this_ip) if !$known_ips{$this_ip};
      $known_ips{$this_ip} = 1;
      next if $known_names{"$this_ip,$search_item"};
      $count++;
      $known_names{"$this_ip,$search_item"} = 1; 
      output("$this_ip\t$search_item");
    }
  }
}

sub find_nearby {
  my $lowest;
  my $highest;
  my @octet;
  my $res = $res; # local copy so threads aren't waiting for others
  @octet = split(/\x2E/, shift);
  if ($wide) {
    ($lowest, $highest) = (0, 255);
  } else { # user provided range
    if ($octet[3] =~ /(\d*)-(\d*)/) {
      ($lowest, $highest) = ($1, $2);
      quit_early("Your range doesn't make sense, try again") 
        if $highest < $lowest;
    } else { # automatic call
      $lowest  = $octet[3] < $traverse       ? 0   : $octet[3] - $traverse;
      $highest = $octet[3] > 255 - $traverse ? 255 : $octet[3] + $traverse;
    }
  }
  
  foreach $class_c ($lowest..$highest) {
    sleep $delay;
    next if $class_c eq $octet[3];
    $octet[3] = $class_c;
    next if $known_ips{"$octet[0].$octet[1].$octet[2].$octet[3]"};
    $known_ips{"$octet[0].$octet[1].$octet[2].$octet[3]"} = 1;
    next unless my $packet = $res->search("$octet[0].$octet[1]."
                                          . "$octet[2].$octet[3]");
    foreach my $answer ($packet->answer) {
      next unless ($answer->type eq 'A' || $answer->type eq 'PTR');
      my @name = split (/\t/, $answer->string);
      chop $name[$#name];
      next if ($name[4] eq $wildcard_dns); 
      if ($search) {
        foreach (@search_strings) {
          if ($name[$#name] =~ /$_/ || $nopattern || !$dns) {
            $count++;
            $known_names{"$octet[0].$octet[1].$octet[2].$octet[3],"
                         . "$name[$#name]"} = 1;
            output("$octet[0].$octet[1].$octet[2].$octet[3]\t$name[$#name]");
            find_nearby("$octet[0].$octet[1].$octet[2].$octet[3]"); # recurse 
          }
        }
      } 
      next if ($name[$#name] !~ /$dns/ && !$nopattern);
      $count++;
      $known_names{"$octet[0].$octet[1].$octet[2].$octet[3],"
                   . "$name[$#name]"} = 1;
      output("$octet[0].$octet[1].$octet[2].$octet[3]\t$name[$#name]");
      find_nearby("$octet[0].$octet[1].$octet[2].$octet[3]");  # recurse  
    }
  }
}

sub http_connect {
  foreach my $_current_name (sort keys(%known_names)) {
    my @headers;
    my @my_headers;
    
    @ip_and_hostname = split(/\x2C/, $_current_name);
    my @octet        = split(/\x2E/, $ip_and_hostname[0]);
    if ($octet[0] == 10                     || # can't query RFC1918
        "$octet[0].$octet[1]" eq "192.168"  ||
        ($octet[0] == 172 && $octet[1] > 32 && $octet[1] < 15) ||
        ($ip_and_hostname[0] eq "127.0.0.1") # loopback
       ) {
      next;
    }
    
    open (HEADERS, $http_connect) 
      or quit_early("Don't know why but I can't read from $http_connect now");
    
    foreach (<HEADERS>) {
      $_ =~ s{^Host:\s*\n$}{Host: $ip_and_hostname[1]\n};
      push (@my_headers, $_);
    }
    close HEADERS;
    if ($my_headers[$#my_headers] !~ /^(\r\n)*$/)  {
      $my_headers[$#my_headers + 1] = "\r\n\r\n";
    }
    #TODO: add port selection and range support
    my $socket = new IO::Socket::INET (	
                                      	PeerAddr => "$ip_and_hostname[0]",
	                                  	PeerPort => 'http(80)',
                      					Timeout  => 10,
                                  		Proto    => 'tcp',
                                      )
      or next;
    $webservers++;
    foreach (@my_headers) {
      print $socket $_;
    }
    print $socket . "\n\n";
    foreach (<$socket>) {
      unless ($_ =~ /^(\r\n)*$/) {
        push (@headers, $_);
      } else {
        last unless $full_output;
      }
    }
    output("\n\nHTTP output for $ip_and_hostname[0] $ip_and_hostname[1]");
    output("\t$_") foreach @headers;
    close $socket;
  }
}

sub output {
  my $text = shift;
  if ($logging) {
    if ($threads && threads->self->tid) {
      push @output, "$text\n";  
    } else {
      print FILE "$text\n";
    }
  }
  print "$text\n" unless $suppress;
}

sub quit_early {
  my ($text, $logging, $suppress) = @_; 
  print FILE "$text\nExiting...\n\n" if $logging;
  print "$text\nExiting...\n" unless $suppress;
  exit;
}

sub help {
  print <<EOHELP;
fierce.pl (C) Copywrite 2006-2008 - By RSnake at http://ha.ckers.org/fierce/

	Usage: perl fierce.pl [-dns example.com] [OPTIONS]

Overview:
	Fierce is a semi-lightweight scanner that helps locate non-contiguous
	IP space and hostnames against specified domains.  It's really meant
	as a pre-cursor to nmap, unicornscan, nessus, nikto, etc, since all 
	of those require that you already know what IP space you are looking 
	for.  This does not perform exploitation and does not scan the whole 
	internet indiscriminately.  It is meant specifically to locate likely 
	targets both inside and outside a corporate network.  Because it uses 
	DNS primarily you will often find mis-configured networks that leak 
	internal address space. That's especially useful in targeted malware.

Options:
	-connect	Attempt to make http connections to any non RFC1918
		(public) addresses.  This will output the return headers but
		be warned, this could take a long time against a company with
		many targets, depending on network/machine lag.  I wouldn't
		recommend doing this unless it's a small company or you have a
		lot of free time on your hands (could take hours-days).  
		Inside the file specified the text "Host:\\n" will be replaced
		by the host specified. Usage:

	perl fierce.pl -dns example.com -connect headers.txt

	-delay		The number of seconds to wait between lookups.
	-dns		The domain you would like scanned.
	-dnsfile  	Use DNS servers provided by a file (one per line) for
                reverse lookups (brute force).
	-dnsserver	Use a particular DNS server for reverse lookups 
		(probably should be the DNS server of the target).  Fierce
		uses your DNS server for the initial SOA query and then uses
		the target's DNS server for all additional queries by default.
	-file		A file you would like to output to be logged to.
	-fulloutput	When combined with -connect this will output everything
		the webserver sends back, not just the HTTP headers.
	-help		This screen.
	-nopattern	Don't use a search pattern when looking for nearby
		hosts.  Instead dump everything.  This is really noisy but
		is useful for finding other domains that spammers might be
		using.  It will also give you lots of false positives, 
		especially on large domains.
	-range		Scan an internal IP range (must be combined with 
		-dnsserver).  Note, that this does not support a pattern
		and will simply output anything it finds.  Usage:

	perl fierce.pl -range 111.222.333.0-255 -dnsserver ns1.example.co

	-search		Search list.  When fierce attempts to traverse up and
		down ipspace it may encounter other servers within other
		domains that may belong to the same company.  If you supply a 
		comma delimited list to fierce it will report anything found.
		This is especially useful if the corporate servers are named
		different from the public facing website.  Usage:

	perl fierce.pl -dns examplecompany.com -search corpcompany,blahcompany 

		Note that using search could also greatly expand the number of
		hosts found, as it will continue to traverse once it locates
		servers that you specified in your search list.  The more the
		better.
	-stop		Stop scan if Zone Transfer works.
	-suppress	Suppress all TTY output (when combined with -file).
	-tcptimeout	Specify a different timeout (default 10 seconds).  You
		may want to increase this if the DNS server you are querying
		is slow or has a lot of network lag.
	-threads  Specify how many threads to use while scanning (default
	  is single threaded).
	-traverse	Specify a number of IPs above and below whatever IP you
		have found to look for nearby IPs.  Default is 5 above and 
		below.  Traverse will not move into other C blocks.
	-version	Output the version number.
	-wide		Scan the entire class C after finding any matching
		hostnames in that class C.  This generates a lot more traffic
		but can uncover a lot more information.
	-wordlist	Use a seperate wordlist (one word per line).  Usage:

	perl fierce.pl -dns examplecompany.com -wordlist dictionary.txt
EOHELP
exit;
}
