This is a work in progress, may eventually find its
way to CPAN, even if it only currently supports getting
and API token.

Using this client:

1. get eBay API credentials and put them in `$HOME/.ebayapi3.conf` (or some other file and use `--config` to specify for the client);
the file is an INI format, and requires this section and variables defined:

```
[eBay]
client_id = your-client-key
client_secret = your-secret-key
```

2. example call,

```
# Vintage Computing - JukeBoxs and arcades
ebayapi3 browse --limit 200 --category_ids 66502 --stats --as json --continue > data-dump.json
```
