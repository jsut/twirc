package App::Twirc::Plugin::Search;
use Moose;
use Data::Dumper;
use POE;
use App::Twirc::Plugin::Search::Session;
use HTML::Entities;

has bot_messages => (
    isa     => 'ArrayRef[HashRef]',
    is      => 'rw',
    default => sub { [] } ,
);

has session => (
    isa     => 'Object',
    is      => 'rw',
);

sub plugin_traits {
    return qw/API::Search/
}

sub create_poe_session {
    my $self = shift;
    my ($twirc, $channel, $nick, $text) = @_;
    $twirc->log->debug('create session');
    if (!$self->session) {
        $twirc->log->debug('creating session');
        $self->session(App::Twirc::Plugin::Search::Session->new(
            twirc  => $twirc,
            plugin => $self,
        ));
    }
    $twirc->log->debug('session exists');
}

#
# register_search
#
# if there isn't already a search registered for the text you enter, then this
# will stuff the search term into the saves searches array, and cause the
# search to be executed as well.  If the search is already registered, it
# tells you that.
#
sub cmd_register_search {
    my $self = shift;
    my ($twirc, $channel, $nick, $text) = @_;
    $twirc->log->debug('register_search');
    if (!$self->session) {
        $self->create_poe_session($twirc,$channel,$nick,$text);
    }

    if (grep {$_->{'text'} eq $$text} @{$self->session->saved_searches} ) {
        push @{ $self->bot_messages }, {
            channel => $channel,
            text    => qq[There is already a search registered for $$text],
        };
        return $self->say_bot_messages($twirc);
    }

    push @{$self->session->saved_searches}, {
        channel => $channel,
        text    => $$text,
        max_id => undef,
    };

    push @{ $self->bot_messages }, {
        channel => $channel,
        text    => qq[A search has been registered for $$text],
    };


    return $self->cmd_search($twirc, $channel, $nick, $text);
}

#
# view_searches
#
# view your list of saved searches
#
sub cmd_view_searches {
    my $self = shift;
    my ($twirc, $channel, $nick, $text) = @_;
    $twirc->log->debug('view_searches');

    if ($self->session && $self->session->saved_searches) {
        push @{ $self->bot_messages }, {
            channel => $channel,
            text    => q[Your saved searches are:],
        };
        foreach my $saved_search (@{$self->session->saved_searches} ) {
            $twirc->log->debug(Dumper($saved_search));
            push @{ $self->bot_messages }, {
                channel => $channel,
                text    => $saved_search->{'text'}, 
            };
        };
    }
    else {
        push @{ $self->bot_messages }, {
            channel => $channel,
            text    => q[No saved searches found.],
        };
    }

    return $self->say_bot_messages($twirc);
}

#
# delete_search
#
# remove a saved search
#
sub cmd_delete_search {
    my $self = shift;
    my ($twirc, $channel, $nick, $text) = @_;
    $twirc->log->debug('delete_search');

    if (!$self->session) {
        push @{ $self->bot_messages }, {
            channel => $channel,
            text    => qq[You have no saved searches],
        };
        return $self->say_bot_messages($twirc);
    }

    my @searches = grep {$_->{'text'} ne $$text} @{$self->session->saved_searches};

    if (scalar @searches == scalar @{$self->session->saved_searches} ) {
        push @{ $self->bot_messages }, {
            channel => $channel,
            text    => qq[$$text is not a saved search],
        };
        return $self->say_bot_messages($twirc);
    }

    $self->session->saved_searches(\@searches);
    push @{ $self->bot_messages }, {
        channel => $channel,
        text    => qq[The saved search for $$text has been removed],
    };
    return $self->say_bot_messages($twirc);
}

#
# search
#
# do a search right now please and thank you.
#
sub cmd_search {
    my $self = shift;
    my ($twirc, $channel, $nick, $text) = @_;
    $twirc->log->debug('search');
    return $self->do_search($twirc,$channel,$$text)
}

