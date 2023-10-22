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
    my $self = baptise \%opts, $pkg, qw/config token/;
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
    my $json = $response->content;
    return $json;
}

1;

__END__

=head1 eBay::Client::OpenAPI3 - unambitious Perl client for eBay's "OpenAPI3" version of APIs

