package eBay::Client::OpenAPI3;

use strict;
use warnings;

use JSON;
use URI qw/query_form/;
use HTTP::Tiny;
use MIME::Base64;
use Util::H2O::More qw/baptise d2o ddd h2o ini2h2o/;

our $EBAY_ENDPOINT_BASE = q{https://api.ebay.com};

sub new {
    my $pkg  = shift;
    my %opts = @_;
    my $self = baptise \%opts, $pkg, qw/config next token total/;
    die qq{configuration file not found\n} if not -e $self->config;
    my $config_file = $self->config;        # initially, ->config is just a string file name
    $self->config(ini2h2o $config_file);    # then it becomes an actual Config::Tiny object with accessors
    return $self;
}

sub oauth2 {
    my ($self)        = @_;
    my $ua            = HTTP::Tiny->new();
    my $URL           = sprintf qq{%s/%s},    $EBAY_ENDPOINT_BASE, q{identity/v1/oauth2/token};
    my $authorization = sprintf qq{%s:%s},    $self->config->eBay->client_id, $self->config->eBay->client_secret;
    my $auth_token    = sprintf qq{Basic %s}, encode_base64( $authorization, q{} );
    my $options       = {
        headers => {
            'Content-Type'  => q{application/x-www-form-urlencoded},
            'Authorization' => $auth_token,
        },

        # define API scopes enabled by this token
        content => q{grant_type=client_credentials&scope=https://api.ebay.com/oauth/api_scope},
    };

    my $resp = h2o $ua->post($URL, $options);
    my $full = h2o JSON::from_json $resp->content;

    # set token member
    $self->token($full);

    # return $self, for chaining
    return $self;
}

# https://developer.ebay.com/api-docs/buy/browse/resources/item_summary/methods/search

#NOTE: "browser" is not meant to be a generic kitchen sink; if implementing your own "browse"
sub browse {
    my ($self, %params) = @_;
    my $ua              = HTTP::Tiny->new();
    my $uri             = URI->new('', 'http');
    $uri->query_form(%params);
    my $URL             = sprintf qq{%s/%s?%s}, $EBAY_ENDPOINT_BASE, q{buy/browse/v1/item_summary/search}, $uri->query;
    my $auth_token      = sprintf qq{Bearer %s}, $self->token->access_token;
    my $options         = {
        headers    => {
            'Accept'                  => q{*/*},
            'Authorization'           => $auth_token,
            'X-EBAY-C-MARKETPLACE-ID' => 'EBAY_US',
            'X-EBAY-C-ENDUSERCTX'     => sprintf('affiliateCampaignId=%s', $self->config->eBay->affiliateCampaignId),
        },

        # define API scopes enabled by this token
        content => undef,
    };
    my $response = h2o $ua->get($URL, $options);;
    my $raw = $response->content;
    my $json = d2o from_json $raw;

    # capture the next URL as member, "next"
    $self->next($json->next);
    $self->total($json->total);

    return $json;
}

1;

__END__

=head1 eBay::Client::OpenAPI3 - unambitious Perl client for eBay's "OpenAPI3" version of APIs

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head1 SUPPORTED APIs

=head1 BUGS & SUPPORT REQUESTS

Please report bugs on Github.

L<< https://github.com/oodler577/p5-eBay-Client-OpenAPI3/issues >>

The author of this utlity and module may be contracted for very reasonable rates
by anyone wishing to significantly extend it or the underlying module. For
requests of this nature, please email the author at the email listed below.

=head1 AUTHOR

Oodler 577 L<< <oodler@cpan.org> >>

=head1 LICENSE & COPYRIGHT

Same as Perl/C<perl>.
