# Autoconsent Coverage Data

This folder contains statistics gathered from running crawls with autoconsent active, to determine which rules trigger on which sites.
The crawler uses [tracker-radar-collector](https://github.com/duckduckgo/tracker-radar-collector/) to crawl a list of the top 10k sites for US, DE and GB regions.
The results report how many sites in this list the rule triggered for, and some error counts.

## Data format

In `coverage.json` the data is included as a JSON object. Keys correspond to rule names and contain stats for `US`, `DE` and `GB` regions, where applicable.
The stats contain the following keys:
 - `sites`: Number of sites where this rule was triggered (`detectCmp` was true).
 - `errors`: Count of sites where an error occured processing the rule.
 - `selfTestFailures`: If the rule has a self-test, and it didn't return true after opting out.
 - `exampleSites`: A list of up to 5 example sites where this rule applies when accessing from this region.
 - `failingSites`: A list of up to 5 sites where the self test is failing.
 - `errorSites`: A list of up to 5 sites where an error occured.
