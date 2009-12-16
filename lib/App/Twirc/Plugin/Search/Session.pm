package App::Twirc::Plugin::Search::Session;

use MooseX::POE;
use Data::Dumper;

has saved_searches => (
    isa     => 'ArrayRef[HashRef]',
    is      => 'rw',
    default => sub { [] } ,
);

has twirc => (
    isa       => 'Object',
    is        => 'ro',
    required  => 1,
);

has plugin => (
    isa       => 'Object',
    is        => 'ro',
    required  => 1,
);

#
# START
#
# this function is run on object creation.
#
sub START {
    my ($self) = @_;
    $self->twirc->log->debug('START');
    $_[KERNEL]->delay(recurring_searches => $self->twirc->twitter_retry);
}

#
# recurring_searches
# 
# the core loop, which causes all of the saved_searches to be reperformed
# every twitter_retry seconds
#
event recurring_searches => sub {
    my ($self) = @_;
    $self->twirc->log->debug('do_recurring_searches');

    foreach my $search (@{$self->saved_searches}) {
        $self->do_recurring_search($search);
    }

    $_[KERNEL]->delay(recurring_searches => $self->twirc->twitter_retry);
};

#
# do_recurring_search
#
# this function actually performs a recurring search. then hands the results
# back to the plugin itself to do the output to the channel
#
event do_recurring_search => sub {
    my ($self,$search) = @_;
    
    $self->twirc->log->debug(Dumper($search));
    
    my $results = $self->twirc->_twitter->search(
        $search->{'text'},
        {
            since_id => $search->{'max_id'},
        }
    );
    unless ( $results ) {
        $self->twirc->twitter_error("search failed");
        return;
    }

    $self->twirc->log->debug(Dumper($results));
    $self->plugin->say_search_results(
        $self->twirc,
        $search->{'channel'},
        $results,
    );
    if ($results->{'max_id'} && $results->{'max_id'} > $search->{'max_id'}) {
        $search->{'max_id'} = $results->{'max_id'};
    }
};

no MooseX::POE;

__END__

=head1 NAME

App::Twirc::Plugin::Search::Session - MooseX::POE session for ATP::Search

=head1 DESCRIPTION

ATP::Search::Session is used by ATP::Search to provide recurring searching
functionality.  It is not meant to be used directly

=head1 AUTHOR

Adam Prime <adam.prime@utoronto.ca>

=head1 LICENSE

Copyright (c) 2009 Adam Prime

You may distribute this code and/or modify it under the same terms as Perl
itself.



