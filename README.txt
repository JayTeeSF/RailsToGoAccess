Given Rails logs (like mine) which have a transaction_id (to help me stitch requests together -- even across servers)

When you 'brew install goaccess'
And update it's config file w/ an appropriate log-format line (see below)

Then:
Run your logs (possibly many of them at once* via a 'glob': unix wildcard) through this script, in order to make a slightly
extended NCSA Combiled Log Format, specifically append "%T" ...unfortunately we don't actually have %b (bytes sent) from the rails log.
log-format %h %^[%d:%t %^] "%r" %s %b "%R" "%u" "%T"


*Note: I have my servers upload hourly logs to S3 w/ UTC times 
Beware, this script is a hack, it assumes the logs are in UTC, and converts them to PT

e.g.

# convert your Rails weblog:
./convert_rails_trx_id_logs.rb '../path/to/downloaded/logs/2017_01_2[67]/i-*' ./rails_access_20170126.weblog

# pass that log to goaccess
cat tmp/rails_access_20170126.weblog | goaccess --date-spec=hr --max-items=366 -a -o public/rails_jan26.html

Beware: this is a very custom hacky script. It will just as easily blow-up your system as do what I'm suggesting.
So use at your own risk.

Instead, read the code, fork it, make adjustments to the regex's (think rubular.com)
and make your own version.

Better yet, make generic version and open-source it, for everyone to use :-)
