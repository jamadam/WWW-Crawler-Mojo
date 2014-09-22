use strict;
use warnings;
use utf8;
use WWW::Crawler::Mojo;
use 5.10.0;
use Mojo::URL;

my $bot = WWW::Crawler::Mojo->new;
my %count;

my $start = Mojo::URL->new(pop @ARGV);

$bot->on(start => sub {
    shift->say_start;
});

$bot->on(error => sub {
    my ($bot, $msg, $job) = @_;
    
    $count{'N/A'}++;
    
    chomp($msg);
    
    report_stdout($msg, $job->resolved_uri, $job->referrer->resolved_uri);
});

$bot->on(res => sub {
    $| = 1;
    
    my ($bot, $discover, $job, $res) = @_;
    
    $count{$res->code}++;
    
    if ($res->code =~ qr{[54]..}) {
        my $msg = $res->code. ' occured!';
        report_stdout($msg, $job->resolved_uri, $job->referrer->resolved_uri);
    }
    
    $count{QUEUE} = scalar @{$bot->queue};
    my @props = map { join(':', $_, $count{$_}) } (sort keys %count);
    print join(' / ', @props), ' ' x 30, "\r";
    
    $discover->();
});

$bot->on(refer => sub {
    my ($bot, $enqueue, $job, $context) = @_;
    
    if (security_warning($job, $context)) {
        $count{'WARNING'}++;
        my $msg = 'WARNING : Cross-scheme resource found';
        report_stdout($msg, $job->resolved_uri, $job->referrer->resolved_uri);
    }
    
    $enqueue->() if ($job->referrer->resolved_uri->host eq $start->host);
    #$enqueue->() ;
});

$bot->shuffle(5);
$bot->max_conn_per_host(2);
$bot->max_conn(5);
$bot->enqueue($start);
$bot->peeping_port(3001);
$bot->crawl;

sub report_stdout {
    my ($msg, $url, $url_referrer) = @_;
    state $index = 1;
    say sprintf(
        '%s: %s at %s referred by %s',
        $index++,
        $msg,
        $url,
        $url_referrer,
    );
}

sub security_warning {
    my ($job, $context) = @_;
    
    my $scheme1 = $job->referrer->resolved_uri->protocol;
    my $scheme2 = $job->resolved_uri->protocol;
    
    if ($scheme1 eq 'https' && $scheme2 ne 'https') {
        return 1 if (!ref $context || ref $context ne 'Mojo::DOM');
        return 0 if ($context->type eq 'a');
        return 1;
    }
    
    return 0;
}