#
# show_trends
#
# requires 1 argument, which is the type of trend you want to see
# twitter currently provides generic trends, current, and weekly not currently
# implemented
#
sub cmd_show_trends {
    my $self = shift;
    my ($twirc, $channel, $nick, $text) = @_;
    $twirc->log->debug('show_trends');
    return 1;
}

#########################
#
# Helper functions
#
#########################

#
# do_search
#
# performs a search, and pushes it's results onto bot_messages
#
sub do_search {
    my ($self,$twirc,$channel,$text,%opts) = @_;

    if (!$opts{'since_id'}) {
        $opts{'rpp'} = 10;
    }

    my $results = $twirc->_twitter->search($text, \%opts);
    unless ( $results ) {
        $self->twitter_error("search failed");
        return;
    }
    #
    # if this is a saved search, update the max_id of the search
    #
    if ($self->session &&
            (my @res = grep {$_->{'text'} eq $text} @{$self->session->saved_searches})) {
        my $search = shift @res;
        $search->{'max_id'} = $results->{'max_id'};
    }

    push @{$self->bot_messages}, (
        {
            channel => $channel,
            text    => qq[Search results for "$text"],
        },
    );
    $twirc->log->debug(qq[found ] . scalar @{$results->{'results'}} .
        qq[ results for search $text]
    );
    return $self->say_search_results($twirc,$channel,$results,$text);
}

#
# say_search_results
#
# adds the messages that we want the bot to say to $self->bot_messages, and
# then calls say_bot_messages.  This is split up the way it is because i think
# (but am not sure) that it would make sense to have some yield's in here, but
# since i'm not really sure how to do that, it'll just chain itself together
#
sub say_search_results {
    my $self = shift;
    my ($twirc, $channel, $results, $text) = @_;
    #
    # stuff all the messages into an array in the format that bot_messages
    # likes
    #
    my @messages;
    foreach my $tweet (@{$results->{'results'}}) {
        my @lines = split /[\r\n]+/, decode_entities($tweet->{'text'});
        foreach my $line (@lines) {
            next if !$line;
            push @messages , {
                channel => $channel,
                text    => qq[\@$$tweet{'from_user'}: $line],
            };
        }
    }
    push @{$self->bot_messages},@messages;
    return $self->say_bot_messages($twirc);
}

#
# say_bot_messages
#
# this function pushes all the queued bot messages out to the channel
#
sub say_bot_messages {
    my ($self,$twirc) = @_;

    $twirc->log->debug("[say_bot_messages] ", scalar @{$self->bot_messages}, " messages");

    for my $entry ( @{$self->bot_messages} ) {
        $twirc->bot_says(
            $entry->{'channel'},
            $entry->{'text'},
        );
    }

    $self->bot_messages([]);
    return 1;
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

App::Twirc::Plugin::Search - A search interface for twirc

=head1 SYNOPSIS

In your twirc config file add 'Search' to your plugins list.  For example if
you are using a YAML config file, you could add these two lines:

    plugins:
    - Search

=head1 DESCRIPTION

ATP::Search adds a number of search API related commands to twirc.  Since the
results of searches most often come from users that you are not following the
tweets are echoed by the bot.

=head1 COMMANDS

=head2 search <search text>

search does an immediate search and returns the 10 most recent results
matching your search term.

=head2 register_search <search text>

register_search does an immediate search, and makes twirc save the search and
post new entries that match your search as they show up.  Searches are redone
based on your twitter retry setting, which defaults to 300 seconds.

=head2 view_searches

view_searches shows you all your saved searches.

=head2 delete_search <search text>

delete_search removes a saved search.

=head1 AUTHOR

Adam Prime <adam.prime@utoronto.ca>

=head1 LICENSE

Copyright (c) 2009 Adam Prime

You may distribute this code and/or modify it under the same terms as Perl
itself.
