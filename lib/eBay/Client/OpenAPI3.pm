package eBay::Client::OpenAPI3;

use strict;
use warnings;

use JSON;
use URI qw/query_form/;
use HTTP::Tiny;
use HTTP::Status;
use MIME::Base64;
use Util::H2O::More qw/baptise d2o ddd HTTPTiny2h2o h2o ini2h2o o2h/;

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

sub warn_if_exists {
  my ($self, $headers, $header) = @_;
  if (exists $headers->{$header}) {
    warn sprintf("WARNING: '%s' detected: %s\n\n", $header, $headers->{$header})
  }
}

sub _defined_params {
    my (%params) = @_;
    return map { defined $params{$_} ? ( $_ => $params{$_} ) : () } keys %params;
}

sub _error_message_from_json {
    my ($json) = @_;
    return eval { $json->errors->get(0)->longMessage }
        // eval { $json->{errors}->[0]{longMessage} }
        // q{Unknown error};
}

# Call limit for all Browse APIs is 5,000 / day
#   https://developer.ebay.com/develop/apis/api-call-limits

sub get_ua {
    my ($self)          = @_;
    my $auth_token      = sprintf qq{Bearer %s}, $self->token->access_token;
    my $options         = {
        default_headers    => {
            'Accept'                  => q{*/*},
            'Authorization'           => $auth_token,
            'X-EBAY-C-MARKETPLACE-ID' => 'EBAY_US',
            'X-EBAY-C-ENDUSERCTX'     => sprintf('affiliateCampaignId=%s', $self->config->eBay->affiliateCampaignId),
        },
        # define API scopes enabled by this token
        content => undef,
    };
    my $ua              = HTTP::Tiny->new(%$options);
    return $ua;
}

# https://api.ebay.com/developer/analytics/v1_beta/rate_limit?api_name=browse
sub rate_limit {
    my ($self, %params) = @_;
    my $ua              = $self->get_ua; 
    my $uri             = URI->new('', 'http');
    $uri->query_form(_defined_params(%params));
    my $URL             = sprintf qq{%s/%s?%s}, $EBAY_ENDPOINT_BASE, q{developer/analytics/v1_beta/rate_limit}, $uri->query;

    my $resp = h2o $ua->get($URL);

    my $raw = $resp->content;
    my $json        = d2o from_json $raw;

    if (not is_success($resp->status)) {
      $self->warn_if_exists($resp->headers, "x-ebay-api-call-limit");
      $self->warn_if_exists($resp->headers, "x-ebay-api-throttle-limit");
      $self->warn_if_exists($resp->headers, "x-ebay-api-throttle-remaining");
      my $status = $resp->status;
      my $msg = _error_message_from_json($json);
      die "$msg (HTTP Status: $status)\n";
    }

    return $json;
}

# getItem (part of the 'Browse' API); only gets one item at a time
sub getItem {
    my ($self, %params) = @_;
    my $params = h2o \%params, qw/itemid/;
    my $URL             = sprintf qq{%s/%s/v1|%s|0}, $EBAY_ENDPOINT_BASE, q{buy/browse/v1/item}, $params->itemid;

    my $ua   = $self->get_ua;
    my $resp = HTTPTiny2h2o $ua->get($URL);

    # error handling
    if (not is_success($resp->status)) {
      $self->warn_if_exists($resp->headers, "x-ebay-api-call-limit");
      $self->warn_if_exists($resp->headers, "x-ebay-api-throttle-limit");
      $self->warn_if_exists($resp->headers, "x-ebay-api-throttle-remaining");
      my $status = $resp->status;
      my $msg = eval { $resp->content->errors->get(0)->longMessage } // "Unknown error";
      die "$msg (HTTP Status: $status)\n";
    }

    return $resp->content;;
}

# https://developer.ebay.com/api-docs/buy/browse/resources/item_summary/methods/search
sub browse {
    my ($self, %params) = @_;
    my $ua              = $self->get_ua; 
    my $uri             = URI->new('', 'http');
    $uri->query_form(_defined_params(%params));
    my $URL             = sprintf qq{%s/%s?%s}, $EBAY_ENDPOINT_BASE, q{buy/browse/v1/item_summary/search}, $uri->query;
    my $resp = h2o $ua->get($URL);

    my $raw = $resp->content;
    my $json         = from_json $raw;
    $json->{next}    = $json->{next}      // undef;  # d2o should probably allow some top level
    $json->{total}   = $json->{total}     // undef;  # default accessors to be defined
    $json->{warnings} = $json->{warnings} // [];     # default accessors to be defined
    $json->{errors}   = $json->{errors}   // [ { longMessage => undef } ];
    $json = d2o $json;

    if (not is_success($resp->status)) {
      $self->warn_if_exists($resp->headers, "x-ebay-api-call-limit");
      $self->warn_if_exists($resp->headers, "x-ebay-api-throttle-limit");
      $self->warn_if_exists($resp->headers, "x-ebay-api-throttle-remaining");
      my $status = $resp->status;
      my $msg = _error_message_from_json($json);
      die "$msg (HTTP Status: $status)\n";
    }

    # capture the next URL as member, "next"
    $self->next($json->next);
    $self->total($json->total);

    return $json;
}

1;

__END__

=head1 NAME

eBay::Client::OpenAPI3 - Lightweight client for eBay Browse API (item_summary/search)

=head1 VERSION

0.01

=head1 SYNOPSIS

  use eBay::Client::OpenAPI3;

  my $ec = eBay::Client::OpenAPI3->new(
    config => {
      oauth2_token => '...',
    }
  );

  my $res = $ec->browse(
    category_ids => '13956',
    q            => 'patch insignia SSI',
    filter       => 'buyingOptions:{AUCTION}',
    limit        => 50,
    offset       => 0,
    sort         => 'newlyListed',
  );

=head1 DESCRIPTION

C<eBay::Client::OpenAPI3> is a lightweight Perl client for the eBay Browse API
C<item_summary/search> endpoint.

It is intended for data ingestion workflows where simple access to listings is
required, supporting category filtering, keyword search, pagination, and filter
expressions.

This module does not attempt to fully abstract the API; parameters are passed
through with minimal transformation.

=head1 METHODS

=head2 new

  my $ec = eBay::Client::OpenAPI3->new( config => \%config );

Constructs a new client instance.

The C<config> hashref must include authentication credentials, typically an
OAuth2 token:

  oauth2_token => '...'

=head2 browse

  my $res = $ec->browse(%params);

Executes a request against:

  /buy/browse/v1/item_summary/search

Parameters are passed directly to the API. Supported parameters include:

=over 4

=item * category_ids

Comma-separated list of eBay category IDs.

=item * q

Keyword search string. Space-separated terms are recommended. The eBay API uses
relevance-based matching and does not guarantee strict boolean behavior.

=item * filter

Filter expression string (e.g., C<buyingOptions:{AUCTION}>,
C<price:[10..100]>). Multiple filters may be combined with commas.

=item * limit

Number of results per request (maximum 200).

=item * offset

Pagination offset.

=item * sort

Sort order. Common values include:

  newlyListed
  endingSoonest
  price
  -price

=back

Undefined parameters are omitted from the request automatically.

Returns a decoded JSON structure, converted to an object via C<d2o>.

=head2 rate_limit

  my $info = $ec->rate_limit;

Fetches API rate limit information from:

  /buy/browse/v1/rate_limit

Returns a decoded JSON structure.

=head1 ERROR HANDLING

If the API returns an error response, this module attempts to extract a
meaningful message from the JSON payload (C<errors[0].longMessage>). If not
available, the HTTP response reason is used.

=head1 NOTES

=over 4

=item *

The eBay Browse API does not support strict boolean logic in the C<q> parameter.
For broader coverage, multiple queries should be executed separately.

=item *

Filter expressions follow eBay API syntax and are passed through without
validation.

=item *

This module is intentionally minimal and does not perform schema validation or
result normalization.

=back

=head1 DEPENDENCIES

=over 4

=item * L<HTTP::Tiny>

=item * L<JSON>

=item * L<URI>

=item * L<Util::H2O::More>

=back

=head1 BUGS & LIMITATIONS

Please report bugs on Github.

L<< https://github.com/oodler577/p5-eBay-Client-OpenAPI3/issues >>

=head1 AUTHOR

Brett Estrade L<< <brett@acutisdata.com> >>

The author of this utlity and module may be contracted for very reasonable rates
by anyone wishing to significantly extend it or the underlying module - provided
the changes may be incorporated into the public version of this module. Please
email the author at the email listed below if interested.


=head1 LICENSE & COPYRIGHT

Same as Perl/C<perl>.

