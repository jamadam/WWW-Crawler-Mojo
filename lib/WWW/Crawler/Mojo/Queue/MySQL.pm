package WWW::Crawler::Mojo::Queue::MySQL;
use strict;
use warnings;
use utf8;
use Mojo::Base 'WWW::Crawler::Mojo::Queue';
use Mojo::mysql;
use Storable qw(freeze thaw );

 
has table_name => 'jobs';
has jobs => '';
has blob => 0;

sub new { 
	my ($self, $connection, $table) = @_;

	die "USAGE: WWW::Crawler::Mojo::Queue::MySQL->new( 'mysql://user:pass\@server/db', 'jobs_table' ) "unless $connection;

	my $object = shift->SUPER::new( jobs => Mojo::mysql->new( $connection )->db );
	
	$object->table_name($table) if $table;

	$table = $object->table_name;

	unless ($object->jobs->query("show tables LIKE '$table'" )->rows) {

		$object->jobs->query( "create table $table (id integer auto_increment primary key, digest varchar(255) , data blob, completed boolean , unique key digested(digest, completed))");
	}
	return $object;

}
sub empty {

	my $self = shift;
	my $table = $self->table_name;
	$self->jobs->query( "delete from $table");
}

has redundancy => sub {
	my %fix;
    
	return sub {
		my $d = $_[0]->digest;
		return 1 if $fix{$d};
		$fix{$d} = 1;
		return;
	};	
#	return sub {
#        my $d = $_[0]->digest;
#		return 1 if $self->jobs->query("select count(id) from $table where digest = ?", $d)->rows 
#		$self->jobs->query("insert into $table (digest) values(?)"), $d);
#        return;
#    };
};

sub serialize { (shift->blob) ? freeze(shift) :  shift->url->to_string }
sub deserialize { (shift->blob) ? thaw(shift) :  WWW::Crawler::Mojo::Job->new( url => Mojo::URL->new(shift) ) }

sub dequeue {
	
	my $self = shift;
	my $table = $self->table_name;

	my $last;
	eval {
		my $tx = $self->jobs->begin;
		$last = $self->jobs->query("select id, data from $table where completed = 0 order by id limit 1" )->hash;
		$self->jobs->query("update $table set completed = 1 where id = ?", $last->{id}) if $last->{id};
		$tx->commit;
	};
    return ($last->{id}) ? $self->deserialize($last->{data}) :  "";
}
 
sub enqueue {
    shift->_enqueue(@_);
}
 
sub length {
	my $self = shift;
	my $table = $self->table_name;

    return $self->jobs->query("select count(id) AS total from $table where completed = 0")->hash->{total};
}
 
sub next {
	my ($self, $offset, $future) = @_;
	my $table = $self->table_name;
	
	$offset = $offset || 0;

	my $d = $self->jobs->query("select data from $table where completed = 0 order by id limit ? ", $offset + 1 )->arrays->[ $offset ]->[0];

    return ($d) ? $self->deserialize($d)  : "";
}
 
sub requeue {
    my ($self, $job ) = @_;
    $self->_enqueue($job, 1);
}
 
sub shuffle { }
 
sub _enqueue {
    my ($self, $job, $requeue) = @_;
	my $table = $self->table_name;
    return if (!$requeue && $self->redundancy->($job));
	eval {
		my $tx = $self->jobs->begin;
		$self->jobs->query("delete from $table where completed = 1 and digest = ?", $job->digest) if $requeue;
		$self->jobs->query("insert into $table (digest, data, completed) values(?,?,?)", $job->digest, $self->serialize($job), 0 );
		$tx->commit;
	};
    return $self;
}
 
1;
 
